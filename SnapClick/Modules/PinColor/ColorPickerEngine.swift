// ColorPickerEngine.swift
// SnapClick - 贴图取色模块
// 屏幕取色引擎：鼠标追踪、颜色采集、放大镜截图、格式转换

import AppKit
import CoreGraphics

@MainActor
final class ColorPickerEngine: ObservableObject {

    // MARK: - 单例
    static let shared = ColorPickerEngine()

    // MARK: - 发布属性
    /// 当前鼠标位置的颜色
    @Published var currentColor: NSColor = .white
    /// 是否正处于取色模式
    @Published var isActive: Bool = false
    /// 放大镜图像（鼠标周围 64×64 放大 16×）
    @Published var magnifierImage: NSImage? = nil
    /// 颜色历史记录，最多保存 20 个
    @Published var colorHistory: [NSColor] = []

    // MARK: - 私有属性
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var localMonitors: [Any] = []
    private var overlayController: ColorPickerOverlayWindowController?

    // MARK: - 初始化
    private init() {}

    // MARK: - 公开方法

    /// 启动取色模式（显示全屏覆盖层，开始追踪鼠标）
    func startPicking() {
        guard !isActive else { return }
        isActive = true

        // 显示全屏覆盖层
        let controller = ColorPickerOverlayWindowController()
        controller.showWindow(nil)
        overlayController = controller

        // 全局鼠标移动监听
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self.currentColor = self.colorAtMouseLocation(point)
                self.magnifierImage = self.captureMagnifierImage(at: point)
            }
        }

        // 本地鼠标移动监听（覆盖层自身窗口上的移动也需要响应）
        let localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self else { return event }
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self.currentColor = self.colorAtMouseLocation(point)
                self.magnifierImage = self.captureMagnifierImage(at: point)
            }
            return event
        }

        // 全局鼠标点击监听（左键确认取色）
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.confirmColor()
            }
        }

        // 本地鼠标点击监听（覆盖层自身窗口上的点击也需要确认取色）
        let localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.confirmColor()
            }
            return nil  // 吞掉事件，防止穿透
        }

        // 将本地监听器也保存，以便后续移除
        localMonitors = [localMouseMonitor, localClickMonitor]

        // 本地按键监听（ESC 取消）
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in
                    self?.stopPicking()
                }
                return nil
            }
            return event
        }
    }

    /// 停止取色模式（隐藏覆盖层，移除所有监听器）
    func stopPicking() {
        guard isActive else { return }
        isActive = false

        // 移除所有事件监听
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = keyMonitor   { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        for m in localMonitors { NSEvent.removeMonitor(m) }
        localMonitors = []

        // 关闭覆盖层
        overlayController?.close()
        overlayController = nil
    }

    // MARK: - 私有方法

    /// 确认当前颜色：写入剪贴板 + 加入历史 + 关闭取色模式
    private func confirmColor() {
        copyToClipboard(currentColor)
        appendHistory(currentColor)
        stopPicking()
    }

    /// 将颜色 HEX 字符串写入系统剪贴板
    private func copyToClipboard(_ color: NSColor) {
        let hex = hexString(for: color)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }

    /// 追加颜色到历史记录（超过 20 个则丢弃最旧的）
    private func appendHistory(_ color: NSColor) {
        colorHistory.insert(color, at: 0)
        if colorHistory.count > 20 {
            colorHistory = Array(colorHistory.prefix(20))
        }
    }

    /// 获取指定屏幕坐标的像素颜色
    /// - 使用 CGWindowListCreateImage 截取 1×1 区域
    private func colorAtMouseLocation(_ point: NSPoint) -> NSColor {
        // 将 NSPoint（左下原点）转换为 CGPoint（左上原点）
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let cgPoint = CGPoint(x: point.x, y: screenHeight - point.y)
        let captureRect = CGRect(x: cgPoint.x, y: cgPoint.y, width: 1, height: 1)

        guard let image = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return .white }

        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return .white }

        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else { return .white }

        let r = CGFloat(bytes[0]) / 255.0
        let g = CGFloat(bytes[1]) / 255.0
        let b = CGFloat(bytes[2]) / 255.0
        let a = bytesPerPixel >= 4 ? CGFloat(bytes[3]) / 255.0 : 1.0

        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// 截取鼠标周围 64×64 区域（用于放大镜展示）
    private func captureMagnifierImage(at point: NSPoint) -> NSImage? {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let size: CGFloat = 64
        let half = size / 2
        let cgY = screenHeight - point.y - half
        let captureRect = CGRect(x: point.x - half, y: cgY, width: size, height: size)

        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    // MARK: - 颜色格式转换

    /// 返回 HEX 字符串，如 #FF5733
    func hexString(for color: NSColor) -> String {
        let c = normalized(color)
        let r = Int(c.redComponent   * 255 + 0.5)
        let g = Int(c.greenComponent * 255 + 0.5)
        let b = Int(c.blueComponent  * 255 + 0.5)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 返回 RGB 字符串，如 rgb(255, 87, 51)
    func rgbString(for color: NSColor) -> String {
        let c = normalized(color)
        let r = Int(c.redComponent   * 255 + 0.5)
        let g = Int(c.greenComponent * 255 + 0.5)
        let b = Int(c.blueComponent  * 255 + 0.5)
        return "rgb(\(r), \(g), \(b))"
    }

    /// 返回 HSL 字符串，如 hsl(14°, 100%, 60%)
    func hslString(for color: NSColor) -> String {
        let c = normalized(color)
        var h: CGFloat = 0, s: CGFloat = 0, l: CGFloat = 0
        // 计算 HSL
        let r = c.redComponent
        let g = c.greenComponent
        let b = c.blueComponent
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        l = (maxC + minC) / 2
        let delta = maxC - minC
        if delta > 0 {
            s = delta / (1 - abs(2 * l - 1))
            switch maxC {
            case r: h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: h = (b - r) / delta + 2
            default: h = (r - g) / delta + 4
            }
            h = (h / 6).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
        }
        return String(format: "hsl(%.0f°, %.0f%%, %.0f%%)", h * 360, s * 100, l * 100)
    }

    /// 返回 SwiftUI Color 字面量字符串
    func swiftString(for color: NSColor) -> String {
        let c = normalized(color)
        return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)",
                      c.redComponent, c.greenComponent, c.blueComponent)
    }

    /// 返回 CSS 颜色字符串（同 HEX）
    func cssString(for color: NSColor) -> String {
        hexString(for: color)
    }

    // MARK: - 辅助

    /// 将颜色转换到 sRGB 色彩空间
    private func normalized(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }
}
