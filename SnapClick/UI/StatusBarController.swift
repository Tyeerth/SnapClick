import AppKit

// MARK: - StatusBarController

/// 菜单栏图标控制器
/// 管理 NSStatusItem 的图标显示、菜单构建和菜单项事件响应
@MainActor
final class StatusBarController: NSObject {

    // MARK: 私有属性

    private var statusItem: NSStatusItem
    private weak var appDelegate: AppDelegate?

    // MARK: 初始化

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        // 创建固定宽度的状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        setupIcon()
        setupMenu()
        
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    @objc private func defaultsChanged() {
        setupMenu()
    }

    // MARK: 图标设置

    private func setupIcon() {
        guard let button = statusItem.button else { return }

        // 使用 SF Symbol 作为菜单栏图标 (camera.viewfinder)
        let icon = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "SnapClick"
        )
        icon?.isTemplate = true  // 自动适应深色/浅色菜单栏
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
        let areaT = parse(settings.hotkeyAreaScreenshot)
        let areaItem = makeItem(
            title: "区域截图",
            symbolName: "crop",
            shortcut: areaT.shortcut,
            modifiers: areaT.modifiers,
            action: #selector(areaScreenshot)
        )
        menu.addItem(areaItem)

        let longT = parse(settings.hotkeyLongScreenshot)
        let longItem = makeItem(
            title: "长截图",
            symbolName: "arrow.up.and.down",
            shortcut: longT.shortcut,
            modifiers: longT.modifiers,
            action: #selector(longScreenshot)
        )
        menu.addItem(longItem)

        menu.addItem(.separator())



        // ── 取色 & 贴图 ─────────────────────────────────────────
        let colorT = parse(settings.hotkeyColorPicker)
        let colorItem = makeItem(
            title: "屏幕取色",
            symbolName: "eyedropper",
            shortcut: colorT.shortcut,
            modifiers: colorT.modifiers,
            action: #selector(colorPicker)
        )
        menu.addItem(colorItem)

        let pinT = parse(settings.hotkeyPin)
        let pinItem = makeItem(
            title: "贴图",
            symbolName: "pin",
            shortcut: pinT.shortcut,
            modifiers: pinT.modifiers,
            action: #selector(pinImage)
        )
        menu.addItem(pinItem)

        menu.addItem(.separator())

        // ── 设置 & 退出 ─────────────────────────────────────────
        let settingsItem = makeItem(
            title: "设置…",
            symbolName: "gearshape",
            shortcut: ",",
            modifiers: [.command],
            action: #selector(openSettings)
        )
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = makeItem(
            title: "退出 SnapClick",
            symbolName: "power",
            shortcut: "q",
            modifiers: [.command],
            action: #selector(quitApp)
        )
        menu.addItem(quitItem)

        statusItem.menu = menu

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

    @objc private func areaScreenshot() {
        Task { @MainActor in
            do {
                try await ScreenCaptureEngine.shared.captureArea()
            } catch ScreenCaptureError.permissionDenied {
                showPermissionAlert(for: .screenRecording)
            } catch {
                print("[StatusBar] 区域截图出错: \(error)")
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
            alert.messageText = "剪贴板未包含图片"
            alert.informativeText = "请先使用 ⌘C 复制一张图片或使用截图功能，随后即可在此直接贴图。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            alert.runModal()
        }
    }

    @objc private func openSettings() {
        appDelegate?.openSettings()
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
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "请在系统设置 → 隐私与安全性 → 屏幕录制中授权 SnapClick。"
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.shared.requestScreenRecordingPermission()
            }
        case .accessibility:
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "请在系统设置 → 隐私与安全性 → 辅助功能中授权 SnapClick。"
            alert.addButton(withTitle: "去设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.shared.requestAccessibilityPermission()
            }
        }
    }
}

