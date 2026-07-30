// ColorPickerEngine.swift
// SnapClick - 贴图取色模块
// 屏幕取色引擎：全屏捕获、鼠标追踪、颜色采集、放大镜截图、格式转换

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
    /// 放大镜图像（鼠标周围像素，用于放大显示）
    @Published var magnifierImage: NSImage? = nil
    /// 颜色历史记录，最多保存 20 个
    @Published var colorHistory: [NSColor] = []
    /// 全屏截图（在覆盖层出现前捕获，供背景显示及颜色采样）
    @Published var fullScreenCapture: NSImage? = nil

    // MARK: - 私有属性
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var localMonitors: [Any?] = []
    private var overlayController: ColorPickerOverlayWindowController?

    /// 存储的全屏 CGImage（用于直接像素采色，避免每帧调用 CGWindowListCreateImage）
    private var screenCGImage: CGImage? = nil
    private var captureScale: CGFloat = 1.0
    private var captureScreenH: CGFloat = 0.0
    /// 全屏截图包围盒原点（用于将 NSEvent.mouseLocation 映射到 CGImage 坐标空间）
    private var captureUnionOrigin: CGPoint = .zero

    // MARK: - 初始化
    private init() {}

    // MARK: - 公开方法

    /// 启动取色模式（先截全屏，再显示覆盖层）
    /// 返回 false 表示权限不足，调用方应提示用户授权
    @discardableResult
    func startPicking() -> Bool {
        guard !isActive else { return false }

        guard PermissionManager.shared.hasScreenRecordingPermission else {
            let alert = NSAlert()
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "请在系统设置 → 隐私与安全性 → 屏幕录制中授权 SnapClick。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.shared.requestScreenRecordingPermission()
            }
            return false
        }

        captureFullScreen()

        isActive = true

        let controller = ColorPickerOverlayWindowController()
        controller.showWindow(nil)
        overlayController = controller

        // 初始更新
        let initPoint = NSEvent.mouseLocation
        refreshAtPoint(initPoint)

        // ② 全局鼠标移动监听（鼠标在覆盖层以外时也要响应）
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let pt = NSEvent.mouseLocation
            Task { @MainActor in self?.refreshAtPoint(pt) }
        }

        // ③ 本地鼠标移动（覆盖层窗口内）
        let localMM = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            let pt = NSEvent.mouseLocation
            Task { @MainActor in self?.refreshAtPoint(pt) }
            return event   // 不消耗事件，让 SwiftUI 也能响应
        }

        localMonitors = [localMM]

        // ④ ESC 取消
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.stopPicking() }
                return nil
            }
            return event
        }

        return true
    }

    /// 停止取色模式
    func stopPicking() {
        guard isActive else { return }
        isActive = false
        fullScreenCapture = nil
        screenCGImage = nil
        captureUnionOrigin = .zero

        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = keyMonitor   { NSEvent.removeMonitor(m); keyMonitor = nil }
        for m in localMonitors { if let m = m { NSEvent.removeMonitor(m) } }
        localMonitors = []

        overlayController?.close()
        overlayController = nil
    }

    /// 确认当前颜色：写入剪贴板 + 加入历史 + 关闭取色模式
    /// （内部访问级别，供 SwiftUI 视图直接调用）
    func confirmColor() {
        let text = formattedString(for: currentColor)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appendHistory(currentColor)
        stopPicking()
    }

    /// 根据用户在设置中选择的「默认复制格式」生成对应字符串
    /// 与 PinColorSettingsView.swift 中的 ColorFormat 枚举 rawValue 保持一致
    func formattedString(for color: NSColor) -> String {
        let raw = UserDefaults.standard.string(forKey: "PinColor.defaultColorFormat") ?? "HEX"
        switch raw.uppercased() {
        case "RGB":  return rgbString(for: color)
        case "HSL":  return hslString(for: color)
        case "HSB":  return hsbString(for: color)
        case "CMYK": return cmykString(for: color)
        case "LAB":  return labString(for: color)
        default:     return hexString(for: color)
        }
    }

    // MARK: - 私有方法

    /// 刷新指定鼠标坐标处的颜色和放大镜图像
    private func refreshAtPoint(_ point: NSPoint) {
        currentColor = colorFromStoredImage(at: point)
        magnifierImage = captureMagnifierImage(at: point)
    }

    /// 截取全屏图像（存入 fullScreenCapture 和 screenCGImage）
    private func captureFullScreen() {
        guard let screen = NSScreen.main else { return }
        captureScale  = screen.backingScaleFactor
        
        // 获取所有屏幕的完整包围盒，确保多屏截取完整
        let unionFrame = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }
        captureScreenH = unionFrame.height
        captureUnionOrigin = unionFrame.origin

        // 使用 CGRect.infinite 获取完整的桌面快照
        let cg = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
        screenCGImage = cg
        if let cg {
            // size 应该基于 unionFrame，而不是像素大小，这样 SwiftUI 里 scaleToFill 才会对
            fullScreenCapture = NSImage(cgImage: cg, size: unionFrame.size)
        }
    }

    /// 从已存储的全屏 CGImage 中采样指定屏幕坐标的颜色（比实时截图更高效）
    private func colorFromStoredImage(at point: NSPoint) -> NSColor {
        guard let cgImg = screenCGImage else {
            return colorAtMouseLocationFallback(point)
        }

        // 将 NSEvent.mouseLocation（全局坐标，原点在主屏左下角）映射到
        // 全屏截图 CGImage 的像素坐标（原点在左上角）
        let px = Int((point.x - captureUnionOrigin.x) * captureScale)
        let py = Int((captureScreenH - (point.y - captureUnionOrigin.y)) * captureScale)

        guard px >= 0, py >= 0, px < cgImg.width, py < cgImg.height else {
            return colorAtMouseLocationFallback(point)
        }

        // 裁剪 1×1 像素，绘制到已知格式的 Context 中读取 RGB
        let cropRect = CGRect(x: CGFloat(px), y: CGFloat(py), width: 1, height: 1)
        guard let pixel = cgImg.cropping(to: cropRect) else { return .white }

        var data = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: cs,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .white }

        ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return NSColor(srgbRed: CGFloat(data[0]) / 255,
                       green:    CGFloat(data[1]) / 255,
                       blue:     CGFloat(data[2]) / 255,
                       alpha:    1.0)
    }

    /// 备用：实时截取 1×1 像素获取颜色（当存储截图不可用时）
    private func colorAtMouseLocationFallback(_ point: NSPoint) -> NSColor {
        let screenH = NSScreen.main?.frame.height ?? 0
        let cgY = screenH - point.y
        let rect = CGRect(x: point.x, y: cgY, width: 1, height: 1)
        guard let img = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]),
              let dp = img.dataProvider, let rawData = dp.data else { return .white }
        let bytes = CFDataGetBytePtr(rawData)!
        let bpp = img.bitsPerPixel / 8
        guard bpp >= 3 else { return .white }
        return NSColor(srgbRed: CGFloat(bytes[0]) / 255,
                       green:    CGFloat(bytes[1]) / 255,
                       blue:     CGFloat(bytes[2]) / 255,
                       alpha:    1.0)
    }

    /// 从已存储的全屏 CGImage 中截取鼠标周围 29×21 像素区域（与放大镜网格对应）
    /// 使用存储的截图而非实时截屏，避免截入覆盖层自身导致递归显示
    private func captureMagnifierImage(at point: NSPoint) -> NSImage? {
        guard let cgImg = screenCGImage else { return nil }

        let cols: CGFloat = 29, rows: CGFloat = 21
        let scale = captureScale

        // 使用与 colorFromStoredImage 一致的坐标映射逻辑
        let px = Int(((point.x - captureUnionOrigin.x) - floor(cols / 2)) * scale)
        let py = Int(((captureScreenH - (point.y - captureUnionOrigin.y)) - floor(rows / 2)) * scale)
        let pw = Int(cols * scale)
        let ph = Int(rows * scale)

        guard px >= 0, py >= 0,
              px + pw <= cgImg.width,
              py + ph <= cgImg.height else { return nil }

        let cropRect = CGRect(x: CGFloat(px), y: CGFloat(py), width: CGFloat(pw), height: CGFloat(ph))
        guard let cropped = cgImg.cropping(to: cropRect) else { return nil }

        return NSImage(cgImage: cropped, size: NSSize(width: cols, height: rows))
    }

    /// 追加颜色到历史（超 20 个则丢弃最旧）
    private func appendHistory(_ color: NSColor) {
        colorHistory.insert(color, at: 0)
        if colorHistory.count > 20 { colorHistory = Array(colorHistory.prefix(20)) }
    }

    // MARK: - 颜色格式转换

    func hexString(for color: NSColor) -> String {
        let c = normalized(color)
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent   * 255 + 0.5),
                      Int(c.greenComponent * 255 + 0.5),
                      Int(c.blueComponent  * 255 + 0.5))
    }

    func rgbString(for color: NSColor) -> String {
        let c = normalized(color)
        return "rgb(\(Int(c.redComponent*255+0.5)), \(Int(c.greenComponent*255+0.5)), \(Int(c.blueComponent*255+0.5)))"
    }

    func hslString(for color: NSColor) -> String {
        let c = normalized(color)
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let maxC = max(r, g, b), minC = min(r, g, b)
        var h: CGFloat = 0, s: CGFloat = 0
        let l = (maxC + minC) / 2
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

    func hsbString(for color: NSColor) -> String {
        let c = normalized(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return String(format: "hsb(%.0f, %.0f%%, %.0f%%)", h * 360, s * 100, b * 100)
    }

    /// CMYK：先简单 RGB→CMYK（基于 sRGB，未做 ICC 转换）
    func cmykString(for color: NSColor) -> String {
        let c = normalized(color)
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let k = 1 - max(r, g, b)
        let cy: CGFloat
        let mg: CGFloat
        let yl: CGFloat
        if k >= 1 - 1e-6 {
            cy = 0; mg = 0; yl = 0
        } else {
            cy = (1 - r - k) / (1 - k)
            mg = (1 - g - k) / (1 - k)
            yl = (1 - b - k) / (1 - k)
        }
        return String(format: "cmyk(%.0f%%, %.0f%%, %.0f%%, %.0f%%)",
                      cy * 100, mg * 100, yl * 100, k * 100)
    }

    /// CIE Lab（D65）：sRGB → 线性 RGB → XYZ → Lab
    func labString(for color: NSColor) -> String {
        let c = normalized(color)
        // sRGB → linear
        func toLinear(_ v: CGFloat) -> CGFloat {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = toLinear(c.redComponent)
        let g = toLinear(c.greenComponent)
        let b = toLinear(c.blueComponent)
        // linear RGB → XYZ (D65)
        let x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
        let y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
        let z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041
        // 归一化到参考白 D65
        let xn: CGFloat = 0.95047, yn: CGFloat = 1.0, zn: CGFloat = 1.08883
        func f(_ t: CGFloat) -> CGFloat {
            let delta: CGFloat = 6.0 / 29.0
            return t > pow(delta, 3) ? pow(t, 1.0 / 3.0) : (t / (3 * delta * delta) + 4.0 / 29.0)
        }
        let fx = f(x / xn), fy = f(y / yn), fz = f(z / zn)
        let L = 116 * fy - 16
        let aLab = 500 * (fx - fy)
        let bLab = 200 * (fy - fz)
        return String(format: "lab(%.1f, %.1f, %.1f)", L, aLab, bLab)
    }

    func swiftString(for color: NSColor) -> String {
        let c = normalized(color)
        return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)",
                      c.redComponent, c.greenComponent, c.blueComponent)
    }

    func cssString(for color: NSColor) -> String { hexString(for: color) }

    private func normalized(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }
}
