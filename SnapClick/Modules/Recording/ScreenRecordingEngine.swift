// ScreenRecordingEngine.swift
// SnapClick - 屏幕录制模块核心引擎
// 使用 ScreenCaptureKit (macOS 12.3+) 实现屏幕录制功能，集成专属选区层、HUD 控制浮条以及多音轨麦克风捕获

import ScreenCaptureKit
import AVFoundation
import AppKit
import Combine

// MARK: - 录制错误类型
enum ScreenRecordingError: LocalizedError {
    case permissionDenied
    case noScreenAvailable
    case alreadyRecording
    case notRecording
    case setupFailed(String)
    case saveFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:      return "没有屏幕录制权限，请在系统设置中授权"
        case .noScreenAvailable:     return "未找到可用的屏幕"
        case .alreadyRecording:      return "录制已在进行中"
        case .notRecording:          return "当前没有进行录制"
        case .setupFailed(let msg):  return "录制配置失败：\(msg)"
        case .saveFailed(let msg):   return "保存录制失败：\(msg)"
        case .userCancelled:         return "用户取消了录制"
        }
    }
}

// MARK: - 录制引擎（主 Actor）
@MainActor
final class ScreenRecordingEngine: NSObject, ObservableObject {

    // MARK: 单例
    static let shared = ScreenRecordingEngine()

    // MARK: 发布属性
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var recordingDuration: TimeInterval = 0

    // MARK: 私有属性
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput? // 系统音频输入
    private var micInput: AVAssetWriterInput?   // 麦克风音频输入
    private var outputURL: URL?
    private var durationTimer: AnyCancellable?
    private var recordingStartTime: CMTime = .zero
    private var firstSample = true

    // 麦克风录制会话
    private var micSession: AVCaptureSession?

    // 暂停/继续时间差参数
    private var timeOffset: CMTime = .zero
    private var lastAppendedPTS: CMTime = .zero
    private var needsResumeAdjustment = false

    // UI 组件引用
    private var selectionOverlayWindow: RecordSelectionOverlayWindow?
    private var overlayContinuation: CheckedContinuation<(CGRect?, SCWindow?), Error>?
    private var hudWindow: RecordingHUDWindow?
    private var countdownWindow: RecordingCountdownWindow?
    private var areaIndicatorWindow: RecordingAreaIndicatorWindow?

    private override init() {
        super.init()
    }


    // MARK: - 公共接口：选区录制
    func startAreaRecording() async throws {
        guard !isRecording else { throw ScreenRecordingError.alreadyRecording }
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenRecordingError.permissionDenied
        }

        let screen = activeScreen()
        let bgImage = try await captureScreen(screen)

        // 显示专属选区覆盖层，底部已自带 RecordingSelectionHUDView
        // 用户在覆盖层上拖完选区 → 在底部 HUD 上选清晰度等参数 → 点"开始录制"
        let (selectedRect, selectedWindow) = try await showSelectionOverlay(
            background: bgImage,
            screen: screen
        )
        guard let rect = selectedRect else {
            throw ScreenRecordingError.userCancelled
        }

        let quality = currentVideoQuality()
        let areaScreen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? screen

        // 提前显示四角闪烁标识，让用户在倒计时期间明确录制范围
        let indicator = RecordingAreaIndicatorWindow(recordingRect: rect)
        self.areaIndicatorWindow = indicator
        indicator.orderFrontRegardless()

        // 倒计时（如设置）
        do {
            try await performCountdown()
        } catch {
            // 若倒计时被中途取消，及时销毁指示器窗口
            areaIndicatorWindow?.orderOut(nil)
            areaIndicatorWindow = nil
            throw error
        }

        // 开始录制选定区域
        try await startRecording(
            captureRect: rect,
            targetWindow: selectedWindow,
            targetScreen: areaScreen,
            quality: quality
        )
    }

    // MARK: - 公共接口：全屏录制
    func startFullScreenRecording() async throws {
        guard !isRecording else { throw ScreenRecordingError.alreadyRecording }
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenRecordingError.permissionDenied
        }

        // 三种录制模式（选区 / 窗口 / 全屏）共用同一份横向 HUD（RecordingSelectionHUDView）：
        //   - 选区 / 窗口录制：RecordSelectionOverlayWindow 自带底部 HUD
        //   - 全屏录制      ：RecordHUDStandaloneWindow 单独承载 HUD（无选区）
        // HUD 上的所有参数（含清晰度档位）会写入 AppSettings，
        // 启动录制时从这里读取 → 转为 VideoQuality 喂给 AVAssetWriter。
        let screen = try await showStandaloneHUD()
        let quality = currentVideoQuality()

        // 全屏录制同样显示四角闪烁标识，让用户明确录制范围
        // 向内收缩 5px，抵消指示器窗口的对外扩展，确保四角标识完整贴合屏幕边缘可见
        let indicatorRect = screen.frame.insetBy(dx: 5, dy: 5)
        let indicator = RecordingAreaIndicatorWindow(recordingRect: indicatorRect)
        self.areaIndicatorWindow = indicator
        indicator.orderFrontRegardless()

        do {
            try await performCountdown()
        } catch {
            areaIndicatorWindow?.orderOut(nil)
            areaIndicatorWindow = nil
            throw error
        }

        try await startRecording(
            captureRect: nil,
            targetWindow: nil,
            targetScreen: screen,
            quality: quality
        )
    }

    // MARK: - 公共接口：窗口录制
    func startWindowRecording() async throws {
        guard !isRecording else { throw ScreenRecordingError.alreadyRecording }
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenRecordingError.permissionDenied
        }

        // 获取可录制的窗口列表
        let windows = try await getShareableWindows()

        let screen = activeScreen()
        let bgImage = try await captureScreen(screen)

        // 显示专属窗口覆盖层，底部已自带 RecordingSelectionHUDView
        // 用户在覆盖层上点选窗口 → 在底部 HUD 上选清晰度等参数 → 点"开始录制"
        let (selectedRect, selectedWindow) = try await showSelectionOverlay(
            background: bgImage,
            windows: windows,
            mode: .windowSelection,
            screen: screen
        )
        guard let rect = selectedRect else {
            throw ScreenRecordingError.userCancelled
        }

        let quality = currentVideoQuality()
        let windowScreen: NSScreen
        if let win = selectedWindow,
           let matched = NSScreen.screens.first(where: { $0.frame.intersects(win.frame) }) {
            windowScreen = matched
        } else {
            windowScreen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? screen
        }

        // 提前显示四角闪烁标识，让用户在倒计时期间明确录制范围
        let indicator = RecordingAreaIndicatorWindow(recordingRect: rect)
        self.areaIndicatorWindow = indicator
        indicator.orderFrontRegardless()

        // 倒计时（如设置）
        do {
            try await performCountdown()
        } catch {
            // 若倒计时被中途取消，及时销毁指示器窗口
            areaIndicatorWindow?.orderOut(nil)
            areaIndicatorWindow = nil
            throw error
        }

        // 开始独立窗口录制
        try await startRecording(
            captureRect: rect,
            targetWindow: selectedWindow,
            targetScreen: windowScreen,
            quality: quality
        )
    }

    // MARK: - 暂停/继续录制
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        isPaused = true
        print("[ScreenRecordingEngine] 录制已暂停")
    }

    func resumeRecording() {
        guard isRecording && isPaused else { return }
        isPaused = false
        needsResumeAdjustment = true
        print("[ScreenRecordingEngine] 录制已继续")
    }

    // MARK: - 停止录制
    func stopRecording() async throws -> URL {
        guard isRecording else { throw ScreenRecordingError.notRecording }

        // ① 第一步：立即将 isRecording 标记为 false，
        //    让所有正在飞行的异步帧任务（Task { @MainActor in ... }）
        //    在下一次调度时感知到录制已停止，从而不再向 assetWriter 追加数据
        isRecording = false
        isPaused = false

        // ② 停止 ScreenCaptureKit 流，等待其真正停止
        try? await stream?.stopCapture()
        stream = nil

        // ③ 停止麦克风采集
        stopMicrophoneCapture()

        // ④ 关闭指示器窗口
        areaIndicatorWindow?.orderOut(nil)
        areaIndicatorWindow = nil

        // ⑤ 停止时长计时器
        durationTimer?.cancel()
        durationTimer = nil

        // ⑥ 等待 300ms，给已派发的异步帧任务足够时间检测到 isRecording == false
        //    并提前退出，避免并发写入冲突（原先 100ms 不够，在负载较高时仍有帧竞争）
        try await Task.sleep(nanoseconds: 300_000_000)

        // ⑦ 若从未写入任何帧（firstSample 仍为 true，说明 startSession 未触发），
        //    直接结束写入会进入 .failed 并报泛化错误，这里提前给出明确提示并清理
        if firstSample {
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            micInput?.markAsFinished()
            let writer = assetWriter
            self.assetWriter = nil
            writer?.cancelWriting()
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            firstSample = true
            timeOffset = .zero
            lastAppendedPTS = .zero
            needsResumeAdjustment = false
            closeRecordingHUD()
            NotificationCenter.default.post(name: .recordingDidStop, object: nil)
            throw ScreenRecordingError.saveFailed("未捕获到任何画面，录制时间过短或选区无效")
        }

        // ⑧ 通知各轨道数据写入完毕
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()

        // ⑨ 先将 assetWriter 引用转移并置空，
        //    防止极端情况下还有延迟帧在 finishWriting() 期间追加数据
        let writer = assetWriter
        self.assetWriter = nil

        // ⑩ 完成写入并关闭文件描述符
        await writer?.finishWriting()

        // ⑪ 检查写入结果——即使 finishWriting 失败，也不要 throw，
        //    因为此时 isRecording 已经为 false、流已经停止，
        //    如果 throw 会导致调用者无法拿到 outputURL，且录屏陷入
        //    "无法停止"的死锁（isRecording=false → guard 报 notRecording）。
        //    改为仅打印日志警告，文件可能不完整但至少不会卡死。
        if writer?.status == .failed {
            let reason = writer?.error?.localizedDescription ?? "未知错误"
            print("[ScreenRecordingEngine] ⚠️ finishWriting 失败（\(reason)），视频文件可能不完整")
        }

        firstSample = true
        timeOffset = .zero
        lastAppendedPTS = .zero
        needsResumeAdjustment = false

        // 关闭 HUD 控制浮条
        closeRecordingHUD()

        // 广播通知，重置状态栏图标
        NotificationCenter.default.post(name: .recordingDidStop, object: nil)

        guard let url = outputURL else {
            throw ScreenRecordingError.saveFailed("输出路径为空")
        }

        return url
    }

    // MARK: - 取消录制并删除文件
    func cancelRecording() async throws {
        guard isRecording else { throw ScreenRecordingError.notRecording }
        let url = try await stopRecording()
        try? FileManager.default.removeItem(at: url)
        print("[ScreenRecordingEngine] 录制已取消，已删除临时文件：\(url.path)")
    }

    // MARK: - 私有：专属选区覆盖层展示
    private func showSelectionOverlay(
        background: NSImage,
        windows: [SCWindow] = [],
        mode: RecordSelectionMode = .areaSelection,
        screen: NSScreen
    ) async throws -> (CGRect?, SCWindow?) {
        return try await withCheckedThrowingContinuation { continuation in
            self.overlayContinuation = continuation

            let overlay = RecordSelectionOverlayWindow(backgroundImage: background, windows: windows, screen: screen, mode: mode)
            self.selectionOverlayWindow = overlay

            overlay.onCancelled = { [weak self] in
                self?.selectionOverlayWindow = nil
                let cont = self?.overlayContinuation
                self?.overlayContinuation = nil
                cont?.resume(returning: (nil, nil))
            }

            overlay.onFinished = { [weak self] rect, window in
                self?.selectionOverlayWindow = nil
                let cont = self?.overlayContinuation
                self?.overlayContinuation = nil
                cont?.resume(returning: (rect, window))
            }

            overlay.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - 私有：独立 HUD 面板（全屏录制场景）
    /// 全屏录制没有选区可拖，单独显示一份不带选区的横向 HUD（含"屏幕"下拉）。
    /// 等用户点"开始录制"才返回：返回用户在 HUD 中选中的那块屏幕；
    /// 找不到匹配屏时兑底到鼠标所在屏；点"取消"/ESC 抛 userCancelled。
    ///
    /// 注意：不要在 HUD 已经显示后再调用 panel.setFrame / panel.center——
    ///   panel 自己的 init 已经按 hostScreen 正中算好 frame，
    ///   重复设置会覆盖掉用户已经拖到的位置，体验上会看到 HUD 突然跳回屏幕正中。
    private func showStandaloneHUD() async throws -> NSScreen {
        let hostScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSScreen, Error>) in
            let panel = RecordHUDStandaloneWindow(hostScreen: hostScreen)
            panel.onRecord = {
                // 用户在 HUD 的"屏幕"下拉里可能改过目标屏幕，
                // 按名字匹配，没匹配上（拔显示器/重命名）就兑底到鼠标屏
                let savedName = AppSettings.shared.recordFullScreenScreenName
                let picked = NSScreen.screens.first(where: { $0.localizedName == savedName && !savedName.isEmpty })
                    ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                    ?? NSScreen.main
                    ?? hostScreen
                continuation.resume(returning: picked)
            }
            panel.onCancel = {
                continuation.resume(throwing: ScreenRecordingError.userCancelled)
            }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - 私有：当前选中的清晰度档位
    /// 把 AppSettings.recordQuality（"标清" / "超清" / "原画"）映射为 VideoQuality 枚举，
    /// 用于喂给 AVAssetWriter 的码率/编码参数。
    private func currentVideoQuality() -> VideoQuality {
        switch AppSettings.shared.recordQuality {
        case "标清": return .standard
        case "原画": return .original
        default:     return .high  // 默认 / "超清"
        }
    }

    private func getShareableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.current
        let screenFrames = NSScreen.screens.map { $0.frame }

        let systemBundles: Set<String> = [
            "com.apple.dock",
            "com.apple.WindowManager",
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.notificationcenterui",
            "com.apple.wallpaper.WallpaperAgent",
            "com.apple.Spotlight",
            "com.apple.loginwindow",
            "com.apple.TextInputMenuAgent",
            "com.apple.TextInputSwitcher"
        ]

        // 1) 通过 CoreGraphics 获取真实可见窗口列表（已按 Z 序排好）
        let cgListOpts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(cgListOpts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // 2) 把 SCWindow 按 windowID 建立索引，便于按 CG 顺序查找
        var scIndex: [CGWindowID: SCWindow] = [:]
        for w in content.windows {
            scIndex[w.windowID] = w
        }

        // 3) 按 CG 列表顺序构建结果（保留 Z 序：前面 = 最上层）
        var result: [SCWindow] = []
        for entry in rawList {
            // 仅普通应用窗口层
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            // 必须实际"在屏"
            if let onScreen = entry[kCGWindowIsOnscreen as String] as? Bool, !onScreen { continue }
            // 必须有 alpha（>0）
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.05 { continue }
            // PID：排除自身
            // PID：本 App 的录屏辅助窗口（选区覆盖层、HUD、四角指示器）层级均高于 0，
            // 已被上面的 layer == 0 过滤掉；此处保留普通层级的 SnapClick 主窗口，使其可被录制
            // 取 windowID
            guard let cgID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            // 必须在 SCShareableContent 中存在
            guard let scWin = scIndex[cgID] else { continue }
            // owningApplication 必填
            guard let app = scWin.owningApplication else { continue }
            // 排除系统 UI 进程
            if systemBundles.contains(app.bundleIdentifier) { continue }
            // 取 CGRect（CG 坐标系）
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            // 尺寸太小过滤
            if cgRect.width < 60 || cgRect.height < 40 { continue }
            // 必须与某个屏幕有交集
            guard screenFrames.contains(where: { $0.intersects(scWin.frame) }) else { continue }
            result.append(scWin)
        }
        return result
    }

    // MARK: - 私有：多屏幕与截图辅助
    private func activeScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func captureScreen(_ screen: NSScreen) async throws -> NSImage {
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        let scale = screen.backingScaleFactor

        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
                        ?? content.displays.first else {
                    throw ScreenRecordingError.noScreenAvailable
                }

                // 排除自身所有窗口，避免覆盖层被截入
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let ownWindows = content.windows.filter {
                    $0.owningApplication?.processID == ownPID
                }
                let filter = SCContentFilter(display: scDisplay, excludingWindows: ownWindows)

                let cfg = SCStreamConfiguration()
                cfg.width  = Int(CGFloat(scDisplay.width)  * scale)
                cfg.height = Int(CGFloat(scDisplay.height) * scale)
                cfg.showsCursor = false
                cfg.capturesAudio = false

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: cfg)
                let size = NSSize(width:  CGFloat(cgImage.width)  / scale,
                                  height: CGFloat(cgImage.height) / scale)
                return NSImage(cgImage: cgImage, size: size)
            } catch {
                // 失败回退到 CGDisplayCreateImage
            }
        }

        // 降级：在后台线程同步调用，避免阻塞主线程
        let cgImage: CGImage? = await Task.detached(priority: .userInitiated) {
            CGDisplayCreateImage(displayID)
        }.value
        guard let cgImage = cgImage else {
            throw ScreenRecordingError.setupFailed("无法获取屏幕截图")
        }
        let size = NSSize(width:  CGFloat(cgImage.width)  / scale,
                          height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - 私有：倒计时
    private func performCountdown() async throws {
        let seconds = AppSettings.shared.recordTimer
        guard seconds > 0 else { return }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let window = RecordingCountdownWindow(
                seconds: seconds,
                onFinished: {
                    continuation.resume()
                },
                onCancelled: {
                    continuation.resume(throwing: ScreenRecordingError.userCancelled)
                }
            )
            self.countdownWindow = window
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
        self.countdownWindow = nil
    }


    // MARK: - 私有：核心录制启动
    private func startRecording(
        captureRect: CGRect?,
        targetWindow: SCWindow? = nil,
        targetScreen: NSScreen? = nil,
        quality: VideoQuality = .high
    ) async throws {
        let settings = AppSettings.shared

        // ── 准备输出文件路径 ──────────────────────────────────────
        let saveDir = SandboxManager.shared.writableURL(for: settings.recordSavePath)
        try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let fileName = "SnapClick_录屏_\(dateFormatter.string(from: Date()))"
        let ext = settings.recordFormat.lowercased()  // "mov" / "mp4"
        let fileURL = saveDir.appendingPathComponent(fileName).appendingPathExtension(ext)
        self.outputURL = fileURL

        // ── 配置 AVAssetWriter ────────────────────────────────────
        let fileType: AVFileType = settings.recordFormat == "MP4" ? .mp4 : .mov
        let writer = try AVAssetWriter(outputURL: fileURL, fileType: fileType)
        self.assetWriter = writer

        // 计算录制尺寸：以 captureRect 实际所在的屏幕为基准，避免在多屏/不同缩放比下
        // 用 NSScreen.main 的 backingScaleFactor 计算出错误的像素尺寸，
        // 导致 SCStream 输出的帧尺寸与 AVAssetWriterInput 期望尺寸不一致、append 静默失败、文件不完整。
        // 优先级：用户显式指定的 targetScreen > 选区所在屏幕 > 主屏
        let screen: NSScreen = {
            if let explicit = targetScreen {
                return explicit
            }
            if let rect = captureRect,
               let matched = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) {
                return matched
            }
            return NSScreen.main ?? NSScreen.screens[0]
        }()
        let screenScale = screen.backingScaleFactor

        var baseRect = captureRect ?? CGRect(
            origin: .zero,
            size: CGSize(width: screen.frame.width, height: screen.frame.height)
        )

        // 原画画质：保留选区/屏幕的完整像素尺寸
        // 超清/标清：按比例缩到对应档位对应的"参考像素上限"
        let nativeWidthPx  = baseRect.width  * screenScale
        let nativeHeightPx = baseRect.height * screenScale

        // 不同质量档位对应的"最长边像素上限"，控制最终输出文件体积
        // 标清 → 1280  长边；超清 → 1920  长边；原画 → 不限制
        let maxLongSidePx: CGFloat? = {
            switch quality {
            case .standard: return 1280
            case .high:     return 1920
            case .original: return nil
            }
        }()

        var targetWidthPx = nativeWidthPx
        var targetHeightPx = nativeHeightPx
        if let maxLong = maxLongSidePx {
            let longSide = max(nativeWidthPx, nativeHeightPx)
            if longSide > maxLong {
                let ratio = maxLong / longSide
                targetWidthPx  = nativeWidthPx  * ratio
                targetHeightPx = nativeHeightPx * ratio
            }
        }

        var videoWidth  = Int(targetWidthPx.rounded())
        var videoHeight = Int(targetHeightPx.rounded())

        // 保证宽高为偶数，防止 AVAssetWriter 报错
        videoWidth  = videoWidth  - (videoWidth  % 2)
        videoHeight = videoHeight - (videoHeight % 2)

        // ── 编码参数（仿 Snapzy RecordingVideoEncodingSettings） ──────────
        let formatIsMOV = (settings.recordFormat == "MOV")
        let codec = RecordingVideoEncodingSettings.preferredCodec(
            formatIsMOV: formatIsMOV,
            quality: quality
        )
        let bitrate = RecordingVideoEncodingSettings.calculatedBitrate(
            width: videoWidth,
            height: videoHeight,
            fps: settings.recordFPS,
            quality: quality,
            codec: codec
        )

        // 关键帧间隔固定为 1 秒（= FPS 帧）：
        //   - 太长（如 5s）：P 帧积累误差，快速滚动时会拖影/模糊
        //   - 1s 是屏幕录制的行业惯例，兼顾随机访问与压缩效率
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey:               bitrate,
            AVVideoMaxKeyFrameIntervalKey:          settings.recordFPS,
            AVVideoMaxKeyFrameIntervalDurationKey:  1.0,
            AVVideoExpectedSourceFrameRateKey:      settings.recordFPS,
            AVVideoAllowFrameReorderingKey:         false,
        ]
        // H.264 才设置 profile level + CABAC；HEVC 用自己的 profile，不在此处指定
        if codec == .h264 {
            compressionProps[AVVideoProfileLevelKey] = quality.h264ProfileLevel
            compressionProps[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:                 codec,
            AVVideoWidthKey:                 videoWidth,
            AVVideoHeightKey:                videoHeight,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey:    AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey:  AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey:       AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compressionProps,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        self.videoInput = videoInput
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        // 系统音频轨配置
        if settings.recordSystemAudio {
            let systemAudioSettings: [String: Any] = [
                AVFormatIDKey:          kAudioFormatMPEG4AAC,
                AVSampleRateKey:        44100,
                AVNumberOfChannelsKey:  2,
                AVEncoderBitRateKey:    128_000,
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: systemAudioSettings)
            audioInput.expectsMediaDataInRealTime = true
            self.audioInput = audioInput
            if writer.canAdd(audioInput) { writer.add(audioInput) }
        }

        // 麦克风录制音轨配置
        if settings.recordMicrophone != "无" {
            let micAudioSettings: [String: Any] = [
                AVFormatIDKey:          kAudioFormatMPEG4AAC,
                AVSampleRateKey:        44100,
                AVNumberOfChannelsKey:  2,
                AVEncoderBitRateKey:    128_000,
            ]
            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micAudioSettings)
            micInput.expectsMediaDataInRealTime = true
            self.micInput = micInput
            if writer.canAdd(micInput) { writer.add(micInput) }
        }

        // 复位会话状态，避免上一次录制异常中断后残留导致 startSession 永不触发
        self.firstSample = true
        self.timeOffset = .zero
        self.lastAppendedPTS = .zero
        self.needsResumeAdjustment = false
        self.recordingStartTime = .zero

        guard writer.startWriting() else {
            let reason = writer.error?.localizedDescription ?? "未知错误"
            throw ScreenRecordingError.saveFailed("无法开始写入：\(reason)")
        }

        // ── 配置 SCStream ─────────────────────────────────────────
        let content = try await SCShareableContent.current

        // 选取与录制屏幕匹配的 SCDisplay，保证 sourceRect 与尺寸计算基于同一块屏幕
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw ScreenRecordingError.noScreenAvailable
        }

        let filter: SCContentFilter
        if let targetWindow = targetWindow {
            filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        } else {
            // 全屏录制时排除本 App 自身，避免四角闪烁指示器、HUD 等被录入视频
            let selfApps = content.applications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            filter = SCContentFilter(display: display, excludingApplications: selfApps, exceptingWindows: [])
        }

        let streamConfig = SCStreamConfiguration()
        streamConfig.width  = videoWidth
        streamConfig.height = videoHeight
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.recordFPS))
        streamConfig.queueDepth = 6
        streamConfig.showsCursor = settings.recordHighlightCursor

        // 像素格式：屏幕内容包含大量文字 / 锐利边缘，YUV 4:2:0 (默认 420v) 的色度子采样
        // 会让文字边缘发糊、出现彩边。改用 BGRA 全采样像素格式，配合 H.264/HEVC 编码器
        // 内部的高质量色彩转换，最大化保留文字锐度。
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.colorSpaceName = CGColorSpace.sRGB
        streamConfig.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        streamConfig.backgroundColor = .black
        // Retina 屏幕缩放策略：保留全部源像素，由编码器进行 Lanczos 缩放（如有必要）
        if #available(macOS 14.0, *) {
            streamConfig.captureResolution = .best
        }

        // 启用系统声音捕获（macOS 13+）
        if #available(macOS 13.0, *), settings.recordSystemAudio {
            streamConfig.capturesAudio = true
            streamConfig.sampleRate = 44100
            streamConfig.channelCount = 2
        }

        // 如果是选区录制且非窗口录屏，设置裁剪框 sourceRect
        // sourceRect 必须是相对所在屏幕左上角的局部坐标（单位：点），
        // 因此先把全局桌面坐标转换为屏幕局部坐标，再做 Y 轴翻转。
        if let rect = captureRect, targetWindow == nil {
            let localX = rect.origin.x - screen.frame.origin.x
            let localYBottom = rect.origin.y - screen.frame.origin.y
            let flippedY = screen.frame.height - localYBottom - rect.height
            streamConfig.sourceRect = CGRect(x: localX,
                                             y: flippedY,
                                             width: rect.width,
                                             height: rect.height)
        }

        let captureStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        self.stream = captureStream

        try captureStream.addStreamOutput(self, type: .screen,
                                          sampleHandlerQueue: DispatchQueue(label: "com.snapclick.recording.video"))
        
        if settings.recordSystemAudio {
            if #available(macOS 13.0, *) {
                try captureStream.addStreamOutput(self, type: .audio,
                                                  sampleHandlerQueue: DispatchQueue(label: "com.snapclick.recording.audio"))
            }
        }

        // ── 启动音频硬件采集（麦克风） ─────────────────────────────
        startMicrophoneCapture()

        // ── 开启截屏流捕获 ────────────────────────────────────────
        try await captureStream.startCapture()

        // ── 开启区域蓝色闪烁角标指示器（若为选区或窗口模式，且未在倒计时展示） ──
        if let rect = captureRect {
            if self.areaIndicatorWindow == nil {
                let indicator = RecordingAreaIndicatorWindow(recordingRect: rect)
                self.areaIndicatorWindow = indicator
                indicator.orderFrontRegardless()
            }
        }

        // ── 更新内部状态 ─────────────────────────────────────────
        isRecording = true
        isPaused = false
        recordingDuration = 0

        durationTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.isPaused {
                    self.recordingDuration += 1
                }
            }


        // 广播录像启动通知，状态栏改为闪烁录制态
        NotificationCenter.default.post(name: .recordingDidStart, object: nil)

        // 弹出 HUD 控制浮条（暂停/停止/取消）
        showRecordingHUD()
    }

    // MARK: - 录制 HUD 浮显控制
    private func showRecordingHUD() {
        let hud = RecordingHUDWindow(
            onPauseResume: { [weak self] in
                guard let self = self else { return }
                if self.isPaused {
                    self.resumeRecording()
                } else {
                    self.pauseRecording()
                }
            },
            onStop: { [weak self] in
                guard let self = self else { return }
                Task {
                    do {
                        let fileURL = try await self.stopRecording()
                        // 在 Finder 中高亮显示输出的文件
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } catch {
                        print("[ScreenRecordingEngine] 结束录像出错: \(error)")
                    }
                }
            },
            onCancel: { [weak self] in
                guard let self = self else { return }
                // 销毁性操作：先弹确认对话框，避免误触导致文件丢失
                self.confirmCancelRecording()
            }
        )
        self.hudWindow = hud
        hud.makeKeyAndOrderFront(nil)
    }

    // MARK: - 确认取消录制（销毁性操作前的二次确认）
    private func confirmCancelRecording() {
        let alert = NSAlert()
        alert.messageText = "取消录制？"
        alert.informativeText = "当前录制的视频将被丢弃且无法恢复。如需保留，请先点击停止按钮。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消录制")
        alert.addButton(withTitle: "继续录制")
        // 默认按钮为"继续录制"（右侧安全项），符合 HIG 销毁性操作规范
        if let buttons = alert.buttons as? [NSButton] {
            buttons[1].keyEquivalent = "\r"      // Enter -> 继续录制
            buttons[0].keyEquivalent = "\u{1B}"   // Esc  -> 取消录制
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task {
                do {
                    try await self.cancelRecording()
                } catch {
                    print("[ScreenRecordingEngine] 取消录制出错: \(error)")
                }
            }
        }
    }

    private func closeRecordingHUD() {
        hudWindow?.orderOut(nil)
        hudWindow = nil
    }

    // MARK: - 麦克风录音控制
    private func startMicrophoneCapture() {
        let settings = AppSettings.shared
        guard settings.recordMicrophone != "无" else { return }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        guard let device = session.devices.first(where: { $0.localizedName == settings.recordMicrophone }) else {
            print("[ScreenRecordingEngine] 找不到用户选择的麦克风设备: \(settings.recordMicrophone)")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureAudioDataOutput()

            // 显式指定 Float32 线性 PCM 输出，避免依赖硬件默认格式产生歧义。
            output.audioSettings = [
                AVFormatIDKey:          kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey:  true,
                AVLinearPCMIsNonInterleaved: false
            ]

            let micSession = AVCaptureSession()
            if micSession.canAddInput(input) { micSession.addInput(input) }
            if micSession.canAddOutput(output) { micSession.addOutput(output) }

            let queue = DispatchQueue(label: "com.snapclick.recording.mic")
            output.setSampleBufferDelegate(self, queue: queue)

            self.micSession = micSession
            
            DispatchQueue.global(qos: .userInitiated).async {
                micSession.startRunning()
            }
            print("[ScreenRecordingEngine] 成功启动麦克风录制设备: \(device.localizedName)")
        } catch {
            print("[ScreenRecordingEngine] 初始化麦克风捕捉会话失败: \(error)")
        }
    }

    private func stopMicrophoneCapture() {
        micSession?.stopRunning()
        micSession = nil
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecordingEngine: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            print("[ScreenRecordingEngine] 截屏捕获流异常终止: \(error)")
            if self.isRecording {
                _ = try? await self.stopRecording()
            }
        }
    }
}

// MARK: - SCStreamOutput（SCKit 视频/系统音频帧采集）

extension ScreenRecordingEngine: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                             didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                             of outputType: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // 仅处理状态为 .complete 的视频帧；.idle/.blank/.suspended 等帧不含有效画面，
        // 直接 append 会污染时间轴并可能导致选区录制文件不完整。
        if case .screen = outputType {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete else {
                return
            }
        }

        Task { @MainActor in
            guard self.isRecording && !self.isPaused else { return }
            guard let writer = self.assetWriter,
                  writer.status == .writing else { return }

            // 第一帧到来时启动写入 Session
            if self.firstSample {
                self.firstSample = false
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: pts)
                self.recordingStartTime = pts
            }

            switch outputType {
            case .screen:
                if let videoInput = self.videoInput, videoInput.isReadyForMoreMediaData {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    
                    // 恢复录制时，动态计算并补偿暂停期间消耗的帧差时间偏移
                    if self.needsResumeAdjustment {
                        self.needsResumeAdjustment = false
                        if self.lastAppendedPTS != .zero {
                            let gap = pts - self.lastAppendedPTS
                            self.timeOffset = self.timeOffset + gap
                        }
                    }
                    
                    let adjustedPTS = pts - self.timeOffset
                    self.lastAppendedPTS = adjustedPTS
                    
                    if self.timeOffset != .zero {
                        if let adjustedBuffer = sampleBuffer.withTimingOffset(self.timeOffset) {
                            videoInput.append(adjustedBuffer)
                        }
                    } else {
                        videoInput.append(sampleBuffer)
                    }
                }
            default:
                // .audio 仅在 macOS 13+ 可用
                if #available(macOS 13.0, *) {
                    if case .audio = outputType,
                       let audioInput = self.audioInput,
                       audioInput.isReadyForMoreMediaData {
                        if self.timeOffset != .zero {
                            if let adjustedBuffer = sampleBuffer.withTimingOffset(self.timeOffset) {
                                audioInput.append(adjustedBuffer)
                            }
                        } else {
                            audioInput.append(sampleBuffer)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate（麦克风音频帧采集）

extension ScreenRecordingEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        Task { @MainActor in
            guard self.isRecording && !self.isPaused else { return }
            guard let writer = self.assetWriter,
                  writer.status == .writing else { return }
            
            // 如果第一帧是从麦克风先到来，也需支持会话初始化
            if self.firstSample {
                self.firstSample = false
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: pts)
                self.recordingStartTime = pts
            }
            
            if let micInput = self.micInput, micInput.isReadyForMoreMediaData {
                if self.timeOffset != .zero {
                    if let adjustedBuffer = sampleBuffer.withTimingOffset(self.timeOffset) {
                        micInput.append(adjustedBuffer)
                    }
                } else {
                    micInput.append(sampleBuffer)
                }
            }
        }
    }
}

// MARK: - CMSampleBuffer 帧播放时间修正扩展
extension CMSampleBuffer {
    func withTimingOffset(_ offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(self, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        
        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
        CMSampleBufferGetSampleTimingInfoArray(self, entryCount: count, arrayToFill: &info, entriesNeededOut: &count)
        
        for i in 0..<count {
            if info[i].presentationTimeStamp.isValid {
                info[i].presentationTimeStamp = info[i].presentationTimeStamp - offset
            }
            if info[i].decodeTimeStamp.isValid {
                info[i].decodeTimeStamp = info[i].decodeTimeStamp - offset
            }
        }
        
        var adjustedBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: self,
            sampleTimingEntryCount: count,
            sampleTimingArray: &info,
            sampleBufferOut: &adjustedBuffer
        )
        
        return status == noErr ? adjustedBuffer : nil
    }
}

// MARK: - Notification 扩展
public extension Notification.Name {
    static let recordingDidStart   = Notification.Name("SnapClickRecordingDidStart")
    static let recordingDidStop    = Notification.Name("SnapClickRecordingDidStop")
    static let recordingCountdown  = Notification.Name("SnapClickRecordingCountdown")
}

