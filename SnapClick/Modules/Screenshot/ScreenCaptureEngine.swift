// ScreenCaptureEngine.swift
// SnapClick - 截图模块核心引擎
// 使用 ScreenCaptureKit (macOS 12.3+) 实现截图功能

import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import AppKit
import Combine

// MARK: - 截图错误类型
enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noScreenAvailable
    case captureSessionFailed
    case imageConversionFailed
    case userCancelled
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:        return "没有屏幕录制权限，请在系统设置中授权"
        case .noScreenAvailable:       return "未找到可用的屏幕"
        case .captureSessionFailed:    return "截图会话失败"
        case .imageConversionFailed:   return "图像转换失败"
        case .userCancelled:           return "用户取消了截图"
        case .saveFailed(let msg):     return "保存截图失败：\(msg)"
        }
    }
}

// MARK: - 截图格式
enum ScreenshotFormat: String, CaseIterable {
    case png  = "PNG"
    case jpg  = "JPEG"
    case tiff = "TIFF"

    var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpg:  return "jpg"
        case .tiff: return "tiff"
        }
    }

    var bitmapFormat: NSBitmapImageRep.FileType {
        switch self {
        case .png:  return .png
        case .jpg:  return .jpeg
        case .tiff: return .tiff
        }
    }
}

// MARK: - 截图引擎（主 Actor）
@MainActor
class ScreenCaptureEngine: NSObject, ObservableObject {

    // 单例
    static let shared = ScreenCaptureEngine()

    // MARK: 发布属性
    @Published var isCapturing: Bool = false
    @Published var countdown: Int = 0

    // MARK: 私有属性
    private var overlayWindow: CaptureOverlayWindow?
    private var captureContent: SCShareableContent?
    private var countdownTimer: AnyCancellable?
    private var overlayContinuation: CheckedContinuation<Void, Error>?

    // MARK: - 初始化
    private override init() {
        super.init()
    }

    // MARK: - 权限检查
    /// 检查并请求屏幕录制权限
    func requestPermissionIfNeeded() async -> Bool {
        // 触发权限请求
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }

    // MARK: - 获取可截取内容
    /// 刷新可截取内容列表
    private func refreshContent() async throws -> SCShareableContent {
        let content = try await SCShareableContent.current
        self.captureContent = content
        return content
    }

    /// 过滤出"用户可见的普通应用窗口"，并按真实 Z 序（从最上层到最底层）返回
    ///
    /// 核心思路：
    /// - 使用 CGWindowListCopyWindowInfo(.optionOnScreenOnly) 获取当前桌面上"真正可见"的窗口
    ///   该 API 严格按 Z 序排列（数组前面的窗口在视觉上更上层），且会自动过滤被遮挡的窗口
    /// - 用 windowNumber 与 SCWindow.windowID 做映射，得到对应的 SCWindow 用于 ScreenCaptureKit 截图
    /// - 对最终结果再做一层属性过滤（layer/owner/尺寸/屏幕范围/SnapClick 自身/系统 UI）
    ///
    /// **线程模型**：CGWindowListCopyWindowInfo 是同步阻塞调用，会同步等待 WindowServer
    /// 返回结果（多窗口/多屏场景下稳定 50-200ms）。本函数被设计为在后台队列执行：
    /// 调用方需先在 MainActor 收集 `screenFrames`（NSScreen.screens 必须在主线程访问），
    /// 再用 `Task.detached` 派发本函数。
    ///
    /// 标 `nonisolated` 是因为 ScreenCaptureEngine 整体是 `@MainActor`，但本函数只读入参、
    /// 不访问 self，可以安全从后台 detached task 调用。
    nonisolated private static func selectableWindows(from content: SCShareableContent,
                                                      screenFrames: [CGRect]) -> [SCWindow] {
        // 系统级 UI 进程，不应作为可截图的"窗口"
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
            // 仅普通应用窗口层（菜单栏/Dock/桌面/输入法 IME 等都是非 0）
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            // 必须实际"在屏"
            if let onScreen = entry[kCGWindowIsOnscreen as String] as? Bool, !onScreen { continue }
            // 必须有 alpha（>0），否则纯透明，用户看不见
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.05 { continue }
            // 本 App 的截图覆盖层等辅助窗口层级高于 0，已被上面的 layer == 0 过滤掉；
            // 此处保留普通层级的 SnapClick 主窗口，使其可被选中截图
            // 取 windowID
            guard let cgID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            // 必须在 SCShareableContent 中存在，否则后面无法用 ScreenCaptureKit 截
            guard let scWin = scIndex[cgID] else { continue }
            // owningApplication 必填
            guard let app = scWin.owningApplication else { continue }
            // 排除系统 UI 进程
            if systemBundles.contains(app.bundleIdentifier) { continue }
            // 取 CGRect（CG 坐标系）
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            // 尺寸太小一般是辅助窗口/装饰（放宽到 60x40，避免遗漏部分合法的工具面板窗口）
            if cgRect.width < 60 || cgRect.height < 40 { continue }
            // 必须与某个屏幕有交集
            guard screenFrames.contains(where: { $0.intersects(scWin.frame) }) else { continue }
            result.append(scWin)
        }
        return result
    }

    /// `selectableWindows(from:screenFrames:)` 的 MainActor 包装：先在主线程收集
    /// `NSScreen.screens`（该 API 必须主线程访问），再通过 `Task.detached` 把
    /// 同步阻塞的 `CGWindowListCopyWindowInfo` 派发到后台队列。
    /// 调用方用 `await` 期间会让出主线程，从而避免在截图启动路径上吃掉 50-200ms。
    private func selectableWindowsDetached(from content: SCShareableContent) async -> [SCWindow] {
        let frames = NSScreen.screens.map { $0.frame }
        return await Task.detached(priority: .userInitiated) {
            Self.selectableWindows(from: content, screenFrames: frames)
        }.value
    }

    // MARK: - 智能截图（区域 + 窗口合一）
    /// 显示覆盖层：悬停高亮窗口，拖拽选区，点击截取窗口
    /// 多屏幕支持：覆盖层显示在鼠标当前所在的屏幕上
    ///
    /// 性能路径：先 `await refreshContent()` 拿一次 `SCShareableContent`（避免再走一次
    /// `SCShareableContent.excludingDesktopWindows` 的 WindowServer 枚举），然后用
    /// `async let` 并行启动「截图」与「窗口过滤」，总耗时从串行的 sum 降到 max。
    func capture() async throws {
        guard !isCapturing else { return }

        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        do {
            let screen = activeScreen()
            let content = try await refreshContent()

            // 并行：截图（已 async）+ 窗口过滤（同步阻塞 CG API，包到 detached 跑）
            async let backgroundImageTask = captureScreen(screen, content: content)
            async let windowsTask = selectableWindowsDetached(from: content)

            let backgroundImage = try await backgroundImageTask
            let windows = await windowsTask

            let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage,
                                               windows: windows,
                                               screen: screen)
            self.overlayWindow = overlay
            overlay.mode = .combined
            overlay.makeKeyAndOrderFront(nil)

            try await waitForOverlayToClose(overlay)
        } catch {
            throw error
        }
    }

    // MARK: - 区域截图
    /// 纯区域框选：只截屏，不枚举窗口列表。直接复用 captureScreen 默认 fallback 路径。
    func captureArea() async throws {
        guard !isCapturing else { return }

        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        do {
            let screen = activeScreen()
            let backgroundImage = try await captureScreen(screen)

            let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage, screen: screen)
            self.overlayWindow = overlay
            overlay.mode = .areaSelection
            NSApp.activate(ignoringOtherApps: true)
            overlay.makeKeyAndOrderFront(nil)

            try await waitForOverlayToClose(overlay)
        } catch {
            throw error
        }
    }

    // MARK: - 长截图
    /// 长截图：先选区，选区完成后直接进入滚动截图模式
    func captureLongScreenshot() async throws {
        // 防止重复触发，确保同时只有一个截图实例运行
        guard !isCapturing else { return }

        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        do {
            let screen = activeScreen()
            let backgroundImage = try await captureScreen(screen)
            let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage, screen: screen)
            self.overlayWindow = overlay
            overlay.mode = .areaSelection
            overlay.isLongScreenshotMode = true
            overlay.makeKeyAndOrderFront(nil)

            try await waitForOverlayToClose(overlay)
        } catch {
            throw error
        }
    }

    // MARK: - 窗口截图
    /// 窗口截图：和智能截图一样的「content 复用 + async let 并行」路径
    func captureWindow() async throws {
        guard !isCapturing else { return }

        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        do {
            let screen = activeScreen()
            let content = try await refreshContent()

            async let backgroundImageTask = captureScreen(screen, content: content)
            async let windowsTask = selectableWindowsDetached(from: content)

            let backgroundImage = try await backgroundImageTask
            let windows = await windowsTask

            let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage,
                                               windows: windows,
                                               screen: screen)
            self.overlayWindow = overlay
            overlay.mode = .windowSelection
            overlay.makeKeyAndOrderFront(nil)

            try await waitForOverlayToClose(overlay)
        } catch {
            throw error
        }
    }

    // MARK: - 全屏截图
    /// 截取当前屏幕并立刻进入就地标注模式
    func captureFullScreen() async throws {
        // 防止重复触发，确保同时只有一个截图实例运行
        guard !isCapturing else { return }

        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        do {
            let screen = activeScreen()
            let backgroundImage = try await captureScreen(screen)

            let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage, screen: screen)
            self.overlayWindow = overlay
            overlay.mode = .areaSelection

            // 直接进入全屏标注模式
            overlay.enterFullScreenAnnotationDirectly()

            overlay.makeKeyAndOrderFront(nil)
            try await waitForOverlayToClose(overlay)
        } catch {
            throw error
        }
    }

    // MARK: - 延时截图
    /// countdown 秒倒计时后执行截图并立刻进入就地标注模式
    func captureWithDelay(_ seconds: Int) async throws {
        // 防止重复触发，确保同时只有一个截图实例运行
        guard !isCapturing else { return }

        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        self.countdown = seconds

        // 倒计时
        for remaining in stride(from: seconds, through: 1, by: -1) {
            self.countdown = remaining
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        self.countdown = 0

        defer { isCapturing = false }

        do {
            // 延时结束后重新检测鼠标所在屏幕（用户在倒计时期间可能已移动到其它屏幕）
            let screen = activeScreen()
            let backgroundImage = try await captureScreen(screen)

            let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage, screen: screen)
            self.overlayWindow = overlay
            overlay.mode = .areaSelection

            // 直接进入全屏标注模式
            overlay.enterFullScreenAnnotationDirectly()

            overlay.makeKeyAndOrderFront(nil)
            try await waitForOverlayToClose(overlay)
        } catch {
            throw error
        }
    }

    // MARK: - 辅助挂起方法
    /// 挂起并等待 Overlay 窗口关闭，从而安全管理 Continuation 对象的生命周期
    private func waitForOverlayToClose(_ overlay: CaptureOverlayWindow) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.overlayContinuation = continuation
            
            overlay.onCancelled = { [weak self] in
                // 必须 orderOut + close 一起调用：仅 orderOut 会让窗口在内存中残留，
                // 下次按 ESC 时 NSApp 仍会向该 keyWindow 投递 keyDown，导致需要按两次 ESC 才能退出
                overlay.orderOut(nil)
                overlay.close()
                self?.overlayWindow = nil
                let cont = self?.overlayContinuation
                self?.overlayContinuation = nil
                cont?.resume(throwing: ScreenCaptureError.userCancelled)
            }

            overlay.onFinished = { [weak self] in
                overlay.orderOut(nil)
                overlay.close()
                self?.overlayWindow = nil
                let cont = self?.overlayContinuation
                self?.overlayContinuation = nil
                cont?.resume()
            }
        }
    }

    // MARK: - 屡屏截图辅助

    /// 返回鼠标当前所在的屏幕；找不到时退化为主屏。
    /// 支持多屏幕：这样用户在哪个屏幕上触发截图，覆盖层就显示在那个屏幕上。
    private func activeScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// 截取指定屏幕的全屏图像（逻辑分辨率）
    /// macOS 14+ 使用 SCScreenshotManager（异步、非阻塞）
    /// macOS 13   降级使用 CGDisplayCreateImage
    ///
    /// - Parameter content: 可选已获取的 `SCShareableContent`。传入后会复用其 `displays`，
    ///   避免再次调用 `SCShareableContent.excludingDesktopWindows` 触发第二次 WindowServer
    ///   IPC 枚举（典型耗时 100-300ms）。调用方在窗口截图/智能截图入口处会先 await 一次
    ///   `SCShareableContent.current`，这里直接复用同一份。
    private func captureScreen(_ screen: NSScreen,
                              content providedContent: SCShareableContent? = nil) async throws -> NSImage {
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        let scale = screen.backingScaleFactor

        if #available(macOS 14.0, *) {
            do {
                // 优先复用调用方已获取的 content，避免重复 SCShareableContent 枚举
                let content: SCShareableContent
                if let provided = providedContent {
                    content = provided
                } else {
                    content = try await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: true)
                }
                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
                        ?? content.displays.first else {
                    throw ScreenCaptureError.noScreenAvailable
                }

                // 只排除截图覆盖层自身的窗口，其余 SnapClick 窗口（如设置界面）正常保留
                var excludedWindows: [SCWindow] = []
                if let overlayWin = self.overlayWindow {
                    let overlayWindowNum = overlayWin.windowNumber
                    let ownPID = ProcessInfo.processInfo.processIdentifier
                    let overlaySCWin = content.windows.first(where: {
                        $0.owningApplication?.processID == ownPID &&
                        $0.windowID == UInt32(overlayWindowNum)
                    })
                    if let w = overlaySCWin { excludedWindows.append(w) }
                }
                let filter = SCContentFilter(display: scDisplay, excludingWindows: excludedWindows)

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
            throw ScreenCaptureError.imageConversionFailed
        }
        let size = NSSize(width:  CGFloat(cgImage.width)  / scale,
                          height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    /// 单窗口精确截图（macOS 14+ 优先 SCScreenshotManager）
    /// 仅截取指定 SCWindow 的内容（不包含其它程序、不包含被遮挡区域之外的内容）
    /// 返回的图片尺寸与窗口逻辑大小相同（点为单位）
    func captureSingleWindow(_ window: SCWindow) async throws -> NSImage {
        let cgID = window.windowID

        if #available(macOS 14.0, *) {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let cfg = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            cfg.width  = max(1, Int(window.frame.width  * scale))
            cfg.height = max(1, Int(window.frame.height * scale))
            cfg.showsCursor = false
            cfg.capturesAudio = false
            if let cg = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: cfg) {
                return NSImage(cgImage: cg, size: window.frame.size)
            }
        }

        // 降级路径：CGWindowListCreateImage（在后台执行避免阻塞）
        let img: CGImage? = await Task.detached(priority: .userInitiated) {
            if let cg = CGWindowListCreateImage(.null,
                                                .optionIncludingWindow,
                                                cgID,
                                                [.boundsIgnoreFraming, .nominalResolution]) {
                return cg
            }
            return CGWindowListCreateImage(.null,
                                           .optionIncludingWindow,
                                           cgID,
                                           [.boundsIgnoreFraming, .bestResolution])
        }.value
        if let img = img {
            return NSImage(cgImage: img, size: window.frame.size)
        }
        throw ScreenCaptureError.imageConversionFailed
    }

    // MARK: - 图像后处理
    /// 应用圆角和阴影，然后显示标注编辑器
    func processAndShowEditor(_ image: NSImage) {
        let settings = ScreenshotSettings.shared
        var processed = image

        if settings.enableRoundedCorners {
            processed = applyRoundedCorners(to: processed, radius: settings.cornerRadius)
        }
        if settings.enableShadow {
            processed = applyShadow(to: processed)
        }

        // 显示标注编辑器窗口
        let editorWindow = AnnotationEditorWindow(screenshot: processed)
        editorWindow.makeKeyAndOrderFront(nil)
    }

    // MARK: - 圆角处理
    /// 给图片添加圆角（离屏 CGContext 绘制，避免 lockFocus 主线程阻塞）
    func applyRoundedCorners(to image: NSImage, radius: CGFloat) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let pxW = cg.width
        let pxH = cg.height
        let scaleX = CGFloat(pxW) / max(image.size.width, 1)
        let pxRadius = radius * scaleX

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: pxW,
                                  height: pxH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        let rectPx = CGRect(x: 0, y: 0, width: pxW, height: pxH)
        let path = CGPath(roundedRect: rectPx, cornerWidth: pxRadius, cornerHeight: pxRadius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(cg, in: rectPx)
        guard let outCG = ctx.makeImage() else { return image }
        return NSImage(cgImage: outCG, size: image.size)
    }

    // MARK: - 阴影处理
    /// 给图片添加阴影效果（离屏 CGContext 绘制）
    func applyShadow(to image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let padding: CGFloat = 40
        let scaleX = CGFloat(cg.width) / max(image.size.width, 1)
        let pxPadding = padding * scaleX

        let pxW = cg.width  + Int(pxPadding * 2)
        let pxH = cg.height + Int(pxPadding * 2)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: pxW,
                                  height: pxH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }

        ctx.clear(CGRect(x: 0, y: 0, width: pxW, height: pxH))

        // 阴影：偏移 8pt（向下，CG 坐标系 Y 向上 → 取负值），模糊半径 20pt
        let shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * scaleX),
                      blur: 20 * scaleX,
                      color: shadowColor)

        let drawRect = CGRect(x: pxPadding,
                              y: pxPadding,
                              width: CGFloat(cg.width),
                              height: CGFloat(cg.height))
        ctx.draw(cg, in: drawRect)
        guard let outCG = ctx.makeImage() else { return image }
        let newSize = NSSize(width:  image.size.width  + padding * 2,
                             height: image.size.height + padding * 2)
        return NSImage(cgImage: outCG, size: newSize)
    }

    // MARK: - 保存截图
    /// 保存截图到指定路径
    @discardableResult
    func saveScreenshot(_ image: NSImage, to path: String) throws -> URL {
        let settings = ScreenshotSettings.shared
        let format = settings.format

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let data = bitmapRep.representation(using: format.bitmapFormat,
                                                   properties: [:]) else {
            throw ScreenCaptureError.saveFailed("无法编码图像数据")
        }

        let url = URL(fileURLWithPath: path)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ScreenCaptureError.saveFailed(error.localizedDescription)
        }
        return url
    }

    /// 根据命名规则生成文件名并保存到默认目录
    @discardableResult
    func saveWithAutoName(_ image: NSImage) async throws -> URL {
        let settings = ScreenshotSettings.shared
        let fileName = generateFileName(settings: settings)
        guard let directoryURL = await SandboxManager.shared.ensureWritableURL(for: settings.saveDirectory) else {
            throw ScreenCaptureError.saveFailed("无法获取可写入的保存目录")
        }

        // 确保目录存在
        try FileManager.default.createDirectory(at: directoryURL,
                                                withIntermediateDirectories: true)

        let fileURL = directoryURL
            .appendingPathComponent(fileName)
            .appendingPathExtension(settings.format.fileExtension)

        return try saveScreenshot(image, to: fileURL.path)
    }

    // MARK: - 复制到剪贴板
    /// 将截图复制到系统剪贴板
    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    // MARK: - 工具方法

    /// 将 CMSampleBuffer 转换为 NSImage
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> NSImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext(options: nil)

        let extent = ciImage.extent
        guard let cgImage = context.createCGImage(ciImage, from: extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage,
                       size: NSSize(width: extent.width, height: extent.height))
    }

    /// 裁剪图像到指定矩形（坐标为屏幕坐标系）
    /// 多屏修复：根据矩形所在屏幕选择对应 backingScaleFactor，避免混合 Retina 错位
    private func cropImage(_ image: NSImage, to rect: CGRect) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ScreenCaptureError.imageConversionFailed
        }

        let scale: CGFloat = {
            if let s = NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.backingScaleFactor {
                return s
            }
            return NSScreen.main?.backingScaleFactor ?? 1.0
        }()
        let scaledRect = CGRect(
            x:      rect.origin.x * scale,
            y:      rect.origin.y * scale,
            width:  rect.width    * scale,
            height: rect.height   * scale
        )

        // CGImage 坐标 Y 轴翻转处理
        let imageHeight = CGFloat(cgImage.height)
        let flippedRect = CGRect(
            x:      scaledRect.origin.x,
            y:      imageHeight - scaledRect.origin.y - scaledRect.height,
            width:  scaledRect.width,
            height: scaledRect.height
        )

        guard let cropped = cgImage.cropping(to: flippedRect) else {
            throw ScreenCaptureError.imageConversionFailed
        }

        return NSImage(cgImage: cropped,
                       size: NSSize(width: rect.width, height: rect.height))
    }

    /// 生成文件名
    private func generateFileName(settings: ScreenshotSettings) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let dateString = dateFormatter.string(from: Date())

        if settings.namingRule == .customPrefix {
            return "\(settings.customPrefix)_\(dateString)"
        } else {
            return "SnapClick_截图_\(dateString)"
        }
    }
}


