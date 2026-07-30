// RecordSelectionOverlayWindow.swift
// SnapClick - 录屏专属选区覆盖窗口与设置面板
// 实现了完美的选区拖拽调整、分辨率气泡以及 Stitch 风格的毛玻璃 HUD 控制条

import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation

// MARK: - 选区工作模式
enum RecordSelectionMode {
    case areaSelection
    case windowSelection
}

// MARK: - 选区手柄枚举
enum RecordDragHandle {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight, center
}

// MARK: - 录屏选区覆盖窗口
final class RecordSelectionOverlayWindow: NSWindow {
    
    // MARK: 回调
    var onFinished: ((CGRect?, SCWindow?) -> Void)?
    var onCancelled: (() -> Void)?
    
    // MARK: 私有属性
    private let backgroundImage: NSImage
    private var overlayView: RecordSelectionOverlayView!
    
    init(backgroundImage: NSImage, windows: [SCWindow] = [], screen: NSScreen? = nil, mode: RecordSelectionMode = .areaSelection) {
        self.backgroundImage = backgroundImage
        
        let targetScreen = screen ?? NSScreen.main
        let screenFrame = targetScreen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.acceptsMouseMovedEvents = true
        
        if let screenColorSpace = targetScreen?.colorSpace {
            self.colorSpace = screenColorSpace
        }
        
        self.overlayView = RecordSelectionOverlayView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            backgroundImage: backgroundImage,
            parentWindow: self,
            windows: windows
        )
        self.overlayView.mode = mode
        self.contentView = overlayView
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC 键
            cancelSelection()
        }
    }
    
    func startRecording(with rect: CGRect?, window: SCWindow?) {
        orderOut(nil)
        overlayView.closeHUD()
        onFinished?(rect, window)
    }
    
    func cancelSelection() {
        orderOut(nil)
        overlayView.closeHUD()
        onCancelled?()
    }
}

// MARK: - 选区覆盖层视图 (AppKit)
final class RecordSelectionOverlayView: NSView {
    
    private let backgroundImage: NSImage
    private weak var parentWindow: RecordSelectionOverlayWindow?
    private let availableWindows: [SCWindow]
    
    // 选区数据
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var isDragging: Bool = false
    private var activeHandle: RecordDragHandle? = nil
    private var dragStartRect: CGRect = .zero
    
    var mode: RecordSelectionMode = .areaSelection {
        didSet {
            needsDisplay = true
        }
    }
    var hoveredWindow: SCWindow?
    var selectedWindow: SCWindow?
    private var selectedWindowImage: NSImage?
    
    var selectedRect: CGRect = .zero {
        didSet {
            needsDisplay = true
            updateHUDPosition()
        }
    }
    
    // HUD 窗口
    private var hudWindow: NSWindow?
    
    private var cgCoordFlipHeight: CGFloat {
        return NSScreen.screens.map { $0.frame.maxY }.max() ?? NSScreen.main?.frame.height ?? 900
    }

    private func winToViewRect(_ win: SCWindow) -> CGRect {
        let cgFrame = win.frame
        let flipH   = cgCoordFlipHeight

        let appKitScreenRect = NSRect(
            x:      cgFrame.origin.x,
            y:      flipH - cgFrame.origin.y - cgFrame.height,
            width:  cgFrame.width,
            height: cgFrame.height
        )

        guard let parent = self.window else {
            return appKitScreenRect
        }

        let rectInWindow = parent.convertFromScreen(appKitScreenRect)
        return self.convert(rectInWindow, from: nil)
    }
    
    init(frame: NSRect, backgroundImage: NSImage, parentWindow: RecordSelectionOverlayWindow, windows: [SCWindow] = []) {
        self.backgroundImage = backgroundImage
        self.parentWindow = parentWindow
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

        // 窗口选择模式：保持真实屏幕完全透出，不绘制任何蒙版（黑色或蓝色），
        // 仅在悬停目标窗口边缘画蓝色高亮描边 + 信息气泡作为视觉引导。
        if mode == .windowSelection {
            if let win = hoveredWindow {
                let appKitFrame = winToViewRect(win)

                let themeColor = NSColor(red: 0.12, green: 0.56, blue: 1.0, alpha: 1.0)
                context.setStrokeColor(themeColor.cgColor)
                context.setLineWidth(3.0)
                context.stroke(appKitFrame)

                drawWindowTooltip(window: win, rect: appKitFrame, context: context)
            } else {
                // 未悬停任意窗口时，仅显示提示文字
                drawWindowHintText(context: context)
            }
            return
        }

        // 区域选择模式：保留原有"快照 + 暗化蒙层 + 选区高亮"交互
        // 1. 绘制背景底图
        backgroundImage.draw(in: bounds)

        // 2. 绘制暗化蒙层
        context.setFillColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.4).cgColor)

        let rect = isDragging && activeHandle == nil ? normalizedSelectedRect() : selectedRect

        if rect.width > 2 && rect.height > 2 {
            let outerPath = CGMutablePath()
            outerPath.addRect(bounds)
            outerPath.addRect(rect)
            context.addPath(outerPath)
            context.fillPath(using: .evenOdd)

            if let winImg = selectedWindowImage, selectedWindow != nil {
                winImg.draw(in: rect)
            }

            drawSelectionBorder(rect: rect, context: context)
            drawSizeTooltip(rect: rect, context: context)
        } else {
            context.fill(bounds)
            drawHintText(context: context)
        }
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
    
    private func drawWindowHintText(context: CGContext) {
        let text = "将鼠标悬停在要录制的窗口上，点击选择  |  ESC 取消".localized
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
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
    
    // MARK: - 绘制辅助
    private func normalizedSelectedRect() -> CGRect {
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func drawSelectionBorder(rect: CGRect, context: CGContext) {
        let themeColor = NSColor(red: 0.12, green: 0.56, blue: 1.0, alpha: 1.0)
        context.setStrokeColor(themeColor.cgColor)
        context.setLineWidth(2.0)
        context.stroke(rect)
        
        context.setFillColor(themeColor.cgColor)
        let pointSize: CGFloat = 8.0
        let halfSize = pointSize / 2.0
        
        let handles = [
            CGPoint(x: rect.minX, y: rect.minY), // 左上
            CGPoint(x: rect.midX, y: rect.minY), // 中上
            CGPoint(x: rect.maxX, y: rect.minY), // 右上
            CGPoint(x: rect.minX, y: rect.midY), // 左中
            CGPoint(x: rect.maxX, y: rect.midY), // 右中
            CGPoint(x: rect.minX, y: rect.maxY), // 左下
            CGPoint(x: rect.midX, y: rect.maxY), // 中下
            CGPoint(x: rect.maxX, y: rect.maxY)  // 右下
        ]
        
        for p in handles {
            let handleRect = CGRect(x: p.x - halfSize, y: p.y - halfSize, width: pointSize, height: pointSize)
            context.fillEllipse(in: handleRect)
        }
    }
    
    private func drawSizeTooltip(rect: CGRect, context: CGContext) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let wPx = Int(rect.width * scale)
        let hPx = Int(rect.height * scale)
        let text = "\(wPx) × \(hPx)"
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let padding: CGFloat = 5
        let boxRect = CGRect(
            x: rect.minX,
            y: rect.maxY + 6,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        
        context.setFillColor(NSColor(red: 0.12, green: 0.56, blue: 1.0, alpha: 1.0).cgColor)
        let path = CGPath(roundedRect: boxRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()
        
        attrStr.draw(in: boxRect.insetBy(dx: padding, dy: padding))
    }
    
    private func drawHintText(context: CGContext) {
        let text = "拖拽选择要录屏的区域  |  ESC 取消".localized
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
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
    
    // MARK: - 鼠标事件与选区调整
    private func getHandleAt(point: NSPoint) -> RecordDragHandle? {
        let rect = selectedRect
        let threshold: CGFloat = 10.0
        
        if rect.width <= 0 || rect.height <= 0 { return nil }
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        if abs(point.x - minX) < threshold && abs(point.y - minY) < threshold { return .topLeft }
        if abs(point.x - maxX) < threshold && abs(point.y - minY) < threshold { return .topRight }
        if abs(point.x - minX) < threshold && abs(point.y - maxY) < threshold { return .bottomLeft }
        if abs(point.x - maxX) < threshold && abs(point.y - maxY) < threshold { return .bottomRight }
        
        if abs(point.y - minY) < threshold && point.x > minX && point.x < maxX { return .top }
        if abs(point.y - maxY) < threshold && point.x > minX && point.x < maxX { return .bottom }
        if abs(point.x - minX) < threshold && point.y > minY && point.y < maxY { return .left }
        if abs(point.x - maxX) < threshold && point.y > minY && point.y < maxY { return .right }
        
        if rect.contains(point) { return .center }
        return nil
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        // 检查是否在 HUD 区域内，如果在，则不触发选区拖拽
        if let hud = hudWindow, hud.frame.contains(convert(event.locationInWindow, to: nil)) {
            return
        }
        
        if mode == .windowSelection {
            if let win = hoveredWindow {
                selectedWindow = win
                selectedRect = winToViewRect(win)
                mode = .areaSelection
                
                if let app = win.owningApplication,
                   let runningApp = NSRunningApplication(processIdentifier: app.processID) {
                    runningApp.activate(options: [.activateIgnoringOtherApps])
                }
                
                Task { @MainActor in
                    do {
                        let img = try await ScreenCaptureEngine.shared.captureSingleWindow(win)
                        self.selectedWindowImage = img
                        self.needsDisplay = true
                    } catch {
                        print("[RecordSelectionOverlayView] 捕获窗口画面失败: \(error)")
                    }
                }
                
                showHUD()
            }
            return
        }
        
        if selectedRect.width > 10 && selectedRect.height > 10, let handle = getHandleAt(point: loc) {
            activeHandle = handle
            dragStartRect = selectedRect
            startPoint = loc
            selectedWindow = nil
            selectedWindowImage = nil
        } else {
            activeHandle = nil
            startPoint = loc
            currentPoint = loc
            isDragging = true
            selectedRect = .zero
            selectedWindow = nil
            selectedWindowImage = nil
        }
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        if isDragging {
            currentPoint = loc
            selectedRect = normalizedSelectedRect()
        } else if let handle = activeHandle {
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
            
            // 限制最小宽高
            let minSize: CGFloat = 50
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
            
            // 限制不要移出屏幕
            newRect.origin.x = max(0, min(newRect.origin.x, bounds.width - newRect.width))
            newRect.origin.y = max(0, min(newRect.origin.y, bounds.height - newRect.height))
            
            selectedRect = newRect
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            let rect = normalizedSelectedRect()
            if rect.width > 10 && rect.height > 10 {
                selectedRect = rect
                showHUD()
            } else {
                selectedRect = .zero
                closeHUD()
            }
        }
        activeHandle = nil
    }
    
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        if mode == .windowSelection {
            let win = windowAtPoint(loc)
            if win?.windowID != hoveredWindow?.windowID {
                hoveredWindow = win
                needsDisplay = true
            }
            if hoveredWindow != nil {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        
        if selectedRect.width > 10 && selectedRect.height > 10, let handle = getHandleAt(point: loc) {
            switch handle {
            case .topLeft, .bottomRight: NSCursor.crosshair.set()
            case .topRight, .bottomLeft: NSCursor.crosshair.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .center: NSCursor.openHand.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }
    
    private func windowAtPoint(_ viewPoint: NSPoint) -> SCWindow? {
        guard let win = self.window else {
            let cgPt = CGPoint(x: viewPoint.x, y: cgCoordFlipHeight - viewPoint.y)
            return availableWindows.first { $0.frame.contains(cgPt) }
        }

        let pointInWindow = self.convert(viewPoint, to: nil)
        let pointInScreen = win.convertToScreen(NSRect(origin: pointInWindow, size: .zero)).origin
        let cgPoint = CGPoint(x: pointInScreen.x, y: cgCoordFlipHeight - pointInScreen.y)

        for window in availableWindows {
            if window.frame.contains(cgPoint) {
                return window
            }
        }
        return nil
    }
    
    // MARK: - HUD 管理与通信
    private func showHUD() {
        if hudWindow == nil {
            let hudView = RecordingSelectionHUDView(
                onRecord: { [weak self] in
                    guard let self = self else { return }
                    self.parentWindow?.startRecording(with: self.selectedRect, window: self.selectedWindow)
                },
                onCancel: { [weak self] in
                    self?.parentWindow?.cancelSelection()
                },
                onResolutionChange: { [weak self] res in
                    self?.adjustSelectionForResolution(res)
                }
            )
            
            let hostingView = NSHostingView(rootView: hudView)
            hostingView.frame = CGRect(x: 0, y: 0, width: 880, height: 64)

            let panel = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 880, height: 64),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.contentView = hostingView
            
            self.hudWindow = panel
            parentWindow?.addChildWindow(panel, ordered: .above)
        }
        
        updateHUDPosition()
        hudWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func updateHUDPosition() {
        guard let hud = hudWindow else { return }

        let hudWidth: CGFloat = 880
        let hudHeight: CGFloat = 64
        let margin: CGFloat = 12

        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        var x = selectedRect.midX - hudWidth / 2

        // 优先放在选区上方，其次选区下方，若上下都超出屏幕（如全屏/满屏窗口）则浮在选区内部底部
        var y: CGFloat
        if selectedRect.minY - hudHeight - margin >= 10 {
            y = selectedRect.minY - hudHeight - margin
        } else if selectedRect.maxY + margin + hudHeight <= screenFrame.height - 10 {
            y = selectedRect.maxY + margin
        } else {
            y = selectedRect.minY + margin
        }

        // 兜底夹紧，确保 HUD 始终完整可见
        y = max(10, min(y, screenFrame.height - hudHeight - 10))
        x = max(10, min(x, screenFrame.width - hudWidth - 10))
        hud.setFrame(CGRect(x: screenFrame.origin.x + x, y: screenFrame.origin.y + y, width: hudWidth, height: hudHeight), display: true)
    }
    
    func closeHUD() {
        if let hud = hudWindow {
            parentWindow?.removeChildWindow(hud)
            hud.orderOut(nil)
            hudWindow = nil
        }
    }
    
    private func adjustSelectionForResolution(_ res: String) {
        // 设计原则：用户调整录制参数（分辨率/格式/帧率等）时，选区窗口大小不应发生变化。
        // 分辨率仅决定输出视频文件的目标像素尺寸，由 ScreenRecordingEngine 在编码阶段按
        // 选区宽高比进行缩放，这里不再修改 selectedRect。
        _ = res
    }
}

// MARK: - SwiftUI 录屏设置面板
struct RecordingSelectionHUDView: View {
    let onRecord: () -> Void
    let onCancel: () -> Void
    let onResolutionChange: (String) -> Void

    /// 是否显示"屏幕"下拉：仅全屏录制场景下需要
    /// 选区/窗口录制时不需要（屏幕由选区/窗口位置决定）
    var showsScreenSelection: Bool = false

    @ObservedObject private var settings = AppSettings.shared
    @State private var microphones: [String] = ["无"]
    @State private var isCursorHovered = false

    /// 独立 HUD（带"屏幕"下拉）比选区底部 HUD 多 ~150px，
    /// 必须和 RecordHUDStandaloneWindow.hudWidth 保持一致，否则内容会被裁掉
    private var hudFrameWidth: CGFloat {
        showsScreenSelection ? 1030 : 880
    }
    
    private var savePathDisplayName: String {
        let path = settings.recordSavePath
        if path.hasSuffix("Desktop") {
            return "桌面".localized
        } else if path.hasSuffix("Downloads") {
            return "下载".localized
        } else {
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {

            // ── 0. 屏幕（仅全屏录制场景，由 showsScreenSelection 控制） ────
            if showsScreenSelection {
                HUDDropdown(
                    label: "屏幕",
                    selection: Binding(
                        get: {
                            let saved = settings.recordFullScreenScreenName
                            if !saved.isEmpty,
                               NSScreen.screens.contains(where: { $0.localizedName == saved }) {
                                return saved
                            }
                            return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.localizedName
                                ?? NSScreen.main?.localizedName
                                ?? NSScreen.screens.first?.localizedName
                                ?? ""
                        },
                        set: { newName in
                            settings.recordFullScreenScreenName = newName
                        }
                    ),
                    options: NSScreen.screens.enumerated().map { idx, screen in
                        let isMain = (screen == NSScreen.main)
                        return "屏幕 \(idx + 1)" + (isMain ? " · 主屏" : "")
                    },
                    width: 124
                )
                .help("选择要录制的屏幕（多屏环境）")

                HUDSeparator()
            }

            // ── 1. 清晰度（3 档：标清 / 超清 / 原画） ───────────────
            HUDDropdown(
                label: "清晰度",
                selection: $settings.recordQuality,
                options: ["标清", "超清", "原画"],
                width: 90,
                onChange: onResolutionChange
            )

            // ── 2. 格式与编码 ──────────────────────────────────────
            HUDDropdown(
                label: "格式",
                selection: Binding(
                    get: { "\(settings.recordFormat) (\(settings.recordCodec))" },
                    set: { val in
                        let parts = val.replacingOccurrences(of: ")", with: "").split(separator: " (")
                        if parts.count == 2 {
                            settings.recordFormat = String(parts[0])
                            settings.recordCodec = String(parts[1])
                        }
                    }
                ),
                options: ["MOV (H.264)", "MOV (HEVC)", "MP4 (H.264)", "MP4 (HEVC)"],
                width: 110
            )

            // ── 3. 帧率 ──────────────────────────────────────────
            HUDDropdown(
                label: "帧率",
                selection: Binding(
                    get: { "\(settings.recordFPS) fps" },
                    set: { settings.recordFPS = Int($0.replacingOccurrences(of: " fps", with: "")) ?? 60 }
                ),
                options: ["30 fps", "60 fps", "120 fps"],
                width: 66
            )

            HUDSeparator()

            // ── 4. 麦克风 ─────────────────────────────────────────
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 1.0, opacity: 0.8))
                    .padding(.top, 10)

                HUDDropdown(
                    label: "麦克风",
                    selection: $settings.recordMicrophone,
                    options: microphones,
                    width: 110
                )
            }

            // ── 5. 系统声音 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text("系统声音")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.4))

                HStack(spacing: 4) {
                    Image(systemName: settings.recordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(settings.recordSystemAudio ? .green : Color(white: 1.0, opacity: 0.8))
                        .frame(width: 14)

                    Button(action: {
                        settings.recordSystemAudio.toggle()
                    }) {
                        ZStack(alignment: settings.recordSystemAudio ? .trailing : .leading) {
                            Capsule()
                                .fill(settings.recordSystemAudio ? Color.green : Color(white: 1.0, opacity: 0.2))
                                .frame(width: 32, height: 18)
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .padding(.horizontal, 2)
                        }
                        .animation(.easeInOut(duration: 0.15), value: settings.recordSystemAudio)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 24)
            }

            // ── 6. 鼠标指针高亮 ────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text("鼠标")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.4))

                Button(action: {
                    settings.recordHighlightCursor.toggle()
                }) {
                    Image(systemName: settings.recordHighlightCursor ? "cursorarrow.and.square.on.square.dashed" : "cursorarrow.motionlines")
                        .font(.system(size: 12))
                        .foregroundColor(settings.recordHighlightCursor ? .blue : Color(white: 1.0, opacity: 0.8))
                        .frame(width: 26, height: 26)
                        .background(isCursorHovered ? Color.blue.opacity(0.12) : Color(white: 1.0, opacity: 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isCursorHovered ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 0.5)
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isCursorHovered = hovering
                }
            }
            .help("录像中是否显示并高亮鼠标指针")

            // ── 7. 保存路径 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text("保存到")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.4))

                HUDFolderButton(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        settings.recordSavePath = url.path
                    }
                }, savePathDisplayName: savePathDisplayName)
            }
            .help("修改保存路径: \(settings.recordSavePath)")

            HUDSeparator()

            // ── 8. 定时倒计时 ──────────────────────────────────────
            HUDDropdown(
                label: "倒计时",
                selection: Binding(
                    get: { settings.recordTimer == 0 ? "关" : "\(settings.recordTimer)秒" },
                    set: {
                        if $0 == "关" {
                            settings.recordTimer = 0
                        } else {
                            let s = $0.replacingOccurrences(of: "秒", with: "")
                            settings.recordTimer = Int(s) ?? 0
                        }
                    }
                ),
                options: ["关", "3秒", "5秒", "10秒"],
                width: 60
            )

            // 倒计时和动作按钮之间留一点视觉间隔即可，不要占满整行
            // （之前用 Spacer() 会把按钮推到 HUD 最右端，全屏 HUD 1030pt 宽时中间空一大段）
            Spacer(minLength: 0)
                .frame(maxWidth: 16)

            // ── 9. 动作按钮 ───────────────────────────────────────
            HUDCancelButton(action: onCancel)
                .help("取消录屏 (ESC)")

            HUDRecordButton(action: onRecord)
                .help("开始录制")

        }
        .padding(.horizontal, 14)
        .frame(width: hudFrameWidth, height: 64)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .cornerRadius(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(white: 1.0, opacity: 0.15), lineWidth: 0.5)
                )
        )
        .colorScheme(.dark)
        .onAppear {
            loadMicrophones()
        }
    }
    
    private func loadMicrophones() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = ["无"] + session.devices.map { $0.localizedName }
        self.microphones = devices
        
        if !devices.contains(settings.recordMicrophone) {
            settings.recordMicrophone = "无"
        }
    }
}

// MARK: - HUD 风格文件夹选择按钮
struct HUDFolderButton: View {
    let action: () -> Void
    let savePathDisplayName: String
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isHovered ? .blue : .white)
                Text(savePathDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(isHovered ? Color.blue.opacity(0.12) : Color(white: 1.0, opacity: 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 0.5)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - HUD 风格取消按钮 (带红色 Hover)
struct HUDCancelButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isHovered ? .red : Color(white: 1.0, opacity: 0.7))
                .frame(width: 30, height: 30)
                .background(isHovered ? Color.red.opacity(0.15) : Color(white: 1.0, opacity: 0.08))
                .overlay(
                    Circle()
                        .stroke(isHovered ? Color.red.opacity(0.5) : Color.clear, lineWidth: 0.5)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - HUD 风格录制按钮 (带蓝色环绕与红点弹动)
struct HUDRecordButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(isHovered ? Color.blue : Color.white, lineWidth: 2.2)
                    .frame(width: 36, height: 36)
                    .shadow(color: isHovered ? Color.blue.opacity(0.5) : Color.clear, radius: 4)
                Circle()
                    .fill(Color.red)
                    .frame(width: 26, height: 26)
                    .scaleEffect(isHovered ? 1.15 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - HUD 风格下拉组件 (Hover 具备淡蓝色高亮发光，与截图的Snipaste蓝相呼应)
struct HUDDropdown: View {
    let label: String
    @Binding var selection: String
    let options: [String]
    var width: CGFloat
    var onChange: ((String) -> Void)? = nil
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(white: 1.0, opacity: 0.4))
            
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) {
                        selection = opt
                        onChange?(opt)
                    }
                }
            } label: {
                HStack {
                    Text(selection.localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isHovered ? .blue : Color(white: 1.0, opacity: 0.5))
                }
                .padding(.horizontal, 8)
                .frame(width: width, height: 26)
                .background(isHovered ? Color.blue.opacity(0.12) : Color(white: 1.0, opacity: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 0.5)
                )
                .cornerRadius(6)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}

// MARK: - HUD 分隔符
struct HUDSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(white: 1.0, opacity: 0.15))
            .frame(width: 1, height: 26)
    }
}


