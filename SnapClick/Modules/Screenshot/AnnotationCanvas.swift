// AnnotationCanvas.swift
// SnapClick - 标注画布
// NSView 实现，支持多种标注工具的绘制、撤销/重做和图像导出

import AppKit
import CoreGraphics

// MARK: - 标注画布委托
protocol AnnotationCanvasDelegate: AnyObject {
    /// 标注内容发生变化时调用（用于刷新工具栏按钮状态）
    func canvasDidChange(_ canvas: AnnotationCanvas)
}

// MARK: - 标注画布
class AnnotationCanvas: NSView {

    // MARK: - 委托
    weak var delegate: AnnotationCanvasDelegate?

    // MARK: - 当前工具设置
    var currentTool:      AnnotationToolType = .drag
    var currentColor:     NSColor            = .systemRed
    var currentLineWidth: CGFloat            = 2.0
    var currentFontSize:  CGFloat            = 16.0
    var mosaicBlockSize:  Int                = 12

    // MARK: - 底图（截图）
    var baseImage: NSImage? {
        didSet { needsDisplay = true }
    }

    // MARK: - 序号计数
    private var numberCounter: Int = 1

    // MARK: - 标注数据
    private var items:          [AnnotationItem] = []  // 已完成的标注
    private var redoStack:      [AnnotationItem] = []  // 重做栈
    private var currentDrawing: AnnotationItem?         // 正在绘制的标注
    private var textEditing:    Bool = false            // 是否正在编辑文字

    // MARK: - 文字输入框
    private var textField: NSTextField?

    // MARK: - 初始化
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer   = true
        layer?.backgroundColor = NSColor.white.cgColor

        // 添加文字输入跟踪区域
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    // MARK: - 首响应者
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped:             Bool { true }  // 使用从上到下坐标系

    // MARK: - 绘制
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. 绘制底图（截图）
        if let image = baseImage {
            image.draw(in: bounds)
        } else {
            // 没有底图时绘制白色背景
            NSColor.white.setFill()
            bounds.fill()
        }

        // 2. 绘制高亮工具的暗化蒙层
        drawHighlightMask(context: context)

        // 3. 绘制所有已完成的标注
        for item in items {
            drawAnnotationItem(item, in: context)
        }

        // 4. 绘制正在进行的标注（实时预览）
        if let current = currentDrawing {
            drawAnnotationItem(current, in: context)
        }
    }

    // MARK: - 高亮蒙层
    private func drawHighlightMask(context: CGContext) {
        let highlightItems = items.filter { $0.type == .highlight }
            + (currentDrawing.map { [$0] } ?? []).filter { $0.type == .highlight }

        guard !highlightItems.isEmpty else { return }

        // 整体暗化蒙层
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.fill(bounds)

        // 把每个高亮区域清除掉（恢复原图）
        for item in highlightItems {
            let rect = item.normalizedRect
            if rect.width > 1 && rect.height > 1 {
                // 清除蒙层
                context.clear(rect)

                // 从底图重新绘制该区域（带色调）
                if let image = baseImage {
                    image.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1.0)
                }

                // 叠加高亮色调
                context.setFillColor(item.color.withAlphaComponent(0.25).cgColor)
                context.fill(rect)
            }
        }
        context.restoreGState()
    }

    // MARK: - 单个标注绘制分派
    private func drawAnnotationItem(_ item: AnnotationItem, in context: CGContext) {
        switch item.type {
        case .rectangle: drawRectangle(item, in: context)
        case .ellipse:   drawEllipse(item, in: context)
        case .arrow:     drawArrow(item, in: context)
        case .pen:       drawPen(item, in: context)
        case .mosaic:    drawMosaic(item, in: context)
        case .text:      drawText(item, in: context)
        case .number:    drawNumber(item, in: context)
        case .highlight: break  // 高亮由 drawHighlightMask 统一处理
        case .eraser:    break  // 橡皮已在 mouseUp 时从 items 中移除
        case .drag:      break  // 拖动不绘制
        }
    }

    // MARK: - 矩形绘制
    private func drawRectangle(_ item: AnnotationItem, in context: CGContext) {
        let rect = item.normalizedRect
        guard rect.width > 1 && rect.height > 1 else { return }

        context.saveGState()
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.lineWidth)
        context.stroke(rect)
        context.restoreGState()
    }

    // MARK: - 椭圆绘制
    private func drawEllipse(_ item: AnnotationItem, in context: CGContext) {
        let rect = item.normalizedRect
        guard rect.width > 1 && rect.height > 1 else { return }

        context.saveGState()
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.lineWidth)
        context.strokeEllipse(in: rect)
        context.restoreGState()
    }

    // MARK: - 箭头绘制
    private func drawArrow(_ item: AnnotationItem, in context: CGContext) {
        ArrowDrawHelper.drawArrow(
            in: context,
            from: item.startPoint,
            to: item.endPoint,
            lineWidth: item.lineWidth,
            color: item.color
        )
    }

    // MARK: - 画笔绘制
    private func drawPen(_ item: AnnotationItem, in context: CGContext) {
        guard item.points.count >= 2 else { return }

        context.saveGState()
        context.setStrokeColor(item.color.cgColor)
        context.setLineWidth(item.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: item.points[0])
        for point in item.points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - 马赛克绘制
    private func drawMosaic(_ item: AnnotationItem, in context: CGContext) {
        let rect = item.normalizedRect
        guard rect.width > 1 && rect.height > 1 else { return }
        guard let baseImage = baseImage,
              let cgImage = baseImage.cgImage(forProposedRect: nil,
                                              context: nil,
                                              hints: nil) else { return }

        // 坐标适配（isFlipped=true，不需要额外翻转）
        let scale   = backingScaleFactor
        let srcRect = CGRect(
            x:      rect.origin.x * scale,
            y:      rect.origin.y * scale,
            width:  rect.width    * scale,
            height: rect.height   * scale
        )

        if let pixelated = MosaicHelper.pixelate(image: cgImage,
                                                  rect: srcRect,
                                                  blockSize: mosaicBlockSize) {
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(pixelated, in: rect)
            context.restoreGState()
        } else {
            // 后备方案：绘制半透明灰色块
            context.saveGState()
            context.setFillColor(NSColor.gray.withAlphaComponent(0.5).cgColor)
            context.fill(rect)
            context.restoreGState()
        }
    }

    // MARK: - 文字绘制
    private func drawText(_ item: AnnotationItem, in context: CGContext) {
        guard !item.text.isEmpty else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: item.fontSize, weight: .regular),
            .foregroundColor: item.color
        ]
        let attrStr = NSAttributedString(string: item.text, attributes: attrs)

        NSGraphicsContext.saveGraphicsState()
        attrStr.draw(at: item.startPoint)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - 序号绘制
    private func drawNumber(_ item: AnnotationItem, in context: CGContext) {
        let radius:  CGFloat = max(12, item.fontSize * 0.9)
        let center           = item.startPoint
        let circleRect = CGRect(
            x:      center.x - radius,
            y:      center.y - radius,
            width:  radius * 2,
            height: radius * 2
        )

        context.saveGState()

        // 圆形背景
        context.setFillColor(item.color.cgColor)
        context.fillEllipse(in: circleRect)

        // 序号文字
        let numText = "\(item.numberIndex)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.boldSystemFont(ofSize: item.fontSize * 0.8),
            .foregroundColor: NSColor.white
        ]
        let attrStr  = NSAttributedString(string: numText, attributes: attrs)
        let textSize = attrStr.size()
        let textRect = CGRect(
            x:      center.x - textSize.width  / 2,
            y:      center.y - textSize.height / 2,
            width:  textSize.width,
            height: textSize.height
        )
        NSGraphicsContext.saveGraphicsState()
        attrStr.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }

    // MARK: - 鼠标事件
    override func mouseDown(with event: NSEvent) {
        if currentTool == .drag {
            nextResponder?.mouseDown(with: event)
            return
        }

        // 如果正在编辑文字，先提交
        if textEditing { commitTextInput() }

        let loc = convert(event.locationInWindow, from: nil)

        switch currentTool {
        case .text:
            // 显示内嵌文字输入框
            showTextInput(at: loc)
        case .number:
            // 直接添加序号
            let item = AnnotationItem(
                type:        .number,
                startPoint:  loc,
                endPoint:    loc,
                color:       currentColor,
                lineWidth:   currentLineWidth,
                fontSize:    currentFontSize,
                numberIndex: numberCounter
            )
            numberCounter += 1
            commitItem(item)
        default:
            // 起点-终点型 和 路径型工具
            var item = AnnotationItem(
                type:       currentTool,
                startPoint: loc,
                endPoint:   loc,
                color:      currentColor,
                lineWidth:  currentLineWidth,
                fontSize:   currentFontSize
            )
            if currentTool.isPathBased {
                item.points = [loc]
            }
            currentDrawing = item
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if currentTool == .drag {
            nextResponder?.mouseDragged(with: event)
            return
        }

        guard var drawing = currentDrawing else { return }
        let loc = convert(event.locationInWindow, from: nil)

        if drawing.type.isPathBased {
            drawing.points.append(loc)
        } else {
            drawing.endPoint = loc
        }
        currentDrawing = drawing
        needsDisplay   = true
    }

    override func mouseUp(with event: NSEvent) {
        if currentTool == .drag {
            nextResponder?.mouseUp(with: event)
            return
        }

        guard var drawing = currentDrawing else { return }
        let loc = convert(event.locationInWindow, from: nil)

        if drawing.type.isPathBased {
            drawing.points.append(loc)
        } else {
            drawing.endPoint = loc
        }

        currentDrawing = nil

        // 橡皮：移除与路径相交的标注
        if drawing.type == .eraser {
            applyEraser(path: drawing.points, lineWidth: drawing.lineWidth)
        } else {
            // 忽略太小的操作
            let minSize: CGFloat = 3
            if !drawing.type.isPathBased {
                let rect = drawing.normalizedRect
                if rect.width < minSize && rect.height < minSize { return }
            } else {
                if drawing.points.count < 2 { return }
            }
            commitItem(drawing)
        }
    }

    // MARK: - 文字输入
    private func showTextInput(at point: CGPoint) {
        textEditing = true

        let field = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 200, height: 30))
        field.isEditable       = true
        field.isBordered       = false
        field.drawsBackground  = false
        field.backgroundColor  = .clear
        field.textColor        = currentColor
        field.font             = NSFont.systemFont(ofSize: currentFontSize)
        field.placeholderString = "输入文字…"
        field.focusRingType    = .none

        // 当用户按 Return 或失焦时提交
        field.target = self
        field.action = #selector(textFieldAction(_:))

        addSubview(field)
        window?.makeFirstResponder(field)

        textField = field
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        commitTextInput()
    }

    private func commitTextInput() {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = field.frame.origin

        field.removeFromSuperview()
        textField  = nil
        textEditing = false

        guard !text.isEmpty else { return }

        let item = AnnotationItem(
            type:       .text,
            startPoint: origin,
            endPoint:   origin,
            color:      currentColor,
            lineWidth:  currentLineWidth,
            text:       text,
            fontSize:   currentFontSize
        )
        commitItem(item)
    }

    // MARK: - 提交标注
    private func commitItem(_ item: AnnotationItem) {
        items.append(item)
        redoStack.removeAll()
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }

    // MARK: - 橡皮操作
    private func applyEraser(path: [CGPoint], lineWidth: CGFloat) {
        guard !path.isEmpty else { return }

        // 创建橡皮路径
        let eraserPath = NSBezierPath()
        eraserPath.move(to: path[0])
        for pt in path.dropFirst() { eraserPath.line(to: pt) }
        eraserPath.lineWidth = lineWidth * 10

        // 移除路径范围内的标注
        items.removeAll { item in
            if item.type.isPathBased {
                return item.points.contains { eraserPath.contains($0) }
            } else if item.type == .text || item.type == .number {
                return eraserPath.contains(item.startPoint)
            } else {
                let rect = item.normalizedRect
                let corners: [CGPoint] = [
                    rect.origin,
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.midX, y: rect.midY),
                    CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.maxX, y: rect.maxY)
                ]
                return corners.contains { eraserPath.contains($0) }
            }
        }
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }

    // MARK: - 撤销 / 重做 / 清除
    func undo() {
        guard !items.isEmpty else { return }
        let last = items.removeLast()
        redoStack.append(last)

        // 序号计数回退
        if last.type == .number { numberCounter = max(1, numberCounter - 1) }

        needsDisplay = true
        delegate?.canvasDidChange(self)
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        let item = redoStack.removeLast()
        items.append(item)

        // 序号计数递进
        if item.type == .number { numberCounter += 1 }

        needsDisplay = true
        delegate?.canvasDidChange(self)
    }

    func clear() {
        items.removeAll()
        redoStack.removeAll()
        currentDrawing = nil
        numberCounter  = 1
        needsDisplay   = true
        delegate?.canvasDidChange(self)
    }

    // MARK: - 查询状态
    var canUndo: Bool { !items.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - 导出图像
    func exportAsImage() -> NSImage {
        let size = bounds.size
        let result = NSImage(size: size)
        result.lockFocus()

        // 先画底图
        if let image = baseImage {
            image.draw(in: NSRect(origin: .zero, size: size))
        }

        // 再绘制所有标注（与 draw(_:) 逻辑一致）
        if let context = NSGraphicsContext.current?.cgContext {
            drawHighlightMask(context: context)
            for item in items {
                drawAnnotationItem(item, in: context)
            }
        }

        result.unlockFocus()
        return result
    }

    // MARK: - 键盘事件（快捷键切换工具，由 AnnotationEditorWindow 处理）
    override func keyDown(with event: NSEvent) {
        // 文字编辑时不处理工具快捷键
        if textEditing {
            super.keyDown(with: event)
            return
        }

        // 将快捷键上报给父窗口
        nextResponder?.keyDown(with: event)
    }

    // MARK: - 辅助：backingScaleFactor
    private var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
    }
}
