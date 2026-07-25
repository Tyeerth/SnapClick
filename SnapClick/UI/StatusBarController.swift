import AppKit

// MARK: - StatusBarController

/// 菜单栏图标控制器
/// 管理 NSStatusItem 的图标显示、菜单构建和菜单项事件响应
@MainActor
final class StatusBarController: NSObject {

    // MARK: 私有属性

    private var statusItem: NSStatusItem
    private weak var appDelegate: AppDelegate?
    
    private var recordingTimer: Timer?
    private var flashState: Bool = false
    private var audioRecordingHUD: AudioRecordingHUDWindow?
    /// 录音前参数面板（保留强引用，防止 ARC 过早释放）
    private var audioPreLaunchPanel: AudioRecordingPreLaunchPanel?

    // MARK: 初始化

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupIcon()
        setupMenu()
        updateVisibility()

        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .appLanguageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: .showInMenuBarDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRecordingStart), name: .recordingDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRecordingStop), name: .recordingDidStop, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRecordingStart), name: .audioRecordingDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRecordingStop), name: .audioRecordingDidStop, object: nil)
        // 热键路径触发弹出参数面板
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowAudioPreLaunchPanel), name: .showAudioPreLaunchPanel, object: nil)
    }
    
    @objc private func handleShowAudioPreLaunchPanel() {
        showAudioPreLaunchPanel()
    }

    @objc private func defaultsChanged() {
        setupMenu()
    }

    @objc private func languageChanged() {
        setupMenu()
        setupIcon()
    }

    @objc private func visibilityChanged() {
        updateVisibility()
    }

    private func updateVisibility() {
        statusItem.isVisible = AppSettings.shared.showInMenuBar
    }

    // MARK: 图标设置

    private func setupIcon() {
        guard let button = statusItem.button else { return }

        // 使用 SF Symbol 作为菜单栏图标 (camera.viewfinder)
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        guard let icon = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "SnapClick"
        )?.withSymbolConfiguration(config) else { return }
        icon.isTemplate = true  // 自动适应深色/浅色菜单栏
        button.image = icon
        button.toolTip = "SnapClick".localized
    }

    // MARK: 菜单构建

    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let settings = AppSettings.shared

        func parse(_ str: String) -> (shortcut: String, modifiers: NSEvent.ModifierFlags) {
            let sanitized = str.lowercased().replacingOccurrences(of: "+", with: " ")
            let parts = sanitized.split(separator: " ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var modifiers: NSEvent.ModifierFlags = []
            var key = ""
            for part in parts {
                switch part {
                case "ctrl", "control", "⌃": modifiers.insert(.control)
                case "shift", "⇧": modifiers.insert(.shift)
                case "alt", "option", "opt", "⌥": modifiers.insert(.option)
                case "cmd", "command", "⌘": modifiers.insert(.command)
                default: key = part
                }
            }
            // 针对方向键和特殊键做转换（NSMenuItem 的快捷键格式）
            switch key {
            case "enter": key = "\r"
            case "space": key = " "
            case "tab": key = "\t"
            case "esc", "escape": key = "\u{1b}"
            case "↑": key = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
            case "↓": key = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
            case "←": key = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
            case "→": key = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
            default: break
            }
            return (key, modifiers)
        }

        // ── 截图组 ──────────────────────────────────────────────
        // 智能截图（区域 + 窗口合一）：拖拽选区 / 点击截取悬停窗口
        let areaT = parse(settings.hotkeyAreaScreenshot)
        let smartItem = makeItem(
            title: "智能截图".localized,
            symbolName: "viewfinder",
            shortcut: areaT.shortcut,
            modifiers: areaT.modifiers,
            action: #selector(smartScreenshot)
        )
        menu.addItem(smartItem)

        // 选区截图（仅拖拽框选）
        let regionT = parse(settings.hotkeyRegionScreenshot)
        let regionItem = makeItem(
            title: "选区截图".localized,
            symbolName: "crop",
            shortcut: regionT.shortcut,
            modifiers: regionT.modifiers,
            action: #selector(regionScreenshot)
        )
        menu.addItem(regionItem)

        // 窗口截图（仅点击截取窗口）
        let winT = parse(settings.hotkeyWindowScreenshot)
        let winItem = makeItem(
            title: "窗口截图".localized,
            symbolName: "macwindow",
            shortcut: winT.shortcut,
            modifiers: winT.modifiers,
            action: #selector(windowScreenshot)
        )
        menu.addItem(winItem)

        let longT = parse(settings.hotkeyLongScreenshot)
        let longItem = makeItem(
            title: "长截图".localized,
            symbolName: "arrow.up.and.down",
            shortcut: longT.shortcut,
            modifiers: longT.modifiers,
            action: #selector(longScreenshot)
        )
        menu.addItem(longItem)

        menu.addItem(.separator())

        // ── 屏幕录制组 ───────────────────────────────────────────
        let recAreaT = parse(settings.hotkeyRecordArea)
        let recAreaItem = makeItem(
            title: "选区录制".localized,
            symbolName: "record.circle",
            shortcut: recAreaT.shortcut,
            modifiers: recAreaT.modifiers,
            action: #selector(recordArea)
        )
        menu.addItem(recAreaItem)

        let recScreenT = parse(settings.hotkeyRecordScreen)
        let recScreenItem = makeItem(
            title: "全屏录制".localized,
            symbolName: "display",
            shortcut: recScreenT.shortcut,
            modifiers: recScreenT.modifiers,
            action: #selector(recordScreen)
        )
        menu.addItem(recScreenItem)

        let recWindowItem = makeItem(
            title: "窗口录制".localized,
            symbolName: "macwindow",
            shortcut: "",
            modifiers: [],
            action: #selector(recordWindow)
        )
        menu.addItem(recWindowItem)

        menu.addItem(.separator())

        // ── 音频录制组 ───────────────────────────────────────────
        if !AudioRecordingEngine.shared.isRecording {
            let startAudioT = parse(settings.hotkeyAudioRecord)
            let startAudioItem = makeItem(
                title: "开始录音".localized,
                symbolName: "mic.fill",
                shortcut: startAudioT.shortcut,
                modifiers: startAudioT.modifiers,
                action: #selector(startAudioRecording)
            )
            menu.addItem(startAudioItem)
        } else {
            let stopAudioT = parse(settings.hotkeyStopAudioRecord)
            let stopAudioItem = makeItem(
                title: "停止录音".localized,
                symbolName: "stop.fill",
                shortcut: stopAudioT.shortcut,
                modifiers: stopAudioT.modifiers,
                action: #selector(stopAudioRecording)
            )
            menu.addItem(stopAudioItem)
        }

        menu.addItem(.separator())



        // ── 取色 & 贴图 ─────────────────────────────────────────
        let colorT = parse(settings.hotkeyColorPicker)
        let colorItem = makeItem(
            title: "屏幕取色".localized,
            symbolName: "eyedropper",
            shortcut: colorT.shortcut,
            modifiers: colorT.modifiers,
            action: #selector(colorPicker)
        )
        menu.addItem(colorItem)

        let pinT = parse(settings.hotkeyPin)
        let pinItem = makeItem(
            title: "贴图".localized,
            symbolName: "pin",
            shortcut: pinT.shortcut,
            modifiers: pinT.modifiers,
            action: #selector(pinImage)
        )
        menu.addItem(pinItem)

        menu.addItem(.separator())

        // ── 设置 & 退出 ─────────────────────────────────────────
        let settingsItem = makeItem(
            title: "设置…".localized,
            symbolName: "gearshape",
            shortcut: ",",
            modifiers: [.command],
            action: #selector(openSettings)
        )
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = makeItem(
            title: "退出 SnapClick".localized,
            symbolName: "power",
            shortcut: "q",
            modifiers: [.command],
            action: #selector(quitApp)
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
        
        // 将所有 target 指向 self
        for item in menu.items {
            item.target = self
        }
    }

    // MARK: 私有工具方法

    /// 创建带 SF Symbol 图标的菜单项
    private func makeItem(
        title: String,
        symbolName: String,
        shortcut: String,
        modifiers: NSEvent.ModifierFlags,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.isEnabled = true

        // 设置 SF Symbol 小图标
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            var config = NSImage.SymbolConfiguration(scale: .small)
            config = config.applying(.init(paletteColors: [.labelColor]))
            item.image = image.withSymbolConfiguration(config)
        }
        return item
    }

    // MARK: 菜单动作

    /// 智能截图（区域 + 窗口合一）：拖拽选区 / 点击截取悬停窗口
    @objc private func smartScreenshot() {
        Task { @MainActor in
            do {
                try await ScreenCaptureEngine.shared.capture()
            } catch ScreenCaptureError.permissionDenied {
                showPermissionAlert(for: .screenRecording)
            } catch {
                print("[StatusBar] 智能截图出错: \(error)")
            }
        }
    }

    /// 选区截图（仅拖拽框选）
    @objc private func regionScreenshot() {
        Task { @MainActor in
            do {
                try await ScreenCaptureEngine.shared.captureArea()
            } catch ScreenCaptureError.permissionDenied {
                showPermissionAlert(for: .screenRecording)
            } catch {
                print("[StatusBar] 选区截图出错: \(error)")
            }
        }
    }

    /// 窗口截图（仅点击截取窗口）
    @objc private func windowScreenshot() {
        Task { @MainActor in
            do {
                try await ScreenCaptureEngine.shared.captureWindow()
            } catch ScreenCaptureError.permissionDenied {
                showPermissionAlert(for: .screenRecording)
            } catch {
                print("[StatusBar] 窗口截图出错: \(error)")
            }
        }
    }

    @objc private func longScreenshot() {
        Task { @MainActor in
            do {
                try await ScreenCaptureEngine.shared.captureLongScreenshot()
            } catch ScreenCaptureError.permissionDenied {
                showPermissionAlert(for: .screenRecording)
            } catch {
                print("[StatusBar] 长截图出错: \(error)")
            }
        }
    }

    @objc private func colorPicker() {
        ColorPickerEngine.shared.startPicking()
    }

    @objc private func pinImage() {
        let pb = NSPasteboard.general
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            PinWindowManager.shared.pin(image: image)
        } else {
            let alert = NSAlert()
            alert.messageText = "剪贴板未包含图片".localized
            alert.informativeText = "请先使用 ⌘C 复制一张图片或使用截图功能，随后即可在此直接贴图。".localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的".localized)
            alert.runModal()
        }
    }

    @objc private func openSettings() {
        appDelegate?.openSettings()
    }

    @objc private func recordArea() {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            showPermissionAlert(for: .screenRecording)
            return
        }
        // 退出菜单后稍延启动，避免菜单动画与选区覆盖
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Task { @MainActor in
                do {
                    try await ScreenRecordingEngine.shared.startAreaRecording()
                } catch {
                    print("[状态栏] 选区录制出错: \(error)")
                }
            }
        }
    }

    @objc private func recordScreen() {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            showPermissionAlert(for: .screenRecording)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Task { @MainActor in
                do {
                    try await ScreenRecordingEngine.shared.startFullScreenRecording()
                } catch {
                    print("[状态栏] 全屏录制出错: \(error)")
                }
            }
        }
    }

    @objc private func recordWindow() {
        guard PermissionManager.shared.hasScreenRecordingPermission else {
            showPermissionAlert(for: .screenRecording)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Task { @MainActor in
                do {
                    try await ScreenRecordingEngine.shared.startWindowRecording()
                } catch {
                    print("[状态栏] 窗口录制出错: \(error)")
                }
            }
        }
    }


    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 权限提示

    private enum PermissionKind {
        case screenRecording
        case accessibility
    }

    private func showPermissionAlert(for kind: PermissionKind) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch kind {
        case .screenRecording:
            alert.messageText = "需要屏幕录制权限".localized
            alert.informativeText = "请在系统设置 → 隐私与安全性 → 屏幕录制中授权 SnapClick。".localized
            alert.addButton(withTitle: "去设置".localized)
            alert.addButton(withTitle: "取消".localized)
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.shared.requestScreenRecordingPermission()
            }
        case .accessibility:
            alert.messageText = "需要辅助功能权限".localized
            alert.informativeText = "请在系统设置 → 隐私与安全性 → 辅助功能中授权 SnapClick。".localized
            alert.addButton(withTitle: "去设置".localized)
            alert.addButton(withTitle: "取消".localized)
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.shared.requestAccessibilityPermission()
            }
        }
    }
    
    // MARK: - 录屏控制状态与菜单更新
    
    private func setupRecordingMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        
        let engine = ScreenRecordingEngine.shared
        let statusText = engine.isPaused ? "录制已暂停".localized : "正在录制屏幕...".localized
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(.separator())
        
        // 暂停/继续
        let pauseTitle = engine.isPaused ? "继续录制".localized : "暂停录制".localized
        let pauseSymbol = engine.isPaused ? "play.fill" : "pause.fill"
        let pauseItem = makeItem(
            title: pauseTitle,
            symbolName: pauseSymbol,
            shortcut: "",
            modifiers: [],
            action: #selector(toggleRecordingPause)
        )
        menu.addItem(pauseItem)
        
        // 停止并保存
        let stopItem = makeItem(
            title: "停止并保存".localized,
            symbolName: "stop.fill",
            shortcut: "",
            modifiers: [],
            action: #selector(stopRecordingAndSave)
        )
        menu.addItem(stopItem)
        
        // 取消录制
        let cancelItem = makeItem(
            title: "取消录制".localized,
            symbolName: "trash",
            shortcut: "",
            modifiers: [],
            action: #selector(cancelRecording)
        )
        menu.addItem(cancelItem)
        
        self.statusItem.menu = menu
        
        for item in menu.items {
            item.target = self
        }
    }
    
    @objc private func handleRecordingStart() {
        setupRecordingMenu()
        
        recordingTimer?.invalidate()
        // 使用 .common mode 注册 Timer，确保菜单打开（.eventTracking mode）期间计时器仍正常触发
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(updateRecordingStatus), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        recordingTimer = timer
        
        updateRecordingStatus()
    }
    
    @objc private func handleRecordingStop() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if let button = statusItem.button {
            button.title = ""
            setupIcon()
        }
        
        setupMenu()
    }
    
    @objc private func updateRecordingStatus() {
        guard let button = statusItem.button else { return }
        let engine = ScreenRecordingEngine.shared
        
        let durationStr = formatDuration(engine.recordingDuration)
        button.title = " " + durationStr
        
        flashState.toggle()
        
        // 设置图标
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        if engine.isPaused {
            // 暂停状态使用 pause.circle.fill，红色常亮不闪烁
            if let pauseImage = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: nil) {
                button.image = pauseImage.withSymbolConfiguration(config)
            }
        } else {
            // 录制状态使用 dot.circle.fill 和 circle 交替闪烁
            let symbolName = flashState ? "dot.circle.fill" : "circle"
            if let recImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                button.image = recImage.withSymbolConfiguration(config)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    @objc private func toggleRecordingPause() {
        let engine = ScreenRecordingEngine.shared
        if engine.isPaused {
            engine.resumeRecording()
        } else {
            engine.pauseRecording()
        }
        setupRecordingMenu()
    }
    
    @objc private func stopRecordingAndSave() {
        Task { @MainActor in
            do {
                let fileURL = try await ScreenRecordingEngine.shared.stopRecording()
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } catch {
                print("[状态栏] 停止录屏失败: \(error)")
            }
        }
    }
    
    @objc private func cancelRecording() {
        let alert = NSAlert()
        alert.messageText = "确定要取消录制吗？".localized
        alert.informativeText = "取消录制将不会保存本次录制的视频文件，并且无法恢复。".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定取消".localized)
        alert.addButton(withTitle: "继续录制".localized)

        if alert.runModal() == .alertFirstButtonReturn {
            Task { @MainActor in
                do {
                    try await ScreenRecordingEngine.shared.cancelRecording()
                } catch {
                    print("[状态栏] 取消录像失败: \(error)")
                }
            }
        }
    }

    // MARK: - 音频录音菜单动作

    @objc private func startAudioRecording() {
        // 菜单消失动画结束后再弹面板，避免层级冲突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.showAudioPreLaunchPanel()
        }
    }

    /// 弹出录音前参数选择面板
    private func showAudioPreLaunchPanel() {
        // 如果面板已存在（如快捷键连按），先关闭旧的
        audioPreLaunchPanel?.orderOut(nil)
        audioPreLaunchPanel = nil

        let panel = AudioRecordingPreLaunchPanel()

        panel.onRecord = { [weak self] in
            self?.audioPreLaunchPanel = nil
            self?.doStartAudioRecording()
        }
        panel.onCancel = { [weak self] in
            self?.audioPreLaunchPanel = nil
        }

        self.audioPreLaunchPanel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.center()
    }

    /// 真正执行录音启动（面板确认后调用）
    private func doStartAudioRecording() {
        Task { @MainActor in
            do {
                try await AudioRecordingEngine.shared.startRecording()
            } catch AudioRecordingError.permissionDenied {
                self.showAudioPermissionAlert()
            } catch AudioRecordingError.conflictWithScreenRecording {
                let alert = NSAlert()
                alert.messageText = "无法开始音频录音".localized
                alert.informativeText = "屏幕录制进行中，请先停止屏幕录制再开始音频录音。".localized
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好的".localized)
                alert.runModal()
            } catch {
                print("[状态栏] 开始录音失败: \(error)")
                let alert = NSAlert()
                alert.messageText = "无法开始录音".localized
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好的".localized)
                alert.runModal()
            }
        }
    }

    @objc private func stopAudioRecording() {
        Task { @MainActor in
            do {
                let fileURL = try await AudioRecordingEngine.shared.stopRecording()
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } catch {
                print("[状态栏] 停止录音失败: \(error)")
            }
        }
    }

    @objc private func toggleAudioPause() {
        let engine = AudioRecordingEngine.shared
        if engine.isPaused {
            engine.resumeRecording()
        } else {
            engine.pauseRecording()
        }
        setupAudioRecordingMenu()
    }

    @objc private func cancelAudioRecording() {
        let alert = NSAlert()
        alert.messageText = "确定要取消录音吗？".localized
        alert.informativeText = "取消录音将不会保存本次录制的音频文件，并且无法恢复。".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定取消".localized)
        alert.addButton(withTitle: "继续录音".localized)

        if alert.runModal() == .alertFirstButtonReturn {
            Task { @MainActor in
                do {
                    try await AudioRecordingEngine.shared.cancelRecording()
                } catch {
                    print("[状态栏] 取消录音失败: \(error)")
                }
            }
        }
    }

    private func showAudioPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要麦克风权限".localized
        alert.informativeText = "请授予 SnapClick 麦克风权限以录制音频，请到「系统设置 → 隐私与安全性 → 麦克风」中打开 SnapClick。".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "授权".localized)
        alert.addButton(withTitle: "取消".localized)
        if alert.runModal() == .alertFirstButtonReturn {
            // requestMicrophonePermission 内部会按 authorizationStatus 分流：
            // .notDetermined → 弹系统授权框；.denied → 跳系统设置页
            PermissionManager.shared.requestMicrophonePermission()
        }
    }

    // MARK: - 音频录音 HUD 与动态菜单

    private func showAudioHUD() {
        if audioRecordingHUD == nil {
            let hud = AudioRecordingHUDWindow(
                onPauseResume: { [weak self] in self?.toggleAudioPause() },
                onStop: { [weak self] in self?.stopAudioRecording() },
                onCancel: { [weak self] in self?.cancelAudioRecording() }
            )
            audioRecordingHUD = hud
        }
        audioRecordingHUD?.orderFrontRegardless()
    }

    private func hideAudioHUD() {
        audioRecordingHUD?.orderOut(nil)
        audioRecordingHUD = nil
    }

    private func setupAudioRecordingMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let engine = AudioRecordingEngine.shared
        let statusText = engine.isPaused ? "录音已暂停".localized : "正在录音...".localized
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let pauseTitle = engine.isPaused ? "继续录音".localized : "暂停录音".localized
        let pauseSymbol = engine.isPaused ? "play.fill" : "pause.fill"
        let pauseItem = makeItem(
            title: pauseTitle,
            symbolName: pauseSymbol,
            shortcut: "",
            modifiers: [],
            action: #selector(toggleAudioPause)
        )
        menu.addItem(pauseItem)

        let stopItem = makeItem(
            title: "停止并保存".localized,
            symbolName: "stop.fill",
            shortcut: "",
            modifiers: [],
            action: #selector(stopAudioRecording)
        )
        menu.addItem(stopItem)

        let cancelItem = makeItem(
            title: "取消录音".localized,
            symbolName: "trash",
            shortcut: "",
            modifiers: [],
            action: #selector(cancelAudioRecording)
        )
        menu.addItem(cancelItem)

        self.statusItem.menu = menu

        for item in menu.items {
            item.target = self
        }
    }

    @objc private func handleAudioRecordingStart() {
        showAudioHUD()
        setupAudioRecordingMenu()

        recordingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(updateAudioRecordingStatus), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        recordingTimer = timer

        updateAudioRecordingStatus()
    }

    @objc private func handleAudioRecordingStop() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        if let button = statusItem.button {
            button.title = ""
            setupIcon()
        }

        hideAudioHUD()
        setupMenu()
    }

    @objc private func updateAudioRecordingStatus() {
        guard let button = statusItem.button else { return }
        let engine = AudioRecordingEngine.shared

        let durationStr = formatDuration(engine.recordingDuration)
        button.title = " " + durationStr

        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let symbolName = engine.isPaused ? "pause.circle.fill" : "mic.fill"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            button.image = img.withSymbolConfiguration(config)
        }
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if ScreenRecordingEngine.shared.isRecording {
            setupRecordingMenu()
        } else if AudioRecordingEngine.shared.isRecording {
            setupAudioRecordingMenu()
        }
    }
}


