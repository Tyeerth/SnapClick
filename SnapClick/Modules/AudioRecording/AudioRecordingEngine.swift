// AudioRecordingEngine.swift
// SnapClick - 音频录音核心引擎
// 采集麦克风（AVCaptureSession）+ 系统音频（macOS 13+ ScreenCaptureKit，Phase 3 接入）
// 编码为 M4A / AAC，实时电平反馈、暂停/继续/停止/取消
// 与 ScreenRecordingEngine 互斥（不可同时运行，避免 SCK 资源争抢）

@preconcurrency import AVFoundation
import AppKit
import Combine
@preconcurrency import ScreenCaptureKit

// MARK: - 录音错误

enum AudioRecordingError: LocalizedError {
    case permissionDenied(String)
    case noMicrophoneAvailable
    case systemAudioNotSupported
    case alreadyRecording
    case notRecording
    case engineStartFailed(String)
    case writeFailed(String)
    case noAudioData
    case userCancelled
    case conflictWithScreenRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let kind):  return "缺少权限：\(kind)"
        case .noMicrophoneAvailable:       return "未找到可用的麦克风设备"
        case .systemAudioNotSupported:     return "系统音频录制需要 macOS 13 或更高版本"
        case .alreadyRecording:            return "音频录音已在进行中"
        case .notRecording:                return "当前没有进行录音"
        case .engineStartFailed(let m):    return "录音引擎启动失败：\(m)"
        case .writeFailed(let m):          return "写入录音文件失败：\(m)"
        case .noAudioData:                 return "未捕获到任何音频数据"
        case .userCancelled:               return "用户取消了录音"
        case .conflictWithScreenRecording: return "屏幕录制进行中，请先停止屏幕录制再开始音频录音"
        }
    }
}

// MARK: - 音频录音引擎

@MainActor
final class AudioRecordingEngine: NSObject, ObservableObject {

    // MARK: 单例

    static let shared = AudioRecordingEngine()

    // MARK: 公开状态

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    /// 麦克风实时电平（0.0 ~ 1.0）
    @Published private(set) var micLevel: Float = 0
    /// 系统音频实时电平（0.0 ~ 1.0）
    @Published private(set) var systemLevel: Float = 0

    // MARK: 私有属性

    private var assetWriter: AVAssetWriter?
    private var micInput: AVAssetWriterInput?
    private var systemInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var durationTimer: AnyCancellable?
    private var firstSample = true
    private var timeOffset: CMTime = .zero
    private var lastAppendedPTS: CMTime = .zero

    // 麦克风采集
    private var micSession: AVCaptureSession?
    private var micDevice: AVCaptureDevice?

    // 系统音频采集（macOS 13+）
    private var systemStream: SCStream?
    private var systemSampleRate: Int = 44_100
    private var systemChannelCount: Int = 2

    // MARK: 初始化

    private override init() {
        super.init()
    }

    // MARK: - 公开接口

    /// 开始录音。
    /// - Parameter withCountdown: 是否在开始前显示倒计时（默认按设置项）
    func startRecording(withCountdown: Bool? = nil) async throws {
        guard !isRecording else { throw AudioRecordingError.alreadyRecording }

        // 互斥检查：录屏进行中不允许开始录音
        await MainActor.run {
            if ScreenRecordingEngine.shared.isRecording {
                // 直接抛错，调用方弹窗
            }
        }
        if ScreenRecordingEngine.shared.isRecording {
            throw AudioRecordingError.conflictWithScreenRecording
        }

        let settings = AppSettings.shared

        // 权限校验
        let needMic = (settings.audioRecordMicrophone != "无")
        if needMic {
            let micGranted: Bool
            if #available(macOS 14.0, *) {
                micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            } else {
                micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }
            if !micGranted {
                throw AudioRecordingError.permissionDenied("麦克风")
            }
        }
        if settings.audioRecordSystemAudio {
            if #available(macOS 13.0, *) {
                // SCK 系统音频不依赖屏幕录制权限，但若两者都想用，需要屏幕录制权限
                // 这里仅系统音频不需要
            } else {
                throw AudioRecordingError.systemAudioNotSupported
            }
        }

        // 倒计时（如设置）
        let useCountdown = withCountdown ?? (settings.audioRecordCountdown > 0)
        if useCountdown {
            try await performCountdown()
        }

        // 解析目标麦克风
        if needMic {
            guard let device = resolveMicrophone() else {
                throw AudioRecordingError.noMicrophoneAvailable
            }
            self.micDevice = device
        }

        // 准备输出文件
        try prepareOutputURL()

        // 启动 AVAssetWriter + 音频输入轨
        try setupAssetWriter()

        // 启动麦克风采集
        if needMic, let device = micDevice {
            startMicrophoneCapture(device: device)
        }

        // 启动系统音频采集（可选）
        if settings.audioRecordSystemAudio, #available(macOS 13.0, *) {
            try await startSystemAudioCapture()
        }

        // 进入录音态
        isRecording = true
        isPaused = false
        recordingDuration = 0
        firstSample = true
        timeOffset = .zero
        lastAppendedPTS = .zero

        durationTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.isPaused {
                    self.recordingDuration += 1
                }
            }

        NotificationCenter.default.post(name: .audioRecordingDidStart, object: nil)
    }

    /// 暂停录音
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
    }

    /// 继续录音
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        // 恢复时让下一帧重新计算 timeOffset，补偿暂停期间缺失的时间
        if lastAppendedPTS != .zero {
            let nowPTS = CMClockGetTime(CMClockGetHostTimeClock())
            let gap = nowPTS - lastAppendedPTS
            if gap > .zero {
                timeOffset = timeOffset + gap
            }
        }
    }

    /// 停止并保存录音文件
    func stopRecording() async throws -> URL {
        guard isRecording else { throw AudioRecordingError.notRecording }

        isRecording = false
        isPaused = false

        // 停止采集
        stopMicrophoneCapture()
        if #available(macOS 13.0, *) {
            await stopSystemAudioCapture()
        }

        // 停计时器
        durationTimer?.cancel()
        durationTimer = nil

        // 等待已飞行的帧任务
        try await Task.sleep(nanoseconds: 200_000_000)

        // 如果没有任何音频数据
        if firstSample {
            cleanupEmptyRecording()
            throw AudioRecordingError.noAudioData
        }

        micInput?.markAsFinished()
        systemInput?.markAsFinished()

        let writer = assetWriter
        self.assetWriter = nil
        await writer?.finishWriting()

        if writer?.status == .failed {
            let reason = writer?.error?.localizedDescription ?? "未知错误"
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            throw AudioRecordingError.writeFailed(reason)
        }

        // 复位
        firstSample = true
        timeOffset = .zero
        lastAppendedPTS = .zero
        micLevel = 0
        systemLevel = 0

        NotificationCenter.default.post(name: .audioRecordingDidStop, object: nil)

        guard let url = outputURL else {
            throw AudioRecordingError.writeFailed("输出路径为空")
        }
        return url
    }

    /// 取消录音并删除文件
    func cancelRecording() async throws {
        guard isRecording else { throw AudioRecordingError.notRecording }
        do {
            _ = try await stopRecording()
        } catch AudioRecordingError.noAudioData {
            // 无音频数据已无文件可删，直接走清理流程
        } catch {
            // 其他错误也允许 cancel 走完
            print("[AudioRecordingEngine] cancel 时 stop 出错: \(error)")
        }
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
    }

    // MARK: - 私有：倒计时

    private func performCountdown() async throws {
        let seconds = AppSettings.shared.audioRecordCountdown
        guard seconds > 0 else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let window = RecordingCountdownWindow(
                seconds: seconds,
                onFinished: { continuation.resume() },
                onCancelled: { continuation.resume(throwing: AudioRecordingError.userCancelled) }
            )
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
    }

    // MARK: - 私有：解析麦克风设备

    private func resolveMicrophone() -> AVCaptureDevice? {
        let settings = AppSettings.shared
        let name = settings.audioRecordMicrophone
        guard name != "无" else { return nil }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        // 优先按名字精确匹配
        if let matched = session.devices.first(where: { $0.localizedName == name }) {
            return matched
        }
        // 退回到第一个可用设备
        return session.devices.first
    }

    /// 枚举所有可用输入设备（用于设置页 Picker）
    static func availableMicrophones() -> [String] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { $0.localizedName }
    }

    // MARK: - 私有：准备输出文件

    private func prepareOutputURL() throws {
        let settings = AppSettings.shared
        let saveDir = SandboxManager.shared.writableURL(for: settings.audioRecordSavePath)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let baseName = "SnapClick_录音_\(formatter.string(from: Date()))"
        var fileURL = saveDir.appendingPathComponent(baseName).appendingPathExtension("m4a")

        // 冲突重命名：SnapClick_录音_xxx.m4a → SnapClick_录音_xxx_2.m4a → ...
        var counter = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            let newName = "\(baseName)_\(counter)"
            fileURL = saveDir.appendingPathComponent(newName).appendingPathExtension("m4a")
            counter += 1
        }

        self.outputURL = fileURL
    }

    // MARK: - 私有：初始化 AVAssetWriter

    private func setupAssetWriter() throws {
        guard let outputURL = outputURL else {
            throw AudioRecordingError.engineStartFailed("输出路径为空")
        }

        let settings = AppSettings.shared
        let quality = AudioQuality(rawValue: qualityRawToEnum(settings.audioRecordQuality)) ?? .standard
        let sampleRate = settings.audioRecordSampleRate
        let channels = settings.audioRecordChannels
        systemSampleRate = sampleRate
        systemChannelCount = channels

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        self.assetWriter = writer

        // 麦克风轨（如果启用）
        if let _ = micDevice {
            let micSettings: [String: Any] = [
                AVFormatIDKey:          kAudioFormatMPEG4AAC,
                AVSampleRateKey:        sampleRate,
                AVNumberOfChannelsKey:  channels,
                AVEncoderBitRateKey:    quality.bitrate,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            input.expectsMediaDataInRealTime = true
            self.micInput = input
            if writer.canAdd(input) {
                writer.add(input)
            }
        }

        // 系统音频轨（Phase 3 实际使用）
        if settings.audioRecordSystemAudio, #available(macOS 13.0, *) {
            let sysSettings: [String: Any] = [
                AVFormatIDKey:          kAudioFormatMPEG4AAC,
                AVSampleRateKey:        sampleRate,
                AVNumberOfChannelsKey:  channels,
                AVEncoderBitRateKey:    quality.bitrate,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: sysSettings)
            input.expectsMediaDataInRealTime = true
            self.systemInput = input
            if writer.canAdd(input) {
                writer.add(input)
            }
        }

        guard writer.startWriting() else {
            let reason = writer.error?.localizedDescription ?? "未知错误"
            throw AudioRecordingError.writeFailed("无法开始写入：\(reason)")
        }
    }

    private func qualityRawToEnum(_ raw: String) -> String {
        switch raw {
        case "经济":   return AudioQuality.economy.rawValue
        case "高质量": return AudioQuality.high.rawValue
        default:       return AudioQuality.standard.rawValue
        }
    }

    // MARK: - 私有：清理空录音

    private func cleanupEmptyRecording() {
        micInput?.markAsFinished()
        systemInput?.markAsFinished()
        let writer = assetWriter
        self.assetWriter = nil
        writer?.cancelWriting()
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
        firstSample = true
        timeOffset = .zero
        lastAppendedPTS = .zero
        micLevel = 0
        systemLevel = 0
        NotificationCenter.default.post(name: .audioRecordingDidStop, object: nil)
    }

    // MARK: - 私有：麦克风采集

    private func startMicrophoneCapture(device: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureAudioDataOutput()

            // 显式指定 Float32 线性 PCM 输出，避免依赖硬件默认格式产生歧义。
            // computeLevel 也按 Float32 读取，两端格式对齐。
            output.audioSettings = [
                AVFormatIDKey:          kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey:  true,
                AVLinearPCMIsNonInterleaved: false
            ]

            let session = AVCaptureSession()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }

            let queue = DispatchQueue(label: "com.snapclick.audio.mic", qos: .userInitiated)
            output.setSampleBufferDelegate(self, queue: queue)

            self.micSession = session
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            print("[AudioRecordingEngine] 启动麦克风采集失败: \(error)")
        }
    }

    private func stopMicrophoneCapture() {
        if let session = micSession {
            // stopRunning 必须在 sessionQueue 同步调用才安全，但 AVCaptureSession 内部已加锁
            session.stopRunning()
        }
        micSession = nil
    }

    // MARK: - 私有：系统音频采集（Phase 3 接入）

    @available(macOS 13.0, *)
    private func startSystemAudioCapture() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AudioRecordingError.engineStartFailed("未找到可录制的屏幕")
        }

        // 排除自身应用的所有窗口，避免 HUD / 倒计时等被录进音频路径上的系统混音
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let selfApps = content.applications.filter {
            $0.processID == ownPID
        }
        let filter = SCContentFilter(display: display, excludingApplications: selfApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        // SCK 强制 width/height 非 0，给最小值
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.capturesAudio = true
        config.sampleRate = systemSampleRate
        config.channelCount = systemChannelCount

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.systemStream = stream

        try stream.addStreamOutput(self, type: SCStreamOutputType.audio,
                                   sampleHandlerQueue: DispatchQueue(label: "com.snapclick.audio.system"))
        try await stream.startCapture()
    }

    @available(macOS 13.0, *)
    private func stopSystemAudioCapture() async {
        try? await systemStream?.stopCapture()
        systemStream = nil
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate（麦克风）

extension AudioRecordingEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // 计算电平（主线程外算好后再 publish）
        let level = Self.computeLevel(from: sampleBuffer)

        Task { @MainActor in
            guard self.isRecording, !self.isPaused else { return }
            // 平滑电平（避免柱状图抖动）
            self.micLevel = self.micLevel * 0.7 + level * 0.3

            guard let writer = self.assetWriter, writer.status == .writing else { return }

            if self.firstSample {
                self.firstSample = false
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: pts)
            }

            if let input = self.micInput, input.isReadyForMoreMediaData {
                if self.timeOffset != .zero {
                    if let adjusted = sampleBuffer.withTimingOffset(self.timeOffset) {
                        input.append(adjusted)
                        self.lastAppendedPTS = CMSampleBufferGetPresentationTimeStamp(adjusted)
                    }
                } else {
                    input.append(sampleBuffer)
                    self.lastAppendedPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                }
            }
        }
    }
}

// MARK: - SCStreamOutput（系统音频，Phase 3）

extension AudioRecordingEngine: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of outputType: SCStreamOutputType) {
        guard #available(macOS 13.0, *) else { return }
        guard outputType == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let level = Self.computeLevel(from: sampleBuffer)

        Task { @MainActor in
            guard self.isRecording, !self.isPaused else { return }
            self.systemLevel = self.systemLevel * 0.7 + level * 0.3

            guard let writer = self.assetWriter, writer.status == .writing else { return }

            if self.firstSample {
                self.firstSample = false
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: pts)
            }

            if let input = self.systemInput, input.isReadyForMoreMediaData {
                if self.timeOffset != .zero {
                    if let adjusted = sampleBuffer.withTimingOffset(self.timeOffset) {
                        input.append(adjusted)
                    }
                } else {
                    input.append(sampleBuffer)
                }
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension AudioRecordingEngine: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[AudioRecordingEngine] 系统音频流异常终止: \(error)")
        Task { @MainActor in
            if self.isRecording {
                _ = try? await self.stopRecording()
            }
        }
    }
}

// MARK: - 工具：CMSampleBuffer → RMS 电平

extension AudioRecordingEngine {
    /// 从 CMSampleBuffer 计算归一化 RMS 电平（0.0 ~ 1.0）
    /// -60dB ~ 0dB 线性映射为 0 ~ 1
    /// 支持 Float32 线性 PCM（startMicrophoneCapture 显式设置的格式）
    nonisolated static func computeLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return 0 }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let raw = dataPointer else { return 0 }

        // macOS AVCaptureAudioDataOutput 在显式设置 AVLinearPCMIsFloatKey=true 后输出
        // Float32（4字节/样本）。按 Float32 解读内存，直接得到 -1.0 ~ 1.0 范围的样本值。
        let floatCount = totalLength / MemoryLayout<Float32>.size
        guard floatCount > 0 else { return 0 }
        let samples = raw.withMemoryRebound(to: Float32.self, capacity: floatCount) {
            Array(UnsafeBufferPointer(start: $0, count: floatCount))
        }

        var sum: Double = 0
        for v in samples {
            let d = Double(v)
            sum += d * d
        }
        let rms = sqrt(sum / Double(samples.count))
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = max(0, (db + 60) / 60)
        return Float(min(1.0, normalized))
    }
}

// MARK: - 通知

public extension Notification.Name {
    static let audioRecordingDidStart   = Notification.Name("SnapClickAudioRecordingDidStart")
    static let audioRecordingDidStop    = Notification.Name("SnapClickAudioRecordingDidStop")
    /// 请求弹出录音前参数选择面板（热键路径发送，StatusBarController 监听）
    static let showAudioPreLaunchPanel  = Notification.Name("SnapClickShowAudioPreLaunchPanel")
}
