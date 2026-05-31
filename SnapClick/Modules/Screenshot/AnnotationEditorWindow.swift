// AnnotationEditorWindow.swift
// SnapClick - 标注编辑器窗口
// 提供完整的图片标注编辑界面

import AppKit

// MARK: - 标注编辑器窗口控制器
class AnnotationEditorWindowController: NSWindowController {
    convenience init(screenshot: NSImage) {
        let window = AnnotationEditorWindow(screenshot: screenshot)
        self.init(window: window)
    }
}

// MARK: - 标注编辑器窗口
class AnnotationEditorWindow: NSWindow, AnnotationCanvasDelegate {

    // MARK: - 子视图
    fileprivate let canvas:       AnnotationCanvas
    private let editorToolbar: NSVisualEffectView
    private let scrollView:   NSScrollView

    // MARK: - 工具栏按钮
    private var toolButtons:  [AnnotationToolType: NSButton] = [:]
    private var undoButton:   NSButton!
    private var redoButton:   NSButton!
    private var clearButton:  NSButton!
    private var doneButton:   NSButton!
    private var copyButton:   NSButton!
    private var shareButton:  NSButton!

    // MARK: - 颜色和大小控件
    private var colorWell:    NSColorWell!
    private var sizeSlider:   NSSlider!
    private var sizeLabel:    NSTextField!

    // MARK: - 常量
    private let toolbarH:     CGFloat = 44
    private let canvasInset:  CGFloat = 20  // 画布内边距

    // MARK: - 初始化
    init(screenshot: NSImage) {
        // 计算窗口大小
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screenFrame.width  * 0.9
        let maxH = screenFrame.height * 0.9
        let imgW  = screenshot.size.width
        let imgH  = screenshot.size.height

        // 按比例缩放截图到窗口
        let scale = min(maxW / max(imgW, 1), (maxH - 120) / max(imgH, 1), 1.0)
        let winW  = max(imgW * scale + canvasInset * 2, 780)
        let winH  = max(imgH * scale + canvasInset * 2 + 100, 480)

        let windowRect = CGRect(
            x: screenFrame.midX - winW / 2,
            y: screenFrame.midY - winH / 2,
            width:  winW,
            height: winH
        )

        // 初始化 canvas
        let canvasFrame = CGRect(
            x:      canvasInset,
            y:      canvasInset,
            width:  imgW * scale,
            height: imgH * scale
        )
        canvas = AnnotationCanvas(frame: canvasFrame)
        canvas.baseImage = screenshot

        // 初始化 editorToolbar 为 vibrancy-dark 毛玻璃
        editorToolbar = NSVisualEffectView()
        editorToolbar.material = .hudWindow
        editorToolbar.blendingMode = .withinWindow
        editorToolbar.state = .active
        editorToolbar.wantsLayer = true
        editorToolbar.layer?.cornerRadius = 22
        editorToolbar.layer?.masksToBounds = true
        editorToolbar.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        editorToolbar.layer?.borderWidth = 0.5

        // 初始化 scrollView（包裹 canvas）
        scrollView = NSScrollView(frame: CGRect(
            x:      0,
            y:      0,
            width:  winW,
            height: winH
        ))

        super.init(
            contentRect: windowRect,
            styleMask:   [.titled, .closable, .miniaturizable, .resizable],
            backing:     .buffered,
            defer:       false
        )

        title       = "SnapClick 标注编辑器"
        isReleasedWhenClosed = false
        minSize     = CGSize(width: 780, height: 480)
        canvas.delegate = self

        setupContentView(winSize: CGSize(width: winW, height: winH))
        setupScrollView(canvasFrame: canvasFrame)
        setupToolbar()
        setupLiveIndicator()
        updateButtonStates()
        
        // 默认选中矩形工具
        selectTool(.rectangle)
    }

    // MARK: - 内容视图
    private func setupContentView(winSize: CGSize) {
        let contentView = NSView(frame: CGRect(origin: .zero, size: winSize))
        contentView.wantsLayer = true
        // 采用稍微深沉的专业灰色背景以烘托截图
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor
        self.contentView = contentView
    }

    // MARK: - 悬浮工具栏
    private func setupToolbar() {
        contentView?.addSubview(editorToolbar)
        editorToolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editorToolbar.centerXAnchor.constraint(equalTo: contentView!.centerXAnchor),
            editorToolbar.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor, constant: -20),
            editorToolbar.heightAnchor.constraint(equalToConstant: toolbarH),
            editorToolbar.widthAnchor.constraint(equalToConstant: 800)
        ])

        // 左侧：工具按钮组
        let toolGroup = makeToolButtonGroup()
        editorToolbar.addSubview(toolGroup)
        toolGroup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolGroup.leadingAnchor.constraint(equalTo: editorToolbar.leadingAnchor, constant: 12),
            toolGroup.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor)
        ])

        // 中间：颜色 + 尺寸调节
        let styleGroup = makeStyleControls()
        editorToolbar.addSubview(styleGroup)
        styleGroup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            styleGroup.centerXAnchor.constraint(equalTo: editorToolbar.centerXAnchor),
            styleGroup.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor)
        ])

        // 右侧：操作按钮
        let actionGroup = makeActionButtons()
        editorToolbar.addSubview(actionGroup)
        actionGroup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            actionGroup.trailingAnchor.constraint(equalTo: editorToolbar.trailingAnchor, constant: -12),
            actionGroup.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor)
        ])
    }

    // MARK: 工具按钮组
    private func makeToolButtonGroup() -> NSStackView {
        var buttons: [NSView] = []

        for tool in AnnotationToolType.allCases {
            let btn = makeToolButton(for: tool)
            toolButtons[tool] = btn
            buttons.append(btn)
        }

        // 插入小隔断，美化排版
        let separator1 = makeSeparator()
        buttons.insert(separator1, at: 4) // 在画笔之前

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing     = 4
        return stack
    }

    private func makeToolButton(for tool: AnnotationToolType) -> HoverButton {
        let btn = HoverButton(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        btn.bezelStyle      = .regularSquare
        btn.isBordered      = false
        btn.imagePosition   = .imageOnly
        btn.wantsLayer      = true
        btn.layer?.cornerRadius = 16 // 圆形按钮

        let pointSize: CGFloat = tool == .text ? 17 : 13
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let img = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.displayName)?
            .withSymbolConfiguration(config) {
            btn.image = img
        } else {
            btn.title = tool.shortcutKey
        }

        btn.contentTintColor  = NSColor.white.withAlphaComponent(0.85)
        btn.customToolTip    = "\(tool.displayName) (\(tool.shortcutKey))"
        btn.onHover          = { [weak self] isHovered, button in
            self?.handleButtonHover(isHovered: isHovered, button: button)
        }
        btn.target           = self
        btn.action           = #selector(toolButtonClicked(_:))
        btn.tag              = AnnotationToolType.allCases.firstIndex(of: tool) ?? 0
        return btn
    }

    // MARK: 样式控件
    private func makeStyleControls() -> NSStackView {
        // 颜色选择器
        colorWell = NSColorWell(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorWellChanged(_:))
        colorWell.toolTip = "更多颜色"

        // 快捷正圆色标组件
        var colorButtons: [NSView] = []
        for color in AnnotationColorPreset.presets {
            let swatch = ColorSwatch(color: color, parent: self)
            colorButtons.append(swatch)
        }

        // 大小调节滑块
        sizeLabel = makeLabel("2")
        sizeSlider = NSSlider(value: 2, minValue: 1, maxValue: 20, target: self,
                              action: #selector(sizeSliderChanged(_:)))
        sizeSlider.frame = CGRect(x: 0, y: 0, width: 70, height: 20)
        sizeSlider.toolTip = "线条与字体尺寸"

        let views: [NSView] = [colorWell]
            + colorButtons
            + [makeSeparator(), makeLabel("大小:"), sizeSlider, sizeLabel]

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing     = 6
        stack.alignment = .centerY
        return stack
    }

    // MARK: 操作按钮
    private func makeActionButtons() -> NSStackView {
        undoButton  = makeIconButton(symbol: "arrow.uturn.backward", tip: "撤销 ⌘Z",    action: #selector(undoAction))
        redoButton  = makeIconButton(symbol: "arrow.uturn.forward",  tip: "重做 ⌘⇧Z", action: #selector(redoAction))
        clearButton = makeIconButton(symbol: "trash",                  tip: "清除全部",   action: #selector(clearAction))
        copyButton  = makeIconButton(symbol: "doc.on.doc",             tip: "复制 ⌘C",    action: #selector(copyAction))
        shareButton = makeIconButton(symbol: "square.and.arrow.up",   tip: "分享",       action: #selector(shareAction))
        
        // 极富质感的高饱和度 Done 蓝色完成大按钮
        doneButton = NSButton(frame: CGRect(x: 0, y: 0, width: 62, height: 28))
        doneButton.bezelStyle = .regularSquare
        doneButton.isBordered = false
        doneButton.wantsLayer = true
        doneButton.layer?.cornerRadius = 14
        doneButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        doneButton.title = "Done"
        doneButton.contentTintColor = .white
        doneButton.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        doneButton.target = self
        doneButton.action = #selector(doneAction)
        doneButton.toolTip = "保存并复制 (Enter)"

        let cancelBtn = makeIconButton(symbol: "xmark", tip: "取消", action: #selector(cancelAction))

        let stack = NSStackView(views: [
            undoButton, redoButton, makeSeparator(),
            clearButton, makeSeparator(),
            copyButton, shareButton, cancelBtn,
            doneButton
        ])
        stack.orientation = .horizontal
        stack.spacing     = 4
        stack.alignment = .centerY
        return stack
    }

    private func makeIconButton(symbol: String, tip: String, action: Selector) -> HoverButton {
        let btn = HoverButton(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 15

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(config) {
            btn.image = img
        }
        btn.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        btn.customToolTip = tip
        btn.onHover       = { [weak self] isHovered, button in
            self?.handleButtonHover(isHovered: isHovered, button: button)
        }
        btn.target   = self
        btn.action   = action
        return btn
    }

    private func makeSeparator() -> NSView {
        let sep = NSView(frame: CGRect(x: 0, y: 0, width: 1, height: 22))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 22).isActive = true
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
        guard let contentView = self.contentView else { return }
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
            
            contentView.addSubview(effect)
            self.customToolTipView = effect
            self.customToolTipLabel = label
        }
        
        customToolTipLabel?.stringValue = button.customToolTip
        customToolTipView?.isHidden = false
        
        let btnFrame = button.convert(button.bounds, to: contentView)
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

    // MARK: - 右上角 Live Annotation 红色呼吸灯面板
    private func setupLiveIndicator() {
        let indicator = NSVisualEffectView()
        indicator.material = .hudWindow
        indicator.blendingMode = .withinWindow
        indicator.state = .active
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 8
        indicator.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        indicator.layer?.borderWidth = 0.5
        
        let redDot = NSView()
        redDot.wantsLayer = true
        redDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        redDot.layer?.cornerRadius = 4.5
        
        // 呼吸脉冲动画
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = 0.85
        pulse.repeatCount = .infinity
        pulse.autoreverses = true
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        redDot.layer?.add(pulse, forKey: "pulse")
        
        let label = NSTextField(labelWithString: "Live Annotation Mode")
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        
        let stack = NSStackView(views: [redDot, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        
        indicator.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: indicator.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: indicator.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: indicator.bottomAnchor, constant: -6),
            
            redDot.widthAnchor.constraint(equalToConstant: 9),
            redDot.heightAnchor.constraint(equalToConstant: 9)
        ])
        
        contentView?.addSubview(indicator)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -20),
            indicator.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 20)
        ])
    }

    // MARK: - 滚动视图（包裹 canvas）
    private func setupScrollView(canvasFrame: CGRect) {
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers    = true
        scrollView.backgroundColor       = .clear
        scrollView.drawsBackground       = false

        let clipView = scrollView.contentView
        clipView.documentView = canvas

        // 设置 canvas 在 scrollView 中的大小，保留优雅的 30pt 外间隙
        let totalW = canvasFrame.width + canvasInset * 2
        let totalH = canvasFrame.height + canvasInset * 2
        let docView = NSView(frame: CGRect(x: 0, y: 0, width: totalW, height: totalH))
        docView.wantsLayer = true
        docView.layer?.backgroundColor = NSColor.clear.cgColor
        
        canvas.frame = CGRect(
            x:      canvasInset,
            y:      canvasInset,
            width:  canvasFrame.width,
            height: canvasFrame.height
        )
        docView.addSubview(canvas)
        scrollView.documentView = docView

        contentView?.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor)
        ])
    }

    // MARK: - 工具切换
    @objc private func toolButtonClicked(_ sender: NSButton) {
        let tool = AnnotationToolType.allCases[sender.tag]
        selectTool(tool)
    }

    private func selectTool(_ tool: AnnotationToolType) {
        canvas.currentTool = tool

        // 更新按钮高亮状态 (vibrant hover 效果)
        for (t, btn) in toolButtons {
            btn.layer?.backgroundColor = (t == tool)
                ? NSColor.white.withAlphaComponent(0.18).cgColor
                : .none
            btn.contentTintColor = (t == tool) ? .white : NSColor.white.withAlphaComponent(0.7)
        }
    }

    // MARK: - 颜色变更
    @objc private func colorWellChanged(_ sender: NSColorWell) {
        setColor(sender.color)
    }

    func setColor(_ color: NSColor) {
        canvas.currentColor = color
        colorWell?.color    = color
        
        // 触发所有子色块重绘，以显示/隐藏白描边高亮态
        for view in editorToolbar.subviews {
            if let stack = view as? NSStackView {
                for item in stack.views {
                    if let swatch = item as? ColorSwatch {
                        swatch.updateHighlightState(selectedColor: color)
                    }
                }
            }
        }
    }

    // MARK: - 大小滑块
    @objc private func sizeSliderChanged(_ sender: NSSlider) {
        let val = CGFloat(sender.doubleValue)
        canvas.currentLineWidth = val
        canvas.currentFontSize  = val * 4  // 字号为线宽 4 倍
        sizeLabel.stringValue   = "\(Int(val))"
    }

    // MARK: - 工具操作
    @objc private func undoAction()  { canvas.undo(); updateButtonStates() }
    @objc private func redoAction()  { canvas.redo(); updateButtonStates() }
    @objc private func clearAction() { canvas.clear(); updateButtonStates() }

    @objc private func doneAction() {
        // 点击 Done：一键保存到桌面并复制到剪贴板，随后优雅地关闭窗口
        let exported = canvas.exportAsImage()
        ScreenCaptureEngine.shared.copyToClipboard(exported)
        
        let path = (AppSettings.shared.screenshotSavePath as NSString).expandingTildeInPath
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent("截图 \(fmt.string(from: Date())).png")
        
        do {
            try ScreenCaptureEngine.shared.saveScreenshot(exported, to: fileURL.path)
        } catch {
            print("自动保存失败: \(error)")
        }
        self.close()
    }

    @objc private func cancelAction() {
        self.close()
    }

    @objc private func copyAction() {
        let exported = canvas.exportAsImage()
        ScreenCaptureEngine.shared.copyToClipboard(exported)

        // 短暂高亮 Done 按钮为绿色以示成功
        let originalColor = doneButton.layer?.backgroundColor
        doneButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        doneButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.doneButton.layer?.backgroundColor = originalColor
            self?.doneButton.title = "Done"
        }
    }

    @objc private func shareAction() {
        let exported = canvas.exportAsImage()
        let picker   = NSSharingServicePicker(items: [exported])
        picker.show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .minY)
    }

    // MARK: - 更新撤销/重做按钮状态
    private func updateButtonStates() {
        undoButton.alphaValue = canvas.canUndo ? 1.0 : 0.35
        redoButton.alphaValue = canvas.canRedo ? 1.0 : 0.35
    }

    // MARK: AnnotationCanvasDelegate
    func canvasDidChange(_ canvas: AnnotationCanvas) {
        updateButtonStates()
    }

    // MARK: - 键盘快捷键
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // ⌘Z 撤销
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) {
                redoAction()
            } else {
                undoAction()
            }
            return
        }
        // ⌘C 复制
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copyAction(); return
        }
        // 回车键 Done
        if event.keyCode == 36 { // Enter
            doneAction(); return
        }

        // 工具快捷键（不含修饰键时）
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            super.keyDown(with: event)
            return
        }

        if let char = event.charactersIgnoringModifiers?.uppercased(),
           let tool = AnnotationToolType.allCases.first(where: { $0.shortcutKey == char }) {
            selectTool(tool)
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - 颜色快选色块

private class ColorSwatch: NSView {
    private let color: NSColor
    private weak var parent: AnnotationEditorWindow?
    private var isHovered = false

    init(color: NSColor, parent: AnnotationEditorWindow) {
        self.color = color
        self.parent = parent
        super.init(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius    = 9 // 完美正圆
        layer?.masksToBounds   = true
        
        widthAnchor.constraint(equalToConstant: 18).isActive  = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
        
        updateHighlightState(selectedColor: parent.canvas.currentColor)
        
        // 创建 Tracking Area 以便在 Hover 时实现放大
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateHighlightState(selectedColor: NSColor) {
        // 如果当前颜色与母窗口选择颜色匹配，应用粗白环描边
        if color == selectedColor {
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor.white.cgColor
        } else {
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.35).cgColor
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        // 放大微动效
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().frame = self.frame.insetBy(dx: -1.5, dy: -1.5)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().frame = CGRect(x: self.frame.midX - 9, y: self.frame.midY - 9, width: 18, height: 18)
        }
    }

    override func mouseDown(with event: NSEvent) {
        parent?.setColor(color)
    }
}
