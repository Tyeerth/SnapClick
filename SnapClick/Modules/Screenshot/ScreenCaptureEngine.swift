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

    // MARK: - 区域截图
    /// 显示覆盖层让用户拖拽选区并进行就地标注，标注完成后自动保存并退出
    func captureArea() async throws {
        // 权限检查：无屏幕录制权限时直接抛错，避免截出黑屏/壁纸
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        // 先获取一张全屏底图用于覆盖层背景
        let backgroundImage = try await captureFullScreenRaw()

        // 创建并显示覆盖层窗口
        let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage)
        self.overlayWindow = overlay
        overlay.mode = .areaSelection
        overlay.makeKeyAndOrderFront(nil)

        try await waitForOverlayToClose(overlay)
    }

    // MARK: - 长截图
    /// 长截图：先选区，选区完成后直接进入滚动截图模式
    func captureLongScreenshot() async throws {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        let backgroundImage = try await captureFullScreenRaw()
        let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage)
        self.overlayWindow = overlay
        overlay.mode = .areaSelection
        overlay.isLongScreenshotMode = true
        overlay.makeKeyAndOrderFront(nil)
        
        try await waitForOverlayToClose(overlay)
    }

    // MARK: - 窗口截图
    /// 显示窗口选择覆盖层，用户点击选中窗口后就地标注
    func captureWindow() async throws {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }

        let content = try await refreshContent()
        let backgroundImage = try await captureFullScreenRaw()

        // 过滤掉自身窗口
        let windows = content.windows.filter {
            $0.isOnScreen && $0.frame.width > 50 && $0.frame.height > 50
        }

        let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage,
                                           windows: windows)
        self.overlayWindow = overlay
        overlay.mode = .windowSelection
        overlay.makeKeyAndOrderFront(nil)

        try await waitForOverlayToClose(overlay)
    }

    // MARK: - 全屏截图
    /// 截取主屏幕并立刻进入就地标注模式
    func captureFullScreen() async throws {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        isCapturing = true
        defer { isCapturing = false }
        
        let backgroundImage = try await captureFullScreenRaw()
        
        let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage)
        self.overlayWindow = overlay
        overlay.mode = .areaSelection
        
        // 直接进入全屏标注模式
        overlay.enterFullScreenAnnotationDirectly()
        
        overlay.makeKeyAndOrderFront(nil)
        try await waitForOverlayToClose(overlay)
    }

    // MARK: - 延时截图
    /// countdown 秒倒计时后执行全屏截图并立刻进入就地标注模式
    func captureWithDelay(_ seconds: Int) async throws {
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
        
        let backgroundImage = try await captureFullScreenRaw()
        
        let overlay = CaptureOverlayWindow(backgroundImage: backgroundImage)
        self.overlayWindow = overlay
        overlay.mode = .areaSelection
        
        // 直接进入全屏标注模式
        overlay.enterFullScreenAnnotationDirectly()
        
        overlay.makeKeyAndOrderFront(nil)
        try await waitForOverlayToClose(overlay)
    }

    // MARK: - 辅助挂起方法
    /// 挂起并等待 Overlay 窗口关闭，从而安全管理 Continuation 对象的生命周期
    private func waitForOverlayToClose(_ overlay: CaptureOverlayWindow) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.overlayContinuation = continuation
            
            overlay.onCancelled = { [weak self] in
                overlay.orderOut(nil)
                self?.overlayWindow = nil
                let cont = self?.overlayContinuation
                self?.overlayContinuation = nil
                cont?.resume(throwing: ScreenCaptureError.userCancelled)
            }
            
            overlay.onFinished = { [weak self] in
                overlay.orderOut(nil)
                self?.overlayWindow = nil
                let cont = self?.overlayContinuation
                self?.overlayContinuation = nil
                cont?.resume()
            }
        }
    }

    /// 内部：截取主屏幕原图
    private func captureFullScreenRaw() async throws -> NSImage {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenCaptureError.imageConversionFailed
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
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
    /// 给图片添加圆角
    func applyRoundedCorners(to image: NSImage, radius: CGFloat) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: radius,
                                yRadius: radius)
        path.addClip()
        image.draw(in: rect)
        result.unlockFocus()
        return result
    }

    // MARK: - 阴影处理
    /// 给图片添加阴影效果
    func applyShadow(to image: NSImage) -> NSImage {
        let padding: CGFloat = 40
        let originalSize = image.size
        let newSize = NSSize(
            width:  originalSize.width  + padding * 2,
            height: originalSize.height + padding * 2
        )

        let result = NSImage(size: newSize)
        result.lockFocus()

        // 清空背景
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: newSize).fill()

        // 设置阴影
        let shadow = NSShadow()
        shadow.shadowColor  = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowBlurRadius = 20
        shadow.set()

        // 绘制图像
        let drawRect = NSRect(
            x: padding,
            y: padding,
            width:  originalSize.width,
            height: originalSize.height
        )
        image.draw(in: drawRect)
        result.unlockFocus()
        return result
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
    func saveWithAutoName(_ image: NSImage) throws -> URL {
        let settings = ScreenshotSettings.shared
        let fileName = generateFileName(settings: settings)
        let directoryURL = URL(fileURLWithPath: settings.saveDirectory)

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
    private func cropImage(_ image: NSImage, to rect: CGRect) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ScreenCaptureError.imageConversionFailed
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
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
        dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dateString = dateFormatter.string(from: Date())

        if settings.namingRule == .customPrefix {
            return "\(settings.customPrefix) \(dateString)"
        } else {
            return "截图 \(dateString)"
        }
    }
}
