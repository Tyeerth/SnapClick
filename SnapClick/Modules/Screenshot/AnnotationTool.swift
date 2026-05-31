// AnnotationTool.swift
// SnapClick - 标注工具定义
// 包含工具类型枚举、标注项结构体、绘制命令协议

import AppKit
import CoreGraphics

// MARK: - 标注工具类型
enum AnnotationToolType: String, CaseIterable, Identifiable {
    case rectangle = "rectangle"
    case ellipse   = "ellipse"
    case arrow     = "arrow"
    case pen       = "pen"
    case mosaic    = "mosaic"
    case text      = "text"
    case number    = "number"
    case highlight = "highlight"
    case eraser    = "eraser"
    case drag      = "drag"

    var id: String { rawValue }

    /// 工具显示名称
    var displayName: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse:   return "椭圆"
        case .arrow:     return "箭头"
        case .pen:       return "画笔"
        case .mosaic:    return "马赛克"
        case .text:      return "文字"
        case .number:    return "序号"
        case .highlight: return "高亮"
        case .eraser:    return "橡皮"
        case .drag:      return "拖动"
        }
    }

    /// 工具快捷键（键盘字母）
    var shortcutKey: String {
        switch self {
        case .rectangle: return "R"
        case .ellipse:   return "E"
        case .arrow:     return "A"
        case .pen:       return "P"
        case .mosaic:    return "M"
        case .text:      return "T"
        case .number:    return "N"
        case .highlight: return "H"
        case .eraser:    return "X"
        case .drag:      return "D"
        }
    }

    /// SF Symbol 图标名称
    var iconName: String {
        switch self {
        case .rectangle: return "square"
        case .ellipse:   return "circle"
        case .arrow:     return "minus"
        case .pen:       return "pencil"
        case .mosaic:    return "square.grid.3x3"
        case .text:      return "t.character"
        case .number:    return "list.number"
        case .highlight: return "highlighter"
        case .eraser:    return "eraser"
        case .drag:      return "hand.draw"
        }
    }

    /// 工具是否需要终点（起点-终点型）
    var requiresEndPoint: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .mosaic, .highlight: return true
        case .pen, .text, .number, .eraser, .drag: return false
        }
    }

    /// 工具是否是路径型（多个点）
    var isPathBased: Bool {
        switch self {
        case .pen, .eraser: return true
        default: return false
        }
    }
}

// MARK: - 标注颜色预设
struct AnnotationColorPreset {
    static let presets: [NSColor] = [
        .systemRed,
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .systemPurple,
        .white,
        .black
    ]
}

// MARK: - 标注项
struct AnnotationItem: Identifiable {
    let id: UUID = UUID()

    // 工具类型
    var type: AnnotationToolType

    // 几何信息
    var startPoint: CGPoint         // 起始点
    var endPoint:   CGPoint         // 终止点（矩形/椭圆/箭头/马赛克/高亮使用）
    var points:     [CGPoint] = []  // 路径点集合（画笔/橡皮使用）

    // 样式
    var color:     NSColor  = .systemRed
    var lineWidth: CGFloat  = 2.0

    // 文字相关
    var text:      String   = ""
    var fontSize:  CGFloat  = 16.0

    // 序号相关
    var numberIndex: Int = 1

    // 计算属性：绘制矩形区域（标准化，起点≤终点）
    var normalizedRect: CGRect {
        let x = min(startPoint.x, endPoint.x)
        let y = min(startPoint.y, endPoint.y)
        let w = abs(endPoint.x - startPoint.x)
        let h = abs(endPoint.y - startPoint.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // 路径边界框（用于橡皮检测）
    var pathBounds: CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        return CGRect(
            x:      xs.min()! - lineWidth,
            y:      ys.min()! - lineWidth,
            width:  xs.max()! - xs.min()! + lineWidth * 2,
            height: ys.max()! - ys.min()! + lineWidth * 2
        )
    }
}

// MARK: - 绘制命令协议
protocol DrawCommand {
    /// 在给定 CGContext 中执行绘制
    func execute(in context: CGContext)
    /// 撤销操作（通常由 AnnotationCanvas 的 undo 机制管理，此处保留接口）
    func undo()
}

// MARK: - 具体绘制命令
struct AddAnnotationCommand: DrawCommand {
    let item: AnnotationItem

    func execute(in context: CGContext) {
        // 实际绘制由 AnnotationCanvas.draw(_:) 统一处理
    }

    func undo() {
        // 由 AnnotationCanvas 弹出最后一个 item 实现
    }
}

// MARK: - 箭头绘制辅助
struct ArrowDrawHelper {
    /// 从 start 到 end 绘制箭头
    static func drawArrow(in context: CGContext,
                          from start: CGPoint,
                          to end: CGPoint,
                          lineWidth: CGFloat,
                          color: NSColor) {
        guard start != end else { return }

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        // 计算箭头角度
        let dx    = end.x - start.x
        let dy    = end.y - start.y
        let angle = atan2(dy, dx)

        // 箭头头部长度和张角
        let headLen:   CGFloat = max(12, lineWidth * 4)
        let headAngle: CGFloat = .pi / 6  // 30°

        // 绘制主线（不覆盖箭头头部区域）
        let lineEnd = CGPoint(
            x: end.x - cos(angle) * headLen * 0.8,
            y: end.y - sin(angle) * headLen * 0.8
        )
        context.move(to: start)
        context.addLine(to: lineEnd)
        context.strokePath()

        // 绘制箭头三角形
        let p1 = CGPoint(
            x: end.x - headLen * cos(angle - headAngle),
            y: end.y - headLen * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLen * cos(angle + headAngle),
            y: end.y - headLen * sin(angle + headAngle)
        )

        let triPath = CGMutablePath()
        triPath.move(to: end)
        triPath.addLine(to: p1)
        triPath.addLine(to: p2)
        triPath.closeSubpath()

        context.addPath(triPath)
        context.fillPath()

        context.restoreGState()
    }
}

// MARK: - 马赛克处理工具
struct MosaicHelper {
    /// 对指定 CGImage 区域进行像素化（马赛克）处理
    /// - Parameters:
    ///   - image:    原始 CGImage
    ///   - rect:     需要像素化的区域（视图坐标，需已标准化）
    ///   - blockSize: 马赛克方块大小（像素）
    static func pixelate(image: CGImage,
                         rect: CGRect,
                         blockSize: Int = 12) -> CGImage? {
        guard blockSize > 0 else { return nil }

        let intX = Int(rect.origin.x)
        let intY = Int(rect.origin.y)
        let intW = max(1, Int(rect.width))
        let intH = max(1, Int(rect.height))

        guard intX >= 0 && intY >= 0
            && intX + intW <= image.width
            && intY + intH <= image.height else { return nil }

        // 裁剪目标区域
        guard let subImage = image.cropping(to: CGRect(x: intX, y: intY,
                                                        width: intW, height: intH)) else {
            return nil
        }

        // 缩小再放大实现像素化
        let smallW = max(1, intW / blockSize)
        let smallH = max(1, intH / blockSize)

        let colorSpace  = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo  = CGImageAlphaInfo.premultipliedLast.rawValue

        // 缩小
        guard let smallCtx = CGContext(data: nil,
                                       width: smallW, height: smallH,
                                       bitsPerComponent: 8,
                                       bytesPerRow: smallW * 4,
                                       space: colorSpace,
                                       bitmapInfo: bitmapInfo) else { return nil }
        smallCtx.interpolationQuality = .none
        smallCtx.draw(subImage, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))

        guard let smallImage = smallCtx.makeImage() else { return nil }

        // 放大回原尺寸
        guard let bigCtx = CGContext(data: nil,
                                     width: intW, height: intH,
                                     bitsPerComponent: 8,
                                     bytesPerRow: intW * 4,
                                     space: colorSpace,
                                     bitmapInfo: bitmapInfo) else { return nil }
        bigCtx.interpolationQuality = .none
        bigCtx.draw(smallImage, in: CGRect(x: 0, y: 0, width: intW, height: intH))

        return bigCtx.makeImage()
    }
}

// MARK: - 自定义带 Hover 事件的按钮
class HoverButton: NSButton {
    var customToolTip: String = ""
    var onHover: ((Bool, HoverButton) -> Void)?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true, self)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false, self)
    }
}
