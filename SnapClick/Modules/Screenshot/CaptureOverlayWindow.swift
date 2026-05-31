// CaptureOverlayWindow.swift
// SnapClick - 全屏透明覆盖层窗口
// 提供就地标注（In-Place Annotation）能力，拖拽截图标注一体化

import AppKit
import ScreenCaptureKit
import Vision

// MARK: - 覆盖层工作模式
enum CaptureOverlayMode {
    case areaSelection    // 区域选择模式（拖拽）
    case windowSelection  // 窗口选择模式（点击）
}

// MARK: - 全屏覆盖层窗口
class CaptureOverlayWindow: NSWindow {

    // MARK: 回调
    var onAreaSelected:   ((CGRect) -> Void)?
    var onWindowSelected: ((SCWindow) -> Void)?
    var onCancelled:      (() -> Void)?
    var onFinished:       (() -> Void)?

    // MARK: 工作模式
    var mode: CaptureOverlayMode = .areaSelection {
        didSet { overlayView.mode = mode }
    }
    
    /// 是否为长截图模式（选区后直接进入滚动截图）
    var isLongScreenshotMode: Bool = false {
        didSet { overlayView.isLongScreenshotMode = isLongScreenshotMode }
    }

    // MARK: 私有属性
    private let overlayView: CaptureOverlayView
    private let backgroundImage: NSImage
    private let availableWindows: [SCWindow]

    // MARK: - 初始化
    init(backgroundImage: NSImage,
         windows: [SCWindow] = []) {

        self.backgroundImage  = backgroundImage
        self.availableWindows = windows

        // 获取屏幕帧
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // 初始化覆盖层视图
        self.overlayView = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            backgroundImage: backgroundImage,
            windows: windows
        )

        // 初始化全屏透明无边框窗口
        super.init(
            contentRect: screenFrame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        // 窗口属性设置
        self.level                  = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        self.backgroundColor        = .clear
        self.isOpaque               = false
        self.hasShadow              = false
        self.ignoresMouseEvents     = false
        self.collectionBehavior     = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView            = overlayView
        self.acceptsMouseMovedEvents = true

        // 绑定回调
        overlayView.onCancelled      = { [weak self] in self?.onCancelled?() }
        overlayView.onWindowSelected = { [weak self] win in self?.onWindowSelected?(win) }
        
        // 挂载 window 引用到 view，以便 Done 时可以关闭 window
        overlayView.parentWindow = self
    }

    // MARK: - 键盘事件（ESC 取消，回车确认）
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC 键
            if overlayView.isScrollingCaptureActive {
                overlayView.stopScrollingCapture(saveMode: .cancel)
            } else {
                onCancelled?()
            }
        } else {
            overlayView.handleKeyDown(event: event)
        }
    }

    // MARK: - 直接全屏标注
    func enterFullScreenAnnotationDirectly() {
        overlayView.enterFullScreenAnnotationDirectly()
    }
}

// MARK: - 覆盖层视图
class CaptureOverlayView: NSView, AnnotationCanvasDelegate {

    // MARK: 回调
    var onWindowSelected: ((SCWindow) -> Void)?
    var onCancelled:      (() -> Void)?
    weak var parentWindow: CaptureOverlayWindow?

    // MARK: 工作模式
    var mode: CaptureOverlayMode = .areaSelection {
        didSet { needsDisplay = true }
    }

    // MARK: 私有属性
    private let backgroundImage: NSImage
    private let availableWindows: [SCWindow]


    // 区域选择
    private var startPoint:    NSPoint = .zero
    private var currentPoint:  NSPoint = .zero
    private var isDragging:    Bool    = false
    private var selectedRect:  NSRect  = .zero

    // 拖拽与缩放
    enum DragHandle {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
    }
    private var activeDragHandle: DragHandle? = nil
    private var dragStartRect: NSRect = .zero


    // 窗口高亮
    private var hoveredWindow: SCWindow?

    // 放大镜
    private var magnifierCenter: NSPoint = .zero
    private let magnifierSize: CGFloat   = 120
    private let magnifierScale: CGFloat  = 4.0

    // MARK: ── 就地标注模式属性 ──────────────────────────────────────────
    private var isAnnotating = false
    fileprivate var canvas: AnnotationCanvas?
    private var editorToolbar: NSVisualEffectView?
    
    // MARK: - 长截图属性
    private let stitchingManager = StitchingManager()
    fileprivate var isScrollingCaptureActive = false
    private var captureTimer: Timer?
    private var isTimerCaptureInFlight = false
    fileprivate var isLongScreenshotMode = false // 标记是否为长截图模式
    private var thumbnailWindow: NSWindow?  // 实时预览缩略图窗口
    private var borderIndicatorWindow: NSWindow? // 红色边框指示器窗口
    private var longScreenshotToolbarWindow: NSWindow? // 长截图工具栏窗口

    // 标注控件引用
    private var toolButtons: [AnnotationToolType: NSButton] = [:]
    private var colorPresetButtons: [ColorPresetButton] = []
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var clearButton: NSButton!
    private var doneButton: NSButton!
    private var copyButton: NSButton!
    private var shareButton: NSButton!
    private var colorWell: NSColorWell!
    private var sizeSlider: NSSlider!
    private var sizeLabel: NSTextField!

    // MARK: - 初始化
    init(frame: NSRect,
         backgroundImage: NSImage,
         windows: [SCWindow]) {

        self.backgroundImage  = backgroundImage
        self.availableWindows = windows

        super.init(frame: frame)
        self.wantsLayer = true

        // 跟踪鼠标移动
        let trackingArea = NSTrackingArea(
            rect: frame,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    // MARK: - 绘制
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. 绘制底部截图背景
        backgroundImage.draw(in: bounds)

        // 2. 绘制半透明暗化遮罩
        context.setFillColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.35).cgColor)

        if mode == .areaSelection && (isDragging || isAnnotating || isScrollingCaptureActive) {
            // 区域选择或正在就地标注：只在选区外侧暗化
            let outerPath = CGMutablePath()
            outerPath.addRect(bounds)
            
            let rectToClear = isAnnotating ? selectedRect : normalizedSelectedRect()
            outerPath.addRect(rectToClear)

            context.addPath(outerPath)
            context.fillPath(using: .evenOdd)

            if isScrollingCaptureActive {
                // 长截图捕获中：绘制红色边框和状态提示
                drawScrollingCaptureBorder(context: context)
                drawScrollingCaptureStatus(context: context)
            } else if !isAnnotating || canvas?.currentTool == .drag {
                // 仅在拖拽阶段或处于“拖动”状态下绘制选区边框与尺寸标注
                drawSelectionBorder(context: context)
                drawSizeAnnotation(context: context)
            }
        } else if mode == .windowSelection {
            context.fill(bounds)
            if let win = hoveredWindow {
                drawWindowHighlight(window: win, context: context)
            }
        } else {
            // 未开始拖拽且未标注：整体半透明暗化
            context.fill(bounds)
        }

        // 3. 拖拽选择阶段（放大镜功能已按需求移除）

        // 4. 绘制顶部操作提示（未进入标注且未在长截图捕获时）
        if !isAnnotating && !isScrollingCaptureActive {
            drawHint(context: context)
        }
    }

    // MARK: - 选区矩形（标准化正方向）
    private func normalizedSelectedRect() -> CGRect {
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func drawSelectionBorder(context: CGContext) {
        let rect = isAnnotating ? selectedRect : normalizedSelectedRect()
        guard rect.width > 1 && rect.height > 1 else { return }

        // 1. 绘制浅蓝色边框
        let themeColor = NSColor(red: 0.12, green: 0.56, blue: 1.0, alpha: 1.0) // 微信/Snipaste蓝
        context.setStrokeColor(themeColor.cgColor)
        context.setLineWidth(1.5)
        context.stroke(rect)

        // 2. 绘制 8 个控制点 (加粗边角)
        context.setFillColor(themeColor.cgColor)
        
        let pointSize: CGFloat = 8.0
        let halfSize = pointSize / 2.0
        
        let points = [
            CGPoint(x: rect.minX, y: rect.minY), // 左上
            CGPoint(x: rect.midX, y: rect.minY), // 中上
            CGPoint(x: rect.maxX, y: rect.minY), // 右上
            CGPoint(x: rect.minX, y: rect.midY), // 左中
            CGPoint(x: rect.maxX, y: rect.midY), // 右中
            CGPoint(x: rect.minX, y: rect.maxY), // 左下
            CGPoint(x: rect.midX, y: rect.maxY), // 中下
            CGPoint(x: rect.maxX, y: rect.maxY)  // 右下
        ]
        
        for point in points {
            let handleRect = CGRect(x: point.x - halfSize, y: point.y - halfSize, width: pointSize, height: pointSize)
            context.fillEllipse(in: handleRect)
        }
        
        // 可选：如果要画成线段直角，可以用路径，这里用实心小圆点/方块更简单且直观
        // 这里采用圆点作为控制点
    }

    // MARK: - 绘制尺寸标注
    private func drawSizeAnnotation(context: CGContext) {
        let rect   = isAnnotating ? selectedRect : normalizedSelectedRect()
        let scale  = NSScreen.main?.backingScaleFactor ?? 1.0
        let wPx    = Int(rect.width  * scale)
        let hPx    = Int(rect.height * scale)
        let text   = "\(wPx) × \(hPx)"

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attrStr   = NSAttributedString(string: text, attributes: attrs)
        let textSize  = attrStr.size()
        let padding:  CGFloat = 6
        let boxWidth  = textSize.width  + padding * 2
        let boxHeight = textSize.height + padding * 2

        var boxX = rect.midX - boxWidth / 2
        var boxY = rect.minY - boxHeight - 8
        if boxY < 4 { boxY = rect.maxY + 8 }
        boxX = max(4, min(boxX, bounds.width - boxWidth - 4))

        let boxRect = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)

        context.setFillColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.65).cgColor)
        let path = CGPath(roundedRect: boxRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        let textRect = boxRect.insetBy(dx: padding, dy: padding)
        NSGraphicsContext.saveGraphicsState()
        attrStr.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - 绘制窗口高亮
    private func drawWindowHighlight(window: SCWindow, context: CGContext) {
        let screenHeight = bounds.height
        let winFrame = window.frame
        let viewRect = CGRect(
            x:      winFrame.origin.x,
            y:      screenHeight - winFrame.origin.y - winFrame.height,
            width:  winFrame.width,
            height: winFrame.height
        )

        context.clear(viewRect)
        backgroundImage.draw(
            in:   viewRect,
            from: CGRect(
                x:      winFrame.origin.x,
                y:      winFrame.origin.y,
                width:  winFrame.width,
                height: winFrame.height
            ),
            operation: .sourceOver,
            fraction:  1.0
        )

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(3)
        context.stroke(viewRect.insetBy(dx: 1.5, dy: 1.5))
    }

    // MARK: - 绘制放大镜
    private func drawMagnifier(context: CGContext) {
        let mousePos = magnifierCenter
        let halfSize = magnifierSize / 2

        var magX = mousePos.x + 20
        var magY = mousePos.y + 20
        if magX + magnifierSize > bounds.width  { magX = mousePos.x - magnifierSize - 20 }
        if magY + magnifierSize > bounds.height { magY = mousePos.y - magnifierSize - 20 }

        let magRect = CGRect(x: magX, y: magY, width: magnifierSize, height: magnifierSize)

        let circlePath = CGPath(ellipseIn: magRect, transform: nil)
        context.saveGState()
        context.addPath(circlePath)
        context.clip()

        let srcW = magnifierSize / magnifierScale
        let srcH = magnifierSize / magnifierScale
        let srcRect = CGRect(
            x:      mousePos.x - srcW / 2,
            y:      mousePos.y - srcH / 2,
            width:  srcW,
            height: srcH
        )
        backgroundImage.draw(in: magRect, from: srcRect, operation: .sourceOver, fraction: 1.0)

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        let midX = magX + halfSize
        let midY = magY + halfSize
        context.move(to: CGPoint(x: midX - halfSize, y: midY))
        context.addLine(to: CGPoint(x: midX + halfSize, y: midY))
        context.move(to: CGPoint(x: midX, y: midY - halfSize))
        context.addLine(to: CGPoint(x: midX, y: midY + halfSize))
        context.strokePath()

        context.restoreGState()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.addPath(circlePath)
        context.strokePath()
    }

    // MARK: - 绘制操作提示
    private func drawHint(context: CGContext) {
        let hint: String
        if isLongScreenshotMode {
            hint = "拖拽选择要长截图的区域  |  ESC 取消"
        } else {
            hint = mode == .areaSelection ? "拖拽选择截图区域  |  ESC 取消" : "点击选择要截图的窗口  |  ESC 取消"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white
        ]
        let attrStr  = NSAttributedString(string: hint, attributes: attrs)
        let textSize = attrStr.size()
        let padding: CGFloat = 10
        let boxRect = CGRect(
            x:      (bounds.width - textSize.width) / 2 - padding,
            y:      bounds.height - 60,
            width:  textSize.width + padding * 2,
            height: textSize.height + padding
        )

        let bgPath = CGPath(roundedRect: boxRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.setFillColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.6).cgColor)
        context.addPath(bgPath)
        context.fillPath()
        attrStr.draw(in: boxRect.insetBy(dx: padding, dy: padding / 2))
    }

    // MARK: - 绘制长截图捕获中的红色边框
    private func drawScrollingCaptureBorder(context: CGContext) {
        let rect = selectedRect
        guard rect.width > 1 && rect.height > 1 else { return }

        // 蓝色实线边框
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(3.0)
        context.stroke(rect)

        // 四角标记
        let cornerLength: CGFloat = 16
        let cornerWidth: CGFloat = 4
        context.setFillColor(NSColor.systemBlue.cgColor)

        // 左上
        context.fill(CGRect(x: rect.minX - cornerWidth / 2, y: rect.minY - cornerWidth / 2, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: rect.minX - cornerWidth / 2, y: rect.minY - cornerWidth / 2, width: cornerWidth, height: cornerLength))

        // 右上
        context.fill(CGRect(x: rect.maxX - cornerLength + cornerWidth / 2, y: rect.minY - cornerWidth / 2, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: rect.maxX - cornerWidth / 2, y: rect.minY - cornerWidth / 2, width: cornerWidth, height: cornerLength))

        // 左下
        context.fill(CGRect(x: rect.minX - cornerWidth / 2, y: rect.maxY - cornerWidth / 2, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: rect.minX - cornerWidth / 2, y: rect.maxY - cornerLength + cornerWidth / 2, width: cornerWidth, height: cornerLength))

        // 右下
        context.fill(CGRect(x: rect.maxX - cornerLength + cornerWidth / 2, y: rect.maxY - cornerWidth / 2, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: rect.maxX - cornerWidth / 2, y: rect.maxY - cornerLength + cornerWidth / 2, width: cornerWidth, height: cornerLength))
    }

    // MARK: - 绘制长截图状态提示
    private func drawScrollingCaptureStatus(context: CGContext) {
        let rect = selectedRect
        let text = "正在捕获长截图...  按 Enter 保存 | ESC 取消"

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attrStr  = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let padding: CGFloat = 12
        let boxWidth  = textSize.width + padding * 2
        let boxHeight = textSize.height + padding
        let boxRect = CGRect(
            x:      rect.midX - boxWidth / 2,
            y:      rect.minY - boxHeight - 12,
            width:  boxWidth,
            height: boxHeight
        )

        // 确保不超出屏幕
        var finalRect = boxRect
        if finalRect.minY < 4 {
            finalRect.origin.y = rect.maxY + 12
        }
        finalRect.origin.x = max(4, min(finalRect.origin.x, bounds.width - boxWidth - 4))

        let bgPath = CGPath(roundedRect: finalRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
        context.addPath(bgPath)
        context.fillPath()
        attrStr.draw(in: finalRect.insetBy(dx: padding, dy: padding / 2))
    }


    private func getHandleAt(point: NSPoint) -> DragHandle? {
        if !isAnnotating { return nil }
        let rect = selectedRect
        let threshold: CGFloat = 10.0
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let midX = rect.midX
        let midY = rect.midY
        
        let p = point
        
        if abs(p.x - minX) < threshold && abs(p.y - minY) < threshold { return .topLeft }
        if abs(p.x - maxX) < threshold && abs(p.y - minY) < threshold { return .topRight }
        if abs(p.x - minX) < threshold && abs(p.y - maxY) < threshold { return .bottomLeft }
        if abs(p.x - maxX) < threshold && abs(p.y - maxY) < threshold { return .bottomRight }
        
        if abs(p.y - minY) < threshold && p.x > minX && p.x < maxX { return .top }
        if abs(p.y - maxY) < threshold && p.x > minX && p.x < maxX { return .bottom }
        if abs(p.x - minX) < threshold && p.y > minY && p.y < maxY { return .left }
        if abs(p.x - maxX) < threshold && p.y > minY && p.y < maxY { return .right }
        
        if rect.contains(p) { return .center }
        
        return nil
    }

    private func updateCanvasBaseImage() {
        guard let canvas = self.canvas else { return }
        canvas.frame = selectedRect
        
        let screenHeight = bounds.height
        let cropY = screenHeight - selectedRect.origin.y - selectedRect.height
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let cropRect = CGRect(
            x:      selectedRect.origin.x * scale,
            y:      cropY * scale,
            width:  selectedRect.width * scale,
            height: selectedRect.height * scale
        )
        
        if let cgImg = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?
            .cropping(to: cropRect) {
            let canvasImage = NSImage(cgImage: cgImg, size: selectedRect.size)
            canvas.baseImage = canvasImage
        }
        
        // 重新布局工具栏
        layoutToolbar()
    }

    private func layoutToolbar() {
        guard let toolbar = editorToolbar else { return }
        
        let mainStack = toolbar.subviews.compactMap { $0 as? NSStackView }.first
        mainStack?.layoutSubtreeIfNeeded()
        let targetWidth = mainStack != nil ? (mainStack!.fittingSize.width + 24) : 633
        
        var tbY = selectedRect.minY - 56
        if tbY < 10 { tbY = selectedRect.maxY + 12 }
        let tbX = selectedRect.midX - targetWidth / 2
        toolbar.frame = CGRect(
            x:      max(10, min(tbX, bounds.width - targetWidth - 10)),
            y:      tbY,
            width:  targetWidth,
            height: 44
        )
    }

    // MARK: - 鼠标事件
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        if isAnnotating && canvas?.currentTool == .drag {
            if let handle = getHandleAt(point: loc) {
                activeDragHandle = handle
                dragStartRect = selectedRect
                startPoint = loc
                return
            }
        }
        
        guard !isAnnotating else { return } // 正在就地标注时，截获鼠标逻辑不在此处处理

        switch mode {
        case .areaSelection:
            startPoint   = loc
            currentPoint = loc
            isDragging   = true
            needsDisplay = true

        case .windowSelection:
            if let win = windowAtPoint(loc) {
                let screenHeight = bounds.height
                let winFrame = win.frame
                let viewRect = CGRect(
                    x:      winFrame.origin.x,
                    y:      screenHeight - winFrame.origin.y - winFrame.height,
                    width:  winFrame.width,
                    height: winFrame.height
                )
                selectedRect = viewRect.intersection(bounds)
                enterInPlaceAnnotationMode()
            } else {
                onCancelled?()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        if isAnnotating && canvas?.currentTool == .drag, let handle = activeDragHandle {
            let dx = loc.x - startPoint.x
            let dy = loc.y - startPoint.y
            var newRect = dragStartRect
            
            switch handle {
            case .topLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
                newRect.origin.y += dy
                newRect.size.height -= dy
            case .top:
                newRect.origin.y += dy
                newRect.size.height -= dy
            case .topRight:
                newRect.size.width += dx
                newRect.origin.y += dy
                newRect.size.height -= dy
            case .left:
                newRect.origin.x += dx
                newRect.size.width -= dx
            case .right:
                newRect.size.width += dx
            case .bottomLeft:
                newRect.origin.x += dx
                newRect.size.width -= dx
                newRect.size.height += dy
            case .bottom:
                newRect.size.height += dy
            case .bottomRight:
                newRect.size.width += dx
                newRect.size.height += dy
            case .center:
                newRect.origin.x += dx
                newRect.origin.y += dy
            }
            
            // 限制边界和最小尺寸
            let minSize: CGFloat = 20
            if newRect.width < minSize {
                newRect.size.width = minSize
                if handle == .topLeft || handle == .left || handle == .bottomLeft {
                    newRect.origin.x = dragStartRect.maxX - minSize
                }
            }
            if newRect.height < minSize {
                newRect.size.height = minSize
                if handle == .topLeft || handle == .top || handle == .topRight {
                    newRect.origin.y = dragStartRect.maxY - minSize
                }
            }
            
            // 不能超出屏幕
            newRect.origin.x = max(0, min(newRect.origin.x, bounds.width - newRect.width))
            newRect.origin.y = max(0, min(newRect.origin.y, bounds.height - newRect.height))
            
            selectedRect = newRect
            updateCanvasBaseImage()
            needsDisplay = true
            return
        }
        
        guard mode == .areaSelection && !isAnnotating else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        magnifierCenter = currentPoint
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isAnnotating && canvas?.currentTool == .drag && activeDragHandle != nil {
            activeDragHandle = nil
            return
        }
        
        guard mode == .areaSelection && isDragging && !isAnnotating else { return }
        isDragging = false
        let rect = normalizedSelectedRect()

        if rect.width < 10 || rect.height < 10 {
            needsDisplay = true
            return
        }

        selectedRect = rect
        
        if isLongScreenshotMode {
            // 长截图模式：选区后直接进入滚动截图，不进入标注模式
            enterScrollingCaptureMode()
        } else {
            // 🌟 正式进入就地标注模式，不退出窗口，不弹窗！
            enterInPlaceAnnotationMode()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if isAnnotating && canvas?.currentTool == .drag {
            let loc = convert(event.locationInWindow, from: nil)
            if let handle = getHandleAt(point: loc) {
                switch handle {
                case .topLeft, .bottomRight: NSCursor.crosshair.set() // TODO: should use better cursor
                case .topRight, .bottomLeft: NSCursor.crosshair.set()
                case .top, .bottom: NSCursor.resizeUpDown.set()
                case .left, .right: NSCursor.resizeLeftRight.set()
                case .center: NSCursor.openHand.set()
                }
            } else {
                NSCursor.arrow.set()
            }
        }
        
        guard !isAnnotating else { return }
        let loc = convert(event.locationInWindow, from: nil)
        magnifierCenter = loc

        if mode == .windowSelection {
            hoveredWindow = windowAtPoint(loc)
        }
        needsDisplay = true
    }

    // MARK: - 🌟 核心：直接全屏标注
    func enterFullScreenAnnotationDirectly() {
        selectedRect = bounds
        enterInPlaceAnnotationMode()
    }

    // MARK: - 🌟 核心：进入就地标注模式
    private func enterInPlaceAnnotationMode() {
        isAnnotating = true
        needsDisplay = true // 强制重绘，高亮选区，外侧暗化

        // 1. 从 backgroundImage 中裁剪出该选区矩形作为画布的底图
        let screenHeight = bounds.height
        let cropY = screenHeight - selectedRect.origin.y - selectedRect.height
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let cropRect = CGRect(
            x:      selectedRect.origin.x * scale,
            y:      cropY * scale,
            width:  selectedRect.width * scale,
            height: selectedRect.height * scale
        )
        
        if let cgImg = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?
            .cropping(to: cropRect) {
            
            let canvasImage = NSImage(cgImage: cgImg, size: selectedRect.size)
            
            // 2. 原位初始化 AnnotationCanvas
            let annotationCanvas = AnnotationCanvas(frame: selectedRect)
            annotationCanvas.baseImage = canvasImage
            annotationCanvas.delegate = self
            addSubview(annotationCanvas)
            self.canvas = annotationCanvas
            
            // 设为主响应者，从而直接在原位拦截鼠标绘制笔触！
            window?.makeFirstResponder(annotationCanvas)
        }

        // 3. 原位初始化悬浮底栏 editorToolbar (Vibrant-dark 材质)
        let toolbar = NSVisualEffectView()
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 22
        toolbar.layer?.masksToBounds = true
        toolbar.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        toolbar.layer?.borderWidth = 0.5
        addSubview(toolbar)
        self.editorToolbar = toolbar

        layoutToolbar()

        // 初始化隐藏的 colorWell 用于承载高级调色盘
        colorWell = NSColorWell()
        colorWell.isHidden = true
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged(_:))
        addSubview(colorWell)

        // 4. 挂载子控件
        setupToolbarControls()

        
        
        
        
        
        
        
        
        
        
        // 5. 默认选中拖动工具
        selectTool(.drag)
        updateButtonStates()
    }

    // MARK: - 标注控件排版配置
    private func setupToolbarControls() {
        guard let toolbar = editorToolbar else { return }

        let mainStack = NSStackView()
        mainStack.orientation = .horizontal
        mainStack.spacing = 2 // 控制组间最小间距
        mainStack.alignment = .centerY
        
        // 1. 全部工具组合并，消除它们之间的额外分隔符
        let toolsStack = makeAllToolsGroup()
        mainStack.addArrangedSubview(toolsStack)
        
        // 自定义紧凑间距，让颜色球组紧贴长截图按钮
        mainStack.setCustomSpacing(2, after: toolsStack)
        
        // 2. 颜色球选择组
        let colorGroup = makeColorPresetGroup()
        mainStack.addArrangedSubview(colorGroup)
        
        mainStack.addArrangedSubview(makeSeparator())
        
        // 3. 右侧动作组
        let actionGroup = makeActionButtonsGroup()
        mainStack.addArrangedSubview(actionGroup)
        
        toolbar.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStack.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            mainStack.topAnchor.constraint(equalTo: toolbar.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor)
        ])
    }

    private func makeAllToolsGroup() -> NSStackView {
        let tools: [AnnotationToolType] = [.rectangle, .ellipse, .arrow, .pen, .text, .highlight, .mosaic, .number]
        var buttons: [NSView] = []
        for tool in tools {
            let btn = makeToolButton(for: tool)
            toolButtons[tool] = btn
            buttons.append(btn)
        }
        
        let longBtn = makeIconButton(symbol: "arrow.up.and.down", tip: "滚动截长图", action: #selector(longScreenshotAction))
        buttons.append(longBtn)
        
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 0 // 更紧凑的各个工具间距
        return stack
    }

    private func makeColorPresetGroup() -> NSStackView {
        let colors: [NSColor] = [
            .systemBlue,
            .systemRed,
            .systemGreen,
            .systemOrange
        ]
        var views: [NSView] = []
        colorPresetButtons.removeAll()
        
        for color in colors {
            let btn = ColorPresetButton(color: color, parentView: self)
            colorPresetButtons.append(btn)
            views.append(btn)
        }
        
        // 调色盘按钮
        let paletteBtn = makeIconButton(symbol: "paintpalette", tip: "高级颜色", action: #selector(paletteButtonClicked))
        views.append(paletteBtn)
        
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 2
        return stack
    }

    private func makeActionButtonsGroup() -> NSStackView {
        let pinBtn = makeIconButton(symbol: "pin", tip: "贴图到桌面", action: #selector(pinAction))
        
        // 保存按钮
        let saveBtn = makeIconButton(symbol: "square.and.arrow.down", tip: "保存至本地", action: #selector(saveToLocalAction))
        
        // Done 胶囊按钮
        doneButton = NSButton(frame: CGRect(x: 0, y: 0, width: 60, height: 28))
        doneButton.bezelStyle = .regularSquare
        doneButton.isBordered = false
        doneButton.wantsLayer = true
        doneButton.layer?.cornerRadius = 14
        doneButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        doneButton.title = "Done"
        doneButton.contentTintColor = .white
        doneButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        doneButton.target = self
        doneButton.action = #selector(doneAction)
        
        doneButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        doneButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        
        let cancelBtn = makeIconButton(symbol: "xmark", tip: "取消", action: #selector(cancelAction))
        
        let stack = NSStackView(views: [pinBtn, saveBtn, cancelBtn, doneButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        return stack
    }

    private func makeToolButton(for tool: AnnotationToolType) -> HoverButton {
        let btn = HoverButton(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
        btn.bezelStyle    = .regularSquare
        btn.isBordered    = false
        btn.imagePosition = .imageOnly
        btn.wantsLayer    = true
        btn.layer?.cornerRadius = 17
        
        let pointSize: CGFloat = tool == .text ? 20 : 16
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        if let img = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.displayName)?
            .withSymbolConfiguration(config) {
             btn.image = img
        } else {
            btn.title = tool.shortcutKey
        }
        
        btn.contentTintColor = .white
        btn.customToolTip    = "\(tool.displayName) (\(tool.shortcutKey))"
        btn.onHover          = { [weak self] isHovered, button in
            self?.handleButtonHover(isHovered: isHovered, button: button)
        }
        btn.target           = self
        btn.action           = #selector(toolButtonClicked(_:))
        btn.tag              = AnnotationToolType.allCases.firstIndex(of: tool) ?? 0
        
        btn.widthAnchor.constraint(equalToConstant: 34).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return btn
    }

    private func makeIconButton(symbol: String, tip: String, action: Selector) -> HoverButton {
        let btn = HoverButton(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 16
        
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(config) {
            btn.image = img
        }
        btn.contentTintColor = .white
        btn.target   = self
        btn.action   = action
        btn.customToolTip = tip
        btn.onHover       = { [weak self] isHovered, button in
            self?.handleButtonHover(isHovered: isHovered, button: button)
        }
        
        btn.widthAnchor.constraint(equalToConstant: 32).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return btn
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return sep
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = NSColor.white.withAlphaComponent(0.7)
        label.font      = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        return label
    }

    // MARK: - 自定义 ToolTip
    private var customToolTipView: NSView?
    private var customToolTipLabel: NSTextField?
    
    private func handleButtonHover(isHovered: Bool, button: HoverButton) {
        if !isHovered {
            customToolTipView?.isHidden = true
            return
        }
        if button.customToolTip.isEmpty { return }
        
        if customToolTipView == nil {
            let effect = NSView()
            effect.wantsLayer = true
            effect.layer?.backgroundColor = NSColor.black.cgColor
            effect.layer?.cornerRadius = 6
            effect.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            effect.layer?.borderWidth = 0.5
            
            let label = NSTextField(labelWithString: "")
            label.textColor = .white
            label.font = NSFont.systemFont(ofSize: 11)
            effect.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
                label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -4)
            ])
            
            self.addSubview(effect)
            self.customToolTipView = effect
            self.customToolTipLabel = label
        }
        
        customToolTipLabel?.stringValue = button.customToolTip
        customToolTipView?.isHidden = false
        
        let btnFrame = button.convert(button.bounds, to: self)
        customToolTipLabel?.sizeToFit()
        let width = (customToolTipLabel?.bounds.width ?? 0) + 16
        let height: CGFloat = 22
        
        // 显示在按钮上方
        customToolTipView?.frame = CGRect(
            x: btnFrame.midX - width / 2,
            y: btnFrame.maxY + 8,
            width: width,
            height: height
        )
    }



    // MARK: - 动态位移与 Toast 提示
    
    private func repositionToolbarAndIndicator() {
        guard let toolbar = editorToolbar else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // 动态计算所需宽度以包裹内部 StackView，边距进一步缩小到总计 16px (左右各 8px)
            let mainStack = toolbar.subviews.compactMap { $0 as? NSStackView }.first
            mainStack?.layoutSubtreeIfNeeded()
            let targetWidth = mainStack != nil ? (mainStack!.fittingSize.width + 24) : 633
            
            // 重新计算工具栏 frame
            var tbY = selectedRect.minY - 56
            if tbY < 10 { tbY = selectedRect.maxY + 12 }
            let tbX = selectedRect.midX - targetWidth / 2
            toolbar.animator().frame = CGRect(
                x:      max(10, min(tbX, bounds.width - targetWidth - 10)),
                y:      tbY,
                width:  targetWidth,
                height: 44
            )
        }
    }

    private func showToast(_ message: String) {
        let toast = NSVisualEffectView()
        toast.material = .hudWindow
        toast.blendingMode = .withinWindow
        toast.state = .active
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 18
        toast.layer?.borderColor = NSColor(white: 1.0, alpha: 0.2).cgColor
        toast.layer?.borderWidth = 0.5
        toast.alphaValue = 0.0
        
        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        
        toast.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -8)
        ])
        
        addSubview(toast)
        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            toast.animator().alphaValue = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                toast.animator().alphaValue = 0.0
            }) {
                toast.removeFromSuperview()
            }
        }
    }

    // MARK: - 特殊交互逻辑响应

    @objc private func longScreenshotAction() {
        if isScrollingCaptureActive {
            stopScrollingCapture(saveMode: .copyToClipboardAndSave)
        } else {
            startScrollingCapture()
        }
    }
    
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    /// 长截图模式：选区后直接进入滚动截图（不经过标注模式）
    private func enterScrollingCaptureMode() {
        startScrollingCapture()
    }
    
    private func startScrollingCapture() {
        isScrollingCaptureActive = true
        
        // 隐藏主覆盖窗口，让鼠标/滚动事件能穿透到下层应用
        self.window?.orderOut(nil)
        
        // 创建独立的红色边框指示器窗口（ignoresMouseEvents，不影响下层交互）
        let rectInScreen = self.window?.convertToScreen(self.convert(self.selectedRect, to: nil)) ?? self.selectedRect
        createBorderIndicator(rect: rectInScreen)
        createLongScreenshotToolbar(rect: rectInScreen)
        
        // 监听全局和本地的 Enter/ESC 键
        let handler: (NSEvent) -> Void = { [weak self] event in
            if event.keyCode == 36 { // Enter - 保存
                DispatchQueue.main.async {
                    self?.stopScrollingCapture(saveMode: .copyToClipboardAndSave)
                }
            } else if event.keyCode == 53 { // ESC - 取消
                DispatchQueue.main.async {
                    self?.stopScrollingCapture(saveMode: .cancel)
                }
            }
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
        
        let captureSize = self.selectedRect.size
        
        // 使用 CGWindowListCreateImage 进行截图（排除自身窗口）
        let captureQueue = DispatchQueue(label: "com.snapclick.capture", qos: .userInteractive)
        
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            if let image = self.captureScreenshotForStitching(rect: rectInScreen, size: captureSize) {
                self.stitchingManager.startStitching(with: image)
            }
        }
        
        // 定时持续截图（每 0.25 秒捕获一帧）
        self.captureTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.isScrollingCaptureActive, !self.isTimerCaptureInFlight else { return }
            self.isTimerCaptureInFlight = true
            
            captureQueue.async {
                if let image = self.captureScreenshotForStitching(rect: rectInScreen, size: captureSize) {
                    self.stitchingManager.addImage(image)
                    
                    // 更新缩略图预览
                    DispatchQueue.main.async {
                        if let stitched = self.stitchingManager.currentStitchedImage {
                            self.updateThumbnail(with: stitched)
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.isTimerCaptureInFlight = false
                }
            }
        }
    }
    
    /// 创建红色边框指示器窗口（不影响下层窗口的鼠标事件）
    private func createBorderIndicator(rect screenRect: NSRect) {
        let borderView = LongScreenshotBorderView(frame: NSRect(origin: .zero, size: screenRect.size))
        
        let window = NSWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true  // 关键：不拦截鼠标事件
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = borderView
        window.makeKeyAndOrderFront(nil)
        self.borderIndicatorWindow = window
    }
    
    /// 截取指定区域的截图
    private func captureScreenshotForStitching(rect screenRect: NSRect, size: NSSize) -> NSImage? {
        // 主覆盖窗口已隐藏，直接截取屏幕区域即可
        let cgRect = CGRect(
            x: screenRect.minX,
            y: NSScreen.main!.frame.height - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
        // 排除边框指示器窗口和缩略图窗口
        var excludeWindowIDs: [CGWindowID] = []
        if let borderWin = borderIndicatorWindow {
            excludeWindowIDs.append(CGWindowID(borderWin.windowNumber))
        }
        if let thumbWin = thumbnailWindow {
            excludeWindowIDs.append(CGWindowID(thumbWin.windowNumber))
        }
        
        // 使用 optionOnScreenBelowWindow 排除指示器窗口
        let winID = excludeWindowIDs.first ?? CGWindowID(0)
        let cgImg = CGWindowListCreateImage(cgRect, .optionOnScreenBelowWindow, winID, [])
        if let image = cgImg {
            return NSImage(cgImage: image, size: size)
        }
        return nil
    }
    
    enum LongScreenshotSaveMode {
        case cancel
        case saveToLocalDialog
        case copyToClipboardAndSave
    }

    private func createLongScreenshotToolbar(rect screenRect: NSRect) {
        let toolbar = NSVisualEffectView()
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 16
        toolbar.layer?.masksToBounds = true
        toolbar.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        toolbar.layer?.borderWidth = 0.5
        
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        
        let cancelBtn = makeIconButton(symbol: "xmark", tip: "取消", action: #selector(longScreenshotCancelAction))
        cancelBtn.contentTintColor = .black
        let saveBtn = makeIconButton(symbol: "square.and.arrow.down", tip: "保存至本地", action: #selector(longScreenshotSaveLocalAction))
        saveBtn.contentTintColor = .black
        
        let confirmBtn = makeIconButton(symbol: "checkmark", tip: "完成并复制", action: #selector(longScreenshotConfirmAction))
        confirmBtn.contentTintColor = .black
        
        stack.addArrangedSubview(cancelBtn)
        stack.addArrangedSubview(saveBtn)
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(confirmBtn)
        
        toolbar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            stack.heightAnchor.constraint(equalTo: toolbar.heightAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: toolbar.widthAnchor, constant: -24)
        ])
        
        let targetWidth = stack.fittingSize.width + 24
        let targetHeight: CGFloat = 44
        
        var tbY = screenRect.minY - targetHeight - 12
        if tbY < 10 { tbY = screenRect.maxY + 12 }
        let tbX = screenRect.midX - targetWidth / 2
        
        let winRect = CGRect(x: max(10, min(tbX, (NSScreen.main?.frame.width ?? 1440) - targetWidth - 10)), y: tbY, width: targetWidth, height: targetHeight)
        
        let window = NSWindow(contentRect: winRect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = toolbar
        window.makeKeyAndOrderFront(nil)
        
        self.longScreenshotToolbarWindow = window
    }
    
    @objc private func longScreenshotCancelAction() {
        stopScrollingCapture(saveMode: .cancel)
    }
    
    @objc private func longScreenshotSaveLocalAction() {
        stopScrollingCapture(saveMode: .saveToLocalDialog)
    }
    
    @objc private func longScreenshotConfirmAction() {
        stopScrollingCapture(saveMode: .copyToClipboardAndSave)
    }

    fileprivate func stopScrollingCapture(saveMode: LongScreenshotSaveMode = .copyToClipboardAndSave) {
        guard isScrollingCaptureActive else { return }
        isScrollingCaptureActive = false
        
        // 清理边框指示器窗口
        borderIndicatorWindow?.orderOut(nil)
        borderIndicatorWindow = nil
        
        // 清理工具栏窗口
        longScreenshotToolbarWindow?.orderOut(nil)
        longScreenshotToolbarWindow = nil
        
        // 清理缩略图窗口
        thumbnailWindow?.orderOut(nil)
        thumbnailWindow = nil
        
        self.captureTimer?.invalidate()
        self.captureTimer = nil
        
        if let globalMonitor = globalEventMonitor {
            NSEvent.removeMonitor(globalMonitor)
            globalEventMonitor = nil
        }
        if let localMonitor = localEventMonitor {
            NSEvent.removeMonitor(localMonitor)
            localEventMonitor = nil
        }
        
        if saveMode == .cancel {
            // ESC 取消：丢弃结果
            showToast("已取消长截图")
            Task {
                _ = await self.stitchingManager.stopStitching()
                await MainActor.run {
                    self.parentWindow?.onCancelled?()
                    self.window?.close()
                }
            }
            return
        }
        
        Task {
            if let finalImage = await self.stitchingManager.stopStitching() {
                await MainActor.run {
                    if saveMode == .saveToLocalDialog {
                        self.parentWindow?.onFinished?()
                        self.window?.close()
                        DispatchQueue.main.async {
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.png]
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
                            panel.nameFieldStringValue = "长截图 \(dateFormatter.string(from: Date())).png"
                            
                            if panel.runModal() == .OK, let url = panel.url {
                                if let tiffData = finalImage.tiffRepresentation,
                                   let bitmap = NSBitmapImageRep(data: tiffData),
                                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                                    try? pngData.write(to: url)
                                }
                            }
                        }
                    } else {
                        // 复制到剪贴板
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([finalImage])
                        
                        // 保存到设置目录
                        if let tiffData = finalImage.tiffRepresentation,
                           let bitmap = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmap.representation(using: .png, properties: [:]) {
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
                            let fileName = "长截图 \(dateFormatter.string(from: Date())).png"
                            
                            // 优先保存到用户设置的截图保存目录
                            let saveDirectory = ScreenshotSettings.shared.saveDirectory
                            let directoryURL = URL(fileURLWithPath: saveDirectory)
                            let fileURL = directoryURL.appendingPathComponent(fileName)
                            
                            do {
                                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                                try pngData.write(to: fileURL)
                                self.showToast("长截图已保存！已复制到剪贴板")
                            } catch {
                                // 回退保存到桌面
                                let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                                let fallbackURL = desktopURL.appendingPathComponent(fileName)
                                try? pngData.write(to: fallbackURL)
                                self.showToast("长截图已保存到桌面！已复制到剪贴板")
                            }
                        }
                        
                        // 关闭覆盖层
                        self.parentWindow?.onFinished?()
                        self.window?.close()
                    }
                }
            }
        }
    }
    
    /// 更新实时预览缩略图
    private func updateThumbnail(with image: NSImage) {
        let thumbnailScaleFactor: CGFloat = 0.25
        let thumbnailWidth = max(180, min(image.size.width * thumbnailScaleFactor, 300))
        let thumbnailHeight = max(120, min(image.size.height * thumbnailScaleFactor, 500))
        let thumbnailSize = NSSize(width: thumbnailWidth, height: thumbnailHeight)
        
        // 计算缩略图位置（选区右侧贴近一点的距离）
        let rectInScreen = self.window?.convertToScreen(self.convert(self.selectedRect, to: nil)) ?? self.selectedRect
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(rectInScreen.origin) })?.frame ?? NSScreen.main?.frame ?? .zero
        
        var targetX = rectInScreen.maxX + 16
        if targetX + thumbnailSize.width > screenFrame.maxX {
            targetX = rectInScreen.minX - thumbnailSize.width - 16
            if targetX < screenFrame.minX {
                targetX = screenFrame.maxX - thumbnailSize.width - 16
            }
        }
        
        let thumbnailOrigin = NSPoint(
            x: targetX,
            y: max(screenFrame.minY + 20, rectInScreen.minY)
        )
        
        if let existingWindow = thumbnailWindow {
            // 更新已有窗口
            if let contentView = existingWindow.contentView as? LongScreenshotThumbnailView {
                contentView.updateImage(image, size: thumbnailSize)
                existingWindow.setFrame(NSRect(origin: thumbnailOrigin, size: thumbnailSize), display: true)
            }
        } else {
            // 创建新窗口
            let thumbnailView = LongScreenshotThumbnailView(image: image, size: thumbnailSize)
            let window = NSWindow(
                contentRect: NSRect(origin: thumbnailOrigin, size: thumbnailSize),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .statusBar
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = thumbnailView
            window.ignoresMouseEvents = true
            window.makeKeyAndOrderFront(nil)
            self.thumbnailWindow = window
        }
    }

    fileprivate func updateButtonStates() {
        for (type, btn) in toolButtons {
            let isSelected = (canvas?.currentTool == type)
            btn.state = isSelected ? .on : .off
            // 添加阴影选中样式：选中时带有半透明白色背景，未选中时背景透明
            btn.layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
        }
    }
    
    @objc private func colorWellChanged(_ sender: NSColorWell) {
        canvas?.currentColor = sender.color
    }

    @objc private func paletteButtonClicked() {
        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelChanged(_:)))
        colorPanel.color = canvas?.currentColor ?? .systemBlue
        // 确保颜色面板的层级高于全屏遮罩的层级 (self.window?.level 通常是 screenSaver + 1)
        if let windowLevel = self.window?.level {
            colorPanel.level = NSWindow.Level(windowLevel.rawValue + 1)
        } else {
            colorPanel.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
        }
        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        canvas?.currentColor = sender.color
    }

    private func getFinalImage() -> NSImage? {
        if let exported = canvas?.exportAsImage() {
            return exported
        }
        let cropRect = self.selectedRect
        if let cgImg = self.backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: NSRect(x: cropRect.minX, y: self.backgroundImage.size.height - cropRect.maxY, width: cropRect.width, height: cropRect.height)) {
            return NSImage(cgImage: cgImg, size: cropRect.size)
        }
        return nil
    }

    @objc private func pinAction() {
        if let image = getFinalImage() {
            PinWindowManager.shared.pin(image: image, at: nil)
        }
        parentWindow?.onFinished?()
        self.window?.close()
    }

    @objc private func saveToLocalAction() {
        guard let image = getFinalImage() else { return }
        
        // 先关闭当前的覆盖层，否则覆盖层层级（screenSaver+1）过高会把保存对话框遮挡在后面，导致看似无响应
        parentWindow?.onFinished?()
        self.window?.close()
        
        // 延时到下一个事件循环展示保存对话框，确保覆盖层已经完全退出
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "Screenshot_\(Int(Date().timeIntervalSince1970)).png"
            
            if panel.runModal() == .OK, let url = panel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                }
            }
        }
    }

    @objc private func doneAction() {
        if let image = getFinalImage() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
        parentWindow?.onFinished?()
        self.window?.close()
    }

    @objc private func cancelAction() {
        parentWindow?.onCancelled?()
        self.window?.close()
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        // Iterate through toolButtons to find which type it is
        for (type, btn) in toolButtons {
            if btn == sender {
                selectTool(type)
                return
            }
        }
    }
    
    private func selectTool(_ tool: AnnotationToolType) {
        if canvas?.currentTool == tool {
            // 如果再次点击已经选中的工具，则取消选中（恢复到默认拖动状态）
            canvas?.currentTool = .drag
        } else {
            canvas?.currentTool = tool
        }
        updateButtonStates()
    }
    
    @objc private func undoAction() {
        canvas?.undo()
    }
    
    @objc private func redoAction() {
        canvas?.redo()
    }
    
    @objc private func copyAction() {
        doneAction()
    }

    // MARK: AnnotationCanvasDelegate
    func canvasDidChange(_ canvas: AnnotationCanvas) {
        updateButtonStates()
    }

    // MARK: - 键盘派发
    func handleKeyDown(event: NSEvent) {
        guard isAnnotating else { return }
        
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { redoAction() } else { undoAction() }
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copyAction(); return
        }
        if event.keyCode == 36 { // Enter 键
            doneAction(); return
        }

        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return }
        if let char = event.charactersIgnoringModifiers?.uppercased(),
           let tool = AnnotationToolType.allCases.first(where: { $0.shortcutKey == char }) {
            selectTool(tool)
        }
    }

    // MARK: - 寻找鼠标下的窗口
    private func windowAtPoint(_ viewPoint: NSPoint) -> SCWindow? {
        let screenHeight = bounds.height
        let screenPoint = CGPoint(x: viewPoint.x, y: screenHeight - viewPoint.y)
        return availableWindows.first { window in
            let frame = window.frame
            return frame.contains(screenPoint)
        }
    }
}

class ColorPresetButton: NSButton {
    let color: NSColor
    weak var parentView: CaptureOverlayView?
    
    init(color: NSColor, parentView: CaptureOverlayView) {
        self.color = color
        self.parentView = parentView
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        self.wantsLayer = true
        self.isBordered = false
        self.title = ""
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: 4, dy: 4), transform: nil)
        shapeLayer.fillColor = color.cgColor
        shapeLayer.strokeColor = NSColor.white.cgColor
        shapeLayer.lineWidth = 1.5
        self.layer?.addSublayer(shapeLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        parentView?.canvas?.currentColor = color
        parentView?.updateButtonStates()
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 24, height: 24)
    }
}

class StitchingManager {
    // MARK: - Properties
    private var runningStitchedImage: NSImage?
    private var previousImage: NSImage?
    private let stitchingQueue = DispatchQueue(label: "com.scrollsnap.stitching", qos: .userInitiated)
    
    /// 获取当前拼接结果（线程安全）
    var currentStitchedImage: NSImage? {
        return stitchingQueue.sync { runningStitchedImage }
    }
    
    // MARK: - Public API
    
    func startStitching(with initialImage: NSImage) {
        runningStitchedImage = initialImage
        previousImage = initialImage
    }
    
    func addImage(_ image: NSImage) {
        stitchingQueue.async { [weak self] in
            guard let self = self else { return }
            guard let baseStitchedImage = self.runningStitchedImage,
                  let prevImage = self.previousImage else {
                self.runningStitchedImage = image
                self.previousImage = image
                return
            }
            guard let offsetInPoints = self.calculateOffset(from: image, to: prevImage) else {
                self.previousImage = image
                return
            }

            if offsetInPoints > 0 {
                guard let newStitchedImage = self.composite(baseImage: baseStitchedImage, newImage: image, offset: offsetInPoints) else {
                    return
                }
                self.runningStitchedImage = newStitchedImage
                self.previousImage = image

            } else if offsetInPoints < 0 {
                let cropAmount = abs(offsetInPoints)
                guard cropAmount <= baseStitchedImage.size.height,
                      let croppedImage = self.cropBottomRegion(of: baseStitchedImage, byAmount: cropAmount) else {
                    self.previousImage = image
                    return
                }
                self.runningStitchedImage = croppedImage
                self.previousImage = image

            } else {
                self.previousImage = image
            }
        }
    }
    
    func stopStitching() async -> NSImage? {
        return await withCheckedContinuation { continuation in
            stitchingQueue.async { [weak self] in
                let finalImage = self?.runningStitchedImage
                self?.runningStitchedImage = nil
                self?.previousImage = nil
                continuation.resume(returning: finalImage)
            }
        }
    }
    
    // MARK: - Private Stitching Methods
    
    private func calculateOffset(from currentImage: NSImage, to previousImage: NSImage) -> CGFloat? {
        guard let currentCG = currentImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let previousCG = previousImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        guard let verticalOffsetInPixels = findVerticalOffset(from: currentCG, to: previousCG) else {
            return nil
        }

        guard currentImage.size.height > 0 else { return nil }
        let scale = CGFloat(currentCG.height) / currentImage.size.height
        return verticalOffsetInPixels / (scale > 0 ? scale : 1.0)
    }
    
    private func findVerticalOffset(from image1: CGImage, to image2: CGImage) -> CGFloat? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: image2)
        let handler = VNImageRequestHandler(cgImage: image1, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }
        return observation.alignmentTransform.ty
    }
    
    private func composite(baseImage: NSImage, newImage: NSImage, offset: CGFloat) -> NSImage? {
        let baseSize = baseImage.size
        let newSize = newImage.size
        
        let totalHeight = baseSize.height + offset
        let outputSize = NSSize(width: baseSize.width, height: totalHeight)
        
        let outputImage = NSImage(size: outputSize)
        outputImage.lockFocus()
        
        let baseRect = CGRect(x: 0, y: totalHeight - baseSize.height, width: baseSize.width, height: baseSize.height)
        baseImage.draw(in: baseRect)
        
        let newRect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        newImage.draw(in: newRect)
        
        outputImage.unlockFocus()

        return outputImage
    }

    private func cropBottomRegion(of image: NSImage, byAmount amount: CGFloat) -> NSImage? {
        let originalSize = image.size
        guard amount > 0, amount < originalSize.height else { return image }

        let newHeight = originalSize.height - amount
        let newSize = NSSize(width: originalSize.width, height: newHeight)

        let croppedImage = NSImage(size: newSize)
        croppedImage.lockFocus()

        let sourceRect = NSRect(x: 0, y: amount, width: originalSize.width, height: newHeight)
        let destRect = NSRect(origin: .zero, size: newSize)

        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)

        croppedImage.unlockFocus()
        return croppedImage
    }
}

// MARK: - 长截图实时预览缩略图
class LongScreenshotThumbnailView: NSView {
    private var image: NSImage
    private var imageView: NSImageView!
    private var statusLabel: NSTextField!
    
    init(image: NSImage, size: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))
        
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 2
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        
        // 图片视图
        imageView = NSImageView(frame: bounds.insetBy(dx: 4, dy: 4))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image
        addSubview(imageView)
        
        // 状态标签
        statusLabel = NSTextField(labelWithString: "长截图捕获中...")
        statusLabel.textColor = .white
        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.wantsLayer = true
        statusLabel.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
        statusLabel.layer?.cornerRadius = 4
        statusLabel.frame = NSRect(x: 4, y: bounds.height - 22, width: bounds.width - 8, height: 18)
        addSubview(statusLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
    
    func updateImage(_ newImage: NSImage, size: NSSize) {
        self.image = newImage
        imageView.image = newImage
        imageView.frame = bounds.insetBy(dx: 4, dy: 4)
        statusLabel.frame = NSRect(x: 4, y: bounds.height - 22, width: bounds.width - 8, height: 18)
    }
}

// MARK: - 长截图红色边框指示器
class LongScreenshotBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let borderRect = bounds
        
        // 绘制蓝色边框
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(3)
        context.stroke(borderRect)
        
        // 绘制四角标记
        let cornerLength: CGFloat = 16
        let cornerWidth: CGFloat = 4
        context.setFillColor(NSColor.systemBlue.cgColor)
        
        // 左上角
        context.fill(CGRect(x: 0, y: borderRect.height - cornerWidth, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: 0, y: borderRect.height - cornerLength, width: cornerWidth, height: cornerLength))
        
        // 右上角
        context.fill(CGRect(x: borderRect.width - cornerLength, y: borderRect.height - cornerWidth, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: borderRect.width - cornerWidth, y: borderRect.height - cornerLength, width: cornerWidth, height: cornerLength))
        
        // 左下角
        context.fill(CGRect(x: 0, y: 0, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: 0, y: 0, width: cornerWidth, height: cornerLength))
        
        // 右下角
        context.fill(CGRect(x: borderRect.width - cornerLength, y: 0, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: borderRect.width - cornerWidth, y: 0, width: cornerWidth, height: cornerLength))
        
        // 绘制状态提示条
        let statusText = "正在捕获长截图... 按 Enter 保存 | ESC 取消"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = statusText.size(withAttributes: attrs)
        let padding: CGFloat = 8
        let statusBgRect = CGRect(
            x: (borderRect.width - textSize.width - padding * 2) / 2,
            y: borderRect.height + 4,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )
        
        // 状态条背景
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
        let bgPath = CGMutablePath()
        bgPath.addRoundedRect(in: statusBgRect, cornerWidth: 4, cornerHeight: 4)
        context.addPath(bgPath)
        context.fillPath()
        
        // 状态条文字
        let textRect = CGRect(
            x: statusBgRect.origin.x + padding,
            y: statusBgRect.origin.y + padding / 2,
            width: textSize.width,
            height: textSize.height
        )
        (statusText as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
