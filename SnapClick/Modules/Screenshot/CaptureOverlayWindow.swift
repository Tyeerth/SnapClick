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
    case combined         // 智能模式：悬停高亮窗口，拖拽选区，点击捕获窗口
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
    /// - Parameters:
    ///   - backgroundImage: 该屏幕的全屏截图（应与 screen 对应）
    ///   - windows: 可选窗口列表（用于窗口模式高亮）
    ///   - screen: 覆盖层应显示的目标屏幕；nil 时退化为主屏
    init(backgroundImage: NSImage,
         windows: [SCWindow] = [],
         screen: NSScreen? = nil) {

        self.backgroundImage  = backgroundImage
        self.availableWindows = windows

        // 确定目标屏幕的帧（AppKit 全局坐标）
        let targetScreen = screen ?? NSScreen.main
        let screenFrame  = targetScreen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // 初始化覆盖层视图（相对于窗口内部，origin 始终 .zero）
        self.overlayView = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            backgroundImage: backgroundImage,
            windows: windows
        )

        // 初始化全屏透明无边框窗口，contentRect 使用目标屏幕的 AppKit 帧
        super.init(
            contentRect: screenFrame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        // 窗口属性设置
        self.level                   = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        self.backgroundColor         = .clear
        self.isOpaque                = false
        self.hasShadow               = false
        self.ignoresMouseEvents      = false
        self.collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView             = overlayView
        self.acceptsMouseMovedEvents = true

        // 将窗口色彩空间设为目标屏幕原生色彩空间（通常是 Display P3）。
        // NSWindow 默认为 sRGB，而 SCScreenshotManager 截取的背景图带屏幕原生 Profile，
        // 不对齐时 NSImage.draw 会产生颜色/色温偏移，hover 与初始状态颜色与选中后不一致。
        if let screenColorSpace = targetScreen?.colorSpace {
            self.colorSpace = screenColorSpace
        }

        // 绑定回调
        overlayView.onCancelled      = { [weak self] in self?.onCancelled?() }
        overlayView.onWindowSelected = { [weak self] win in self?.onWindowSelected?(win) }
        
        // 挂载 window 引用到 view，以便 Done 时可以关闭 window
        overlayView.parentWindow = self

        // 智能截图 / 选区截图：使用自定义大十字光标 + 提示
        // 隐藏系统默认光标，改为在 view 上自绘
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch self.overlayView.mode {
            case .combined, .areaSelection:
                NSCursor.hide()
            case .windowSelection:
                NSCursor.arrow.set()
            }
        }
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

    /// 最后一次拖拽完成的选区（供录制引擎读取）
    var lastSelectedRect: CGRect? {
        let r = overlayView.selectedRect
        return (r.width > 10 && r.height > 10) ? r : nil
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
    var selectedRect:  NSRect  = .zero

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

    // 鼠标移动节流（避免在 ProMotion 120Hz 下每秒触发上百次 needsDisplay）
    private var lastHoverEvalTime: CFTimeInterval = 0
    private let hoverEvalMinInterval: CFTimeInterval = 1.0 / 60.0

    // MARK: ── 就地标注模式属性 ──────────────────────────────────────────
    private var isAnnotating = false
    fileprivate var canvas: AnnotationCanvas?
    private var editorToolbar: NSVisualEffectView?
    
    // 智能模式：窗口已选中等待确认（点击窗口后进入此状态，可调整选区，按 Enter 或双击确认）
    private var isWindowSelectedPending = false
    private var pendingSelectedWindow: SCWindow?
    
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

        // 取消"全部预热"，改为按需懒抓（hover 时拉取）+ NSCache LRU 限制内存峰值
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

        if (mode == .areaSelection || mode == .combined) && (isDragging || isAnnotating || isScrollingCaptureActive || isWindowSelectedPending) {
            // 区域选择或正在就地标注：只在选区外侧暗化
            let outerPath = CGMutablePath()
            outerPath.addRect(bounds)
            
            let rectToClear = isAnnotating || isWindowSelectedPending ? selectedRect : normalizedSelectedRect()
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

            if isWindowSelectedPending, let win = pendingSelectedWindow {
                drawWindowTooltip(window: win, rect: selectedRect, context: context)
                drawWindowConfirmHint(context: context)
            }
        } else if mode == .windowSelection || mode == .combined {
            context.fill(bounds)
            if let win = hoveredWindow {
                drawWindowHighlight(window: win, context: context)
                drawWindowTooltip(window: win, rect: winToViewRect(win), context: context)
            }
        } else {
            // 未开始拖拽且未标注：整体半透明暗化
            context.fill(bounds)
        }

        // 3. 拖拽选择阶段（放大镜功能已按需求移除）

        // 4. 绘制顶部操作提示（未进入标注且未在长截图捕获时）
        if !isAnnotating && !isScrollingCaptureActive && !isWindowSelectedPending {
            drawHint(context: context)
        }

        // 5. 自定义十字光标（覆盖在所有内容之上，确保可见）
        if !isAnnotating && (mode == .areaSelection || mode == .combined) {
            drawCustomCursor(context: context)
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
        // 多屏修复：使用 overlay 所在屏的 backingScaleFactor，而不是主屏
        let scale  = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
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
        let viewRect = winToViewRect(window)

        // 直接从全屏背景图裁剪窗口区域显示：backgroundImage 在覆盖层打开时已包含所有窗口内容，
        // 无需二次截图，色彩空间与背景图完全一致，也不存在任何延迟。
        // CGImage 像素坐标系：原点左上、Y 向下；需从 AppKit 视图坐标（左下、Y 向上）翻转换算。
        let overlayScale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        if let bgCG = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let cropRect = CGRect(
                x:      viewRect.origin.x * overlayScale,
                y:      (bounds.height - viewRect.origin.y - viewRect.height) * overlayScale,
                width:  viewRect.width  * overlayScale,
                height: viewRect.height * overlayScale
            )
            if let cropped = bgCG.cropping(to: cropRect) {
                // 修复双层阴影：
                // backgroundImage 中窗口的阴影位于 viewRect 之外（macOS 窗口阴影在 frame 外侧），
                // 如果不清除直接叠加 35% 暗化遮罩，会形成"暗化阴影 + 暗化背景"两层视觉。
                // 这里把 viewRect 扩大阴影范围后 clear，再 fill 一层与全屏一致的 35% 黑色，
                // 让窗口阴影区域与全屏暗化融为一体，消除双层。
                let shadowRect = viewRect.insetBy(dx: -50, dy: -50)
                context.clear(shadowRect)
                context.setFillColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.35).cgColor)
                context.fill(shadowRect)

                context.interpolationQuality = .high
                context.draw(cropped, in: viewRect)
            }
        } else {
            backgroundImage.draw(
                in:   viewRect,
                from: CGRect(
                    x:      viewRect.origin.x,
                    y:      bounds.height - viewRect.origin.y - viewRect.height,
                    width:  viewRect.width,
                    height: viewRect.height
                ),
                operation: .sourceOver,
                fraction:  1.0
            )
        }

        context.setStrokeColor(NSColor(red: 0.12, green: 0.56, blue: 1.0, alpha: 1.0).cgColor)
        context.setLineWidth(3)
        context.stroke(viewRect)
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

    // MARK: - 绘制自定义十字光标（跟随鼠标）
    private func drawCustomCursor(context: CGContext) {
        let center = magnifierCenter

        // 1. 十字大小（两条完整直线，跨过中心）
        let armLength: CGFloat = 18
        let strokeWidth: CGFloat = 1.2  // 更细的线宽

        // 自定义蓝 #458DF7 = rgb(69, 141, 247)
        let cursorBlue = NSColor(red: 69.0/255.0, green: 141.0/255.0, blue: 247.0/255.0, alpha: 1.0)

        // 3. 绘制十字（蓝色主线 + 黑色描边，确保在任意背景下都可见）
        context.saveGState()
        context.setLineCap(.round)

        // 黑色描边（更粗，作为底色）
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(strokeWidth + 1.0)

        // 水平线（完整一条）
        context.move(to: CGPoint(x: center.x - armLength, y: center.y))
        context.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
        context.strokePath()

        // 垂直线（完整一条）
        context.move(to: CGPoint(x: center.x, y: center.y - armLength))
        context.addLine(to: CGPoint(x: center.x, y: center.y + armLength))
        context.strokePath()

        // 蓝色主线（覆盖在黑色描边上）
        context.setStrokeColor(cursorBlue.cgColor)
        context.setLineWidth(strokeWidth)

        // 水平线
        context.move(to: CGPoint(x: center.x - armLength, y: center.y))
        context.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
        context.strokePath()

        // 垂直线
        context.move(to: CGPoint(x: center.x, y: center.y - armLength))
        context.addLine(to: CGPoint(x: center.x, y: center.y + armLength))
        context.strokePath()

        context.restoreGState()
    }

    // MARK: - 绘制操作提示
    private func drawHint(context: CGContext) {
        let attrStr: NSAttributedString
        let boxWidth: CGFloat

        if isLongScreenshotMode {
            attrStr = makeHint(
                primary: "拖动鼠标框选区域".localized,
                secondary: "ESC 取消".localized
            )
            boxWidth = 300
        } else if mode == .combined {
            // 智能截图：用户已悬停在窗口上时，突出"点击"动作；默认显示双操作
            if hoveredWindow != nil && !isDragging && !isAnnotating && !isWindowSelectedPending {
                attrStr = makeHint(
                    primary: "点击截取该窗口".localized,
                    secondary: "或拖动选择截图区域".localized,
                    accent: true
                )
                boxWidth = 320
            } else {
                attrStr = makeCombinedHint()
                boxWidth = 420
            }
        } else if mode == .areaSelection {
            attrStr = makeHint(
                primary: "拖动鼠标框选区域".localized,
                secondary: "ESC 取消".localized
            )
            boxWidth = 300
        } else {
            attrStr = makeHint(
                primary: "点击选择窗口".localized,
                secondary: "ESC 取消".localized
            )
            boxWidth = 260
        }

        let textSize = attrStr.size()
        let boxRect = CGRect(
            x:      (bounds.width - boxWidth) / 2,
            y:      bounds.height - 72,
            width:  boxWidth,
            height: textSize.height + 18
        )

        // 圆角矩形背景（半透明黑 + 1px 极淡白边）
        let bgPath = CGPath(roundedRect: boxRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.setFillColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.55).cgColor)
        context.addPath(bgPath)
        context.fillPath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        context.setLineWidth(0.5)
        context.addPath(bgPath)
        context.strokePath()

        attrStr.draw(in: boxRect.insetBy(dx: 18, dy: 9))
    }

    /// 标准单行提示（主操作 + 次要操作）
    private func makeHint(primary: String, secondary: String, accent: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: primary,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: accent ? NSColor.systemBlue : NSColor.white
            ]
        ))
        result.append(NSAttributedString(
            string: "   |   ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white.withAlphaComponent(0.25)
            ]
        ))
        result.append(NSAttributedString(
            string: secondary,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55)
            ]
        ))
        return result
    }

    /// 智能截图双操作提示：「模式徽章 + 拖动 + 点击 + ESC」
    private func makeCombinedHint() -> NSAttributedString {
        let result = NSMutableAttributedString()

        // 1. 模式徽章（蓝色圆点 + 文字）
        result.append(NSAttributedString(
            string: "● 智能截图".localized,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.systemBlue
            ]
        ))

        // 分隔
        result.append(separator())

        // 2. 拖动鼠标框选
        result.append(NSAttributedString(
            string: "拖动鼠标框选".localized,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        ))

        // 中点分隔
        result.append(NSAttributedString(
            string: "  ·  ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white.withAlphaComponent(0.35)
            ]
        ))

        // 3. 点击截取窗口
        result.append(NSAttributedString(
            string: "点击截取窗口".localized,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        ))

        // 分隔
        result.append(separator())

        // 4. ESC 取消
        result.append(NSAttributedString(
            string: "ESC 取消".localized,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55)
            ]
        ))

        return result
    }

    private func separator() -> NSAttributedString {
        NSAttributedString(
            string: "   |   ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white.withAlphaComponent(0.20)
            ]
        )
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

        // 双击：所有模式下统一表示「立即截取当前区域并复制到剪贴板」
        if event.clickCount >= 2 {
            handleDoubleClickQuickCopy(at: loc)
            return
        }

        if isAnnotating && canvas?.currentTool == .drag {
            if let handle = getHandleAt(point: loc) {
                activeDragHandle = handle
                dragStartRect = selectedRect
                startPoint = loc
                return
            }
        }
        
        guard !isAnnotating else { return }

        if isWindowSelectedPending {
            let confirmedWindow = pendingSelectedWindow
            isWindowSelectedPending = false
            pendingSelectedWindow = nil
            if let win = confirmedWindow {
                enterInPlaceAnnotationMode(forWindow: win)
            } else {
                enterInPlaceAnnotationMode()
            }
            return
        }

        switch mode {
        case .areaSelection:
            startPoint   = loc
            currentPoint = loc
            isDragging   = true
            needsDisplay = true

        case .combined:
            startPoint   = loc
            currentPoint = loc
            isDragging   = true
            needsDisplay = true

        case .windowSelection:
            if let win = windowAtPoint(loc) {
                selectedRect = winToViewRect(win).intersection(bounds)
                enterInPlaceAnnotationMode(forWindow: win)
            } else {
                // 鼠标点在空白处（未命中任何窗口），不直接取消，
                // 让用户有机会移动鼠标重新悬停到目标窗口上再点击
                needsDisplay = true
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // 选区 / 智能模式下拖动时：系统光标已被隐藏，自定义十字由 drawCustomCursor 绘制
        // 只需保证 needsDisplay 触发（已在 mouseMoved 末尾）
        if !isAnnotating && (mode == .areaSelection || mode == .combined) {
            // 不需要设置系统光标
        }

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
        
        guard (mode == .areaSelection || mode == .combined) && !isAnnotating else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        magnifierCenter = currentPoint
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isAnnotating && canvas?.currentTool == .drag && activeDragHandle != nil {
            activeDragHandle = nil
            return
        }
        
        guard (mode == .areaSelection || mode == .combined) && isDragging && !isAnnotating else { return }
        isDragging = false
        let rect = normalizedSelectedRect()

        // 智能模式：拖拽距离太小→视为单击，直接捕获悬停窗口（对齐 Snipaste/macOS 单击即截行为）
        if mode == .combined && rect.width < 10 && rect.height < 10 {
            if let win = hoveredWindow {
                selectedRect = winToViewRect(win).intersection(bounds)
                if isLongScreenshotMode {
                    enterScrollingCaptureMode()
                } else {
                    enterInPlaceAnnotationMode(forWindow: win)
                }
            } else {
                // 未悬停在任何窗口上，什么也不做，展示空白点击提示
                needsDisplay = true
            }
            return
        }

        if rect.width < 10 || rect.height < 10 {
            needsDisplay = true
            return
        }

        selectedRect = rect
        
        if isLongScreenshotMode {
            enterScrollingCaptureMode()
        } else {
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

        if isWindowSelectedPending {
            if selectedRect.contains(loc) {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }

        // 节流：限制 hover 评估与重绘频率到 60Hz，避免 120Hz ProMotion 下大量重绘
        let now = CACurrentMediaTime()
        if now - lastHoverEvalTime < hoverEvalMinInterval { return }
        lastHoverEvalTime = now

        if mode == .combined {
            // 智能截图：自定义十字光标已在 drawCustomCursor 中绘制
            // 仍然跟踪 hoveredWindow（用于决定文字提示和点击行为）
            let newHover = windowAtPoint(loc)
            if newHover?.windowID != hoveredWindow?.windowID {
                hoveredWindow = newHover
            }
        } else if mode == .windowSelection {
            // 窗口截图：保留系统手型光标
            let newHover = windowAtPoint(loc)
            if newHover?.windowID != hoveredWindow?.windowID {
                hoveredWindow = newHover
            }
            if hoveredWindow != nil {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        needsDisplay = true
    }

    // MARK: - 🌟 核心：直接全屏标注
    func enterFullScreenAnnotationDirectly() {
        selectedRect = bounds
        enterInPlaceAnnotationMode()
    }

    // MARK: - 🌟 核心：进入就地标注模式（窗口模式）
    /// 选中某个具体窗口后，先用 ScreenCaptureKit 单独捕获该窗口图像，
    /// 用窗口图像替换裁剪出的全屏背景作为画布底图，从而避免把上层其它程序的内容也截进来
    private func enterInPlaceAnnotationMode(forWindow win: SCWindow) {
        // 先以"窗口在屏的矩形"为占位，进入标注模式，画布初始底图依然来自 backgroundImage 裁剪
        // 这样 UI 不会被截图等待阻塞
        enterInPlaceAnnotationMode()

        // 异步：用 ScreenCaptureKit 仅捕获该窗口的真实像素，覆盖到画布底图上
        let canvasRef = self.canvas
        Task { @MainActor in
            do {
                let img = try await ScreenCaptureEngine.shared.captureSingleWindow(win)
                // 防御：在标注期间用户可能已取消
                guard let canvas = canvasRef, canvas === self.canvas else { return }
                canvas.baseImage = img
                canvas.needsDisplay = true
            } catch {
                // 失败时保留裁剪后的占位底图，不打断用户操作
            }
        }
    }

    // MARK: - 🌟 核心：进入就地标注模式
    private func enterInPlaceAnnotationMode() {
        isAnnotating = true
        needsDisplay = true // 强制重绘，高亮选区，外侧暗化
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
        var thumbnailTick = 0
        self.captureTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.isScrollingCaptureActive, !self.isTimerCaptureInFlight else { return }
            self.isTimerCaptureInFlight = true
            thumbnailTick &+= 1
            let shouldRefreshThumbnail = (thumbnailTick % 2 == 0)

            captureQueue.async {
                if let image = self.captureScreenshotForStitching(rect: rectInScreen, size: captureSize) {
                    self.stitchingManager.addImage(image)

                    // 限频更新缩略图预览（每 0.5s 一次），减轻主线程压力
                    if shouldRefreshThumbnail,
                       let stitched = self.stitchingManager.currentStitchedImage {
                        DispatchQueue.main.async {
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
    
    /// 创建全屏指示器与遮罩窗口（ignoresMouseEvents 确保不影响下层窗口的鼠标事件）
    private func createBorderIndicator(rect screenRect: NSRect) {
        let fullScreenRect = self.window?.frame ?? NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let borderView = LongScreenshotBorderView(frame: NSRect(origin: .zero, size: fullScreenRect.size), selectedRect: self.selectedRect)
        
        let window = NSWindow(
            contentRect: fullScreenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true  // 关键：不拦截鼠标事件，允许事件穿透到下层应用
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = borderView
        window.makeKeyAndOrderFront(nil)
        self.borderIndicatorWindow = window
    }
    
    /// 截取指定区域的截图
    private func captureScreenshotForStitching(rect screenRect: NSRect, size: NSSize) -> NSImage? {
        // 主覆盖窗口已隐藏，直接截取屏幕区域即可
        // 多屏修复：使用全局坐标系的最大 maxY 进行 Y 翻转，而不是单屏高度
        let flipH = NSScreen.screens.map { $0.frame.maxY }.max()
            ?? NSScreen.main?.frame.height
            ?? screenRect.maxY
        let cgRect = CGRect(
            x: screenRect.minX,
            y: flipH - screenRect.maxY,
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
                            dateFormatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
                            panel.nameFieldStringValue = "SnapClick_长截图_\(dateFormatter.string(from: Date())).png"
                            
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
                            dateFormatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
                            let fileName = "SnapClick_长截图_\(dateFormatter.string(from: Date())).png"
                            
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
        
        // 更新颜色块的选中高亮状态
        let currentSelColor = canvas?.currentColor ?? .systemRed
        for btn in colorPresetButtons {
            btn.updateHighlightState(selectedColor: currentSelColor)
        }
    }
    
    @objc private func colorWellChanged(_ sender: NSColorWell) {
        canvas?.currentColor = sender.color
        updateButtonStates()
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
        updateButtonStates()
    }

    // MARK: - 双击快速截图复制
    /// 所有截图模式下双击：截取当前应被截取的区域 → 复制到剪贴板 → 关闭覆盖层
    /// - 就地标注模式：复制带标注的最终图（等价于 doneAction）
    /// - 窗口选择 / 智能模式 hover 中：复制悬停窗口
    /// - 区域选择 / pending 选区：复制当前选区；都没有则复制全屏
    private func handleDoubleClickQuickCopy(at loc: NSPoint) {
        // 1) 已经在标注模式：直接走 done 逻辑（包含画布上的标注）
        if isAnnotating {
            doneAction()
            return
        }

        // 2) 长截图捕获中不响应双击
        if isScrollingCaptureActive {
            return
        }

        var imageToCopy: NSImage?

        // 3) 窗口模式：优先以悬停或 pending 窗口为目标
        let targetWindow: SCWindow? = {
            if isWindowSelectedPending { return pendingSelectedWindow }
            if mode == .windowSelection || mode == .combined {
                return hoveredWindow ?? windowAtPoint(loc)
            }
            return nil
        }()

        if let win = targetWindow {
            // 从背景图裁剪窗口区域：backgroundImage 已包含截图时刻所有窗口内容
            let winRect = winToViewRect(win).intersection(bounds)
            imageToCopy = cropFromBackgroundImage(viewRect: winRect)
        } else if selectedRect.width > 10 && selectedRect.height > 10 {
            // 4) 区域选择已经有选区：复制选区
            imageToCopy = cropFromBackgroundImage(viewRect: selectedRect)
        } else {
            // 5) 没有任何选区：复制全屏背景
            imageToCopy = backgroundImage
        }

        if let img = imageToCopy {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([img])
        }

        // 关闭覆盖层
        parentWindow?.onFinished?()
        self.window?.close()
    }

    /// 从全屏背景图按 view 坐标系矩形裁剪，返回点尺寸的 NSImage
    private func cropFromBackgroundImage(viewRect: NSRect) -> NSImage? {
        guard viewRect.width > 0, viewRect.height > 0,
              let bgCG = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        // CGImage 像素坐标系：左上原点、Y 向下；view 是左下原点、Y 向上 → 翻转
        let cropRect = CGRect(
            x:      viewRect.origin.x * scale,
            y:      (bounds.height - viewRect.origin.y - viewRect.height) * scale,
            width:  viewRect.width  * scale,
            height: viewRect.height * scale
        )
        guard let cropped = bgCG.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cropped, size: viewRect.size)
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
            // 计算当前选区在屏幕上的精确坐标与大小，实现就地贴图
            let rectInScreen = self.window?.convertToScreen(self.convert(self.selectedRect, to: nil)) ?? self.selectedRect
            PinWindowManager.shared.pin(image: image, at: rectInScreen)
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
        if isWindowSelectedPending && event.keyCode == 36 {
            isWindowSelectedPending = false
            pendingSelectedWindow = nil
            enterInPlaceAnnotationMode()
            return
        }
        
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

    // MARK: - 坐标系转换辅助

    /// CG 全局坐标系与 AppKit 坐标系之间的翻转基准高度。
    ///
    /// CG 全局坐标系：原点在主屏左上角，Y 轴向下为正。
    /// AppKit 全局屏幕坐标系：原点在主屏左下角，Y 轴向上为正。
    ///
    /// 转换公式：
    ///   cgY      = flipHeight - appKitY
    ///   appKitY  = flipHeight - cgY
    ///
    /// 正确的 flipHeight 是「所有屏幕中 AppKit frame.maxY 的最大值」，
    /// 这等价于主屏的高度（在 AppKit 体系中主屏 minY == 0，maxY == height）。
    /// 注意：不能直接用 NSScreen.main?.frame.height，因为在多屏幕且主屏非最大时
    /// 可能不等于所有屏幕的最大 maxY；也不能用 backingScaleFactor 来缩放，
    /// 因为 SCWindow.frame 使用的是逻辑点，与 AppKit 的 NSRect 单位相同。
    private var cgCoordFlipHeight: CGFloat {
        // 取所有已连接屏幕中 maxY 最大值，即全局坐标系中最高点
        return NSScreen.screens.map { $0.frame.maxY }.max() ?? NSScreen.main?.frame.height ?? 900
    }

    // MARK: - 寻找鼠标下的窗口
    private func windowAtPoint(_ viewPoint: NSPoint) -> SCWindow? {
        // viewPoint：overlayView 坐标系（AppKit，以 overlayView 左下角为原点）
        //
        // 转换路径：
        //   overlayView 坐标  ->（convert to nil）->  overlayWindow 内坐标
        //   overlayWindow 内坐标 ->（convertToScreen）->  AppKit 全局屏幕坐标
        //   AppKit 全局屏幕坐标 ->（Y 轴翻转）->  CG 全局坐标
        //   CG 全局坐标 -> 与 SCWindow.frame 做命中测试

        guard let win = self.window else {
            // fallback：没有父 window 时，直接用 view 坐标做粗略估算
            let cgPt = CGPoint(x: viewPoint.x, y: cgCoordFlipHeight - viewPoint.y)
            return availableWindows.first { $0.frame.contains(cgPt) }
        }

        // Step 1: overlayView -> overlayWindow
        let pointInWindow = self.convert(viewPoint, to: nil)
        // Step 2: overlayWindow -> AppKit 全局屏幕坐标
        let pointInScreen = win.convertToScreen(NSRect(origin: pointInWindow, size: .zero)).origin
        // Step 3: AppKit 全局坐标 -> CG 全局坐标（Y 轴翻转）
        let cgPoint = CGPoint(x: pointInScreen.x, y: cgCoordFlipHeight - pointInScreen.y)

        // availableWindows 已按真实 Z 序从上到下排好，命中第一个即为最上层
        for window in availableWindows {
            if window.frame.contains(cgPoint) {
                return window
            }
        }
        return nil
    }

    private func winToViewRect(_ win: SCWindow) -> CGRect {
        // win.frame：CG 全局坐标系（主屏左上角为原点，Y 向下为正）
        //
        // 转换路径（与 windowAtPoint 完全逆向）：
        //   CG 全局坐标 ->（Y 轴翻转）->  AppKit 全局屏幕坐标
        //   AppKit 全局屏幕坐标 ->（convertFromScreen）->  overlayWindow 内坐标
        //   overlayWindow 内坐标 ->（convert from nil）->  overlayView 坐标

        let cgFrame = win.frame
        let flipH   = cgCoordFlipHeight

        // Step 1: CG -> AppKit 全局屏幕坐标
        let appKitScreenRect = NSRect(
            x:      cgFrame.origin.x,
            y:      flipH - cgFrame.origin.y - cgFrame.height, // Y 轴翻转
            width:  cgFrame.width,
            height: cgFrame.height
        )

        guard let parent = self.window else {
            // fallback：无父 window 时直接返回屏幕坐标作为近似
            return appKitScreenRect
        }

        // Step 2: AppKit 全局屏幕坐标 -> overlayWindow 内坐标
        let rectInWindow = parent.convertFromScreen(appKitScreenRect)
        // Step 3: overlayWindow 内坐标 -> overlayView 坐标
        return self.convert(rectInWindow, from: nil)
    }

    private func drawWindowTooltip(window: SCWindow, rect: CGRect, context: CGContext) {
        let appName = window.owningApplication?.applicationName ?? ""
        let winTitle = window.title ?? ""
        let text = appName + (winTitle.isEmpty ? "" : " - \(winTitle)")

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let maxTextWidth = min(textSize.width, rect.width - 20)
        let displaySize = CGSize(width: maxTextWidth, height: textSize.height)

        let padding: CGFloat = 6
        let boxRect = CGRect(
            x: rect.minX + 8,
            y: rect.maxY + 6,
            width: displaySize.width + padding * 2,
            height: displaySize.height + padding * 2
        )

        context.setFillColor(NSColor(red: 0.12, green: 0.56, blue: 1.0, alpha: 1.0).cgColor)
        let path = CGPath(roundedRect: boxRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        attrStr.draw(in: boxRect.insetBy(dx: padding, dy: padding))
    }

    private func drawWindowConfirmHint(context: CGContext) {
        let text = "点击确认 · Enter 确定  |  ESC 取消".localized
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let x = (bounds.width - textSize.width) / 2
        let y = (bounds.height - textSize.height) / 2

        context.setFillColor(NSColor(white: 0, alpha: 0.5).cgColor)
        let boxRect = CGRect(x: x - 15, y: y - 10, width: textSize.width + 30, height: textSize.height + 20)
        let path = CGPath(roundedRect: boxRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.fillPath()

        attrStr.draw(at: CGPoint(x: x, y: y))
    }
}

class ColorPresetButton: NSButton {
    let color: NSColor
    weak var parentView: CaptureOverlayView?
    private let fillLayer = CAShapeLayer()
    
    init(color: NSColor, parentView: CaptureOverlayView) {
        self.color = color
        self.parentView = parentView
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        self.wantsLayer = true
        self.isBordered = false
        self.title = ""
        self.layer?.cornerRadius = 12 // 圆形背景
        self.layer?.masksToBounds = true
        
        // 核心彩色填充层 (保持直径 16)
        fillLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: 4, dy: 4), transform: nil)
        fillLayer.fillColor = color.cgColor
        fillLayer.strokeColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        fillLayer.lineWidth = 0.5
        self.layer?.addSublayer(fillLayer)
        
        // 初始化时立刻刷新一次高亮态
        updateHighlightState(selectedColor: parentView.canvas?.currentColor ?? .systemRed)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateHighlightState(selectedColor: NSColor) {
        let isSelected = (color == selectedColor)
        // 选中时带有半透明白色背景（跟左侧工具按钮一致），未选中时透明
        self.layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
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
        // 与 addImage / currentStitchedImage 同走队列，避免读写竞态
        stitchingQueue.async { [weak self] in
            self?.runningStitchedImage = initialImage
            self?.previousImage = initialImage
        }
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
    private var statusBar: NSVisualEffectView!
    private var statusLabel: NSTextField!
    private var statusDot: NSView!
    private var topScrimLayer: CAGradientLayer!

    private let statusBarHeight: CGFloat = 22
    private let edgeInset: CGFloat = 4

    init(image: NSImage, size: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor

        // 图片视图
        imageView = NSImageView(frame: bounds.insetBy(dx: edgeInset, dy: edgeInset))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        addSubview(imageView)

        // 顶部渐变遮罩（提升状态条区域文字可读性，避免蓝色或浅色背景下不可读）
        topScrimLayer = CAGradientLayer()
        topScrimLayer.colors = [
            NSColor.black.withAlphaComponent(0.55).cgColor,
            NSColor.black.withAlphaComponent(0.0).cgColor
        ]
        topScrimLayer.locations = [0.0, 1.0]
        topScrimLayer.frame = topScrimFrame()
        layer?.addSublayer(topScrimLayer)

        // 状态条（暗色毛玻璃 HUD，保证在任何背景下都清晰）
        statusBar = NSVisualEffectView(frame: statusBarFrame())
        statusBar.material = .hudWindow
        statusBar.blendingMode = .withinWindow
        statusBar.state = .active
        statusBar.wantsLayer = true
        statusBar.layer?.cornerRadius = 5
        statusBar.layer?.masksToBounds = true
        statusBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        statusBar.layer?.borderWidth = 0.5
        addSubview(statusBar)

        // 状态指示小圆点（保留蓝色作为状态标识，但只是小点不影响阅读）
        statusDot = NSView(frame: .zero)
        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = NSColor.systemBlue.cgColor
        statusDot.layer?.cornerRadius = 3
        statusBar.addSubview(statusDot)

        // 状态文字
        statusLabel = NSTextField(labelWithString: "长截图捕获中...")
        statusLabel.textColor = .white
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        statusLabel.alignment = .left
        statusLabel.drawsBackground = false
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.6)
            s.shadowOffset = NSSize(width: 0, height: -1)
            s.shadowBlurRadius = 2
            return s
        }()
        statusBar.addSubview(statusLabel)

        layoutStatusBarContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    private func statusBarFrame() -> NSRect {
        NSRect(x: edgeInset + 2,
               y: bounds.height - statusBarHeight - edgeInset - 2,
               width: bounds.width - (edgeInset + 2) * 2,
               height: statusBarHeight)
    }

    private func topScrimFrame() -> NSRect {
        NSRect(x: 0, y: bounds.height - statusBarHeight - 14, width: bounds.width, height: statusBarHeight + 14)
    }

    private func layoutStatusBarContents() {
        let h = statusBar.bounds.height
        let dotSize: CGFloat = 6
        statusDot.frame = NSRect(x: 8, y: (h - dotSize) / 2, width: dotSize, height: dotSize)
        statusLabel.frame = NSRect(x: 8 + dotSize + 6,
                                   y: 0,
                                   width: statusBar.bounds.width - (8 + dotSize + 6) - 6,
                                   height: h)
    }

    func updateImage(_ newImage: NSImage, size: NSSize) {
        self.image = newImage
        imageView.image = newImage
        imageView.frame = bounds.insetBy(dx: edgeInset, dy: edgeInset)
        topScrimLayer.frame = topScrimFrame()
        statusBar.frame = statusBarFrame()
        layoutStatusBarContents()
    }
}

// MARK: - 长截图红色边框指示器
class LongScreenshotBorderView: NSView {
    var selectedRect: NSRect = .zero {
        didSet {
            needsDisplay = true
        }
    }
    
    init(frame frameRect: NSRect, selectedRect: NSRect) {
        self.selectedRect = selectedRect
        super.init(frame: frameRect)
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 1. 绘制四周的半透明黑色遮罩层（使用 evenOdd 挖空选区）
        context.setFillColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.35).cgColor)
        let outerPath = CGMutablePath()
        outerPath.addRect(bounds)
        outerPath.addRect(selectedRect)
        context.addPath(outerPath)
        context.fillPath(using: .evenOdd)
        
        // 2. 绘制选区蓝色边框
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(3)
        context.stroke(selectedRect)
        
        // 3. 绘制四角标记（基于 selectedRect 绘制）
        let cornerLength: CGFloat = 16
        let cornerWidth: CGFloat = 4
        context.setFillColor(NSColor.systemBlue.cgColor)
        
        // 左上角
        context.fill(CGRect(x: selectedRect.minX, y: selectedRect.maxY - cornerWidth, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: selectedRect.minX, y: selectedRect.maxY - cornerLength, width: cornerWidth, height: cornerLength))
        
        // 右上角
        context.fill(CGRect(x: selectedRect.maxX - cornerLength, y: selectedRect.maxY - cornerWidth, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: selectedRect.maxX - cornerWidth, y: selectedRect.maxY - cornerLength, width: cornerWidth, height: cornerLength))
        
        // 左下角
        context.fill(CGRect(x: selectedRect.minX, y: selectedRect.minY, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: selectedRect.minX, y: selectedRect.minY, width: cornerWidth, height: cornerLength))
        
        // 右下角
        context.fill(CGRect(x: selectedRect.maxX - cornerLength, y: selectedRect.minY, width: cornerLength, height: cornerWidth))
        context.fill(CGRect(x: selectedRect.maxX - cornerWidth, y: selectedRect.minY, width: cornerWidth, height: cornerLength))
        
        // 4. 绘制状态提示条
        let statusText = "正在捕获长截图... 按 Enter 保存 | ESC 取消"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = statusText.size(withAttributes: attrs)
        let padding: CGFloat = 8
        let statusBgRect = CGRect(
            x: selectedRect.minX + (selectedRect.width - textSize.width - padding * 2) / 2,
            y: selectedRect.maxY + 4,
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
