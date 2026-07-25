// AudioMicrophoneTestEngine.swift
// SnapClick - 麦克风检测引擎（设置页实时电平计的数据源）
// 与 AudioRecordingEngine 互斥：录音进行中禁止开启检测，检测中禁止开始录音
// 复用 AudioRecordingEngine.computeLevel 计算 RMS

import AVFoundation
import Foundation

@MainActor
final class AudioMicrophoneTestEngine: NSObject, ObservableObject {

    // MARK: 单例

    static let shared = AudioMicrophoneTestEngine()

    // MARK: 公开状态

    @Published private(set) var isTesting: Bool = false
    @Published private(set) var currentLevel: Float = 0       // 0.0 ~ 1.0

    // MARK: 私有属性

    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?

    // MARK: 初始化

    private override init() {
        super.init()
    }

    // MARK: - 公开接口

    /// 开始检测指定麦克风。
    /// - Parameter deviceName: 用户在 Picker 里选中的设备名，传 "无" 或空字符串会抛错
    func startTesting(deviceName: String) async throws {
        guard !isTesting else { return }
        guard ScreenRecordingEngine.shared.isRecording == false,
              AudioRecordingEngine.shared.isRecording == false else {
            throw NSError(domain: "AudioMicrophoneTest", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "正在进行其他录制任务，请先停止后再检测麦克风".localized])
        }

        guard !deviceName.isEmpty, deviceName != "无" else {
            throw NSError(domain: "AudioMicrophoneTest", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "请先选择麦克风设备".localized])
        }

        // 0) 权限检查 —— 没授权就先把系统弹窗/设置页走完
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw NSError(domain: "AudioMicrophoneTest", code: -5,
                              userInfo: [NSLocalizedDescriptionKey: "麦克风权限被拒绝".localized])
            }
        case .denied, .restricted:
            throw NSError(domain: "AudioMicrophoneTest", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "麦克风权限被拒绝，请在「系统设置 → 隐私与安全性 → 麦克风」中打开".localized])
        case .authorized:
            break
        @unknown default:
            break
        }

        // 1) 解析设备
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        guard let target = discovery.devices.first(where: { $0.localizedName == deviceName })
                          ?? discovery.devices.first else {
            throw NSError(domain: "AudioMicrophoneTest", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "找不到可用的麦克风设备".localized])
        }

        // 2) 创建 input；这里失败通常是设备被其他 app 独占
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: target)
        } catch {
            throw NSError(domain: "AudioMicrophoneTest", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "无法启动麦克风：\(target.localizedName) 可能正被其他应用占用".localized])
        }

        let output = AVCaptureAudioDataOutput()
        let captureSession = AVCaptureSession()
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.canAddOutput(output) { captureSession.addOutput(output) }

        let queue = DispatchQueue(label: "com.snapclick.audio.test", qos: .userInitiated)
        output.setSampleBufferDelegate(self, queue: queue)

        self.session = captureSession
        self.device = target

        self.isTesting = true
        self.currentLevel = 0

        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }

    /// 停止检测
    func stopTesting() {
        guard isTesting else { return }
        isTesting = false
        currentLevel = 0

        if let session = session {
            session.stopRunning()
        }
        session = nil
        device = nil
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension AudioMicrophoneTestEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let raw = AudioRecordingEngine.computeLevel(from: sampleBuffer)
        Task { @MainActor in
            guard self.isTesting else { return }
            // 平滑电平
            self.currentLevel = self.currentLevel * 0.65 + raw * 0.35
        }
    }
}

