import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = NSImage(named: "AppIcon")

        statusBarController = StatusBarController(appDelegate: self)
        _ = PermissionManager.shared
        HotkeyManager.shared.registerAll()
        setupFinderCommandObserver()
        handleFinderCommand()

        // 启动时立即同步已安装的终端/开发工具到 SharedStore，
        // 并预热常用目录 / 文件类型的图标 Data，
        // 确保 FinderExtension 的 MenuBuilder 每次右键都直接命中缓存，
        // 不再触发 NSWorkspace.urlForApplication / icon(forFile:) 等
        // 会触发 TCC 弹窗的同步 I/O 调用。
        preheatFinderMenuAssets()

        // 监听收藏目录 / 文件模板变更，刷新图标缓存
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFinderMenuAssetsChanged),
            name: .finderMenuAssetsDidChange,
            object: nil
        )

        // 初始化并监听程序坞图标状态
        updateActivationPolicy()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateActivationPolicy),
            name: .showInDockDidChange,
            object: nil
        )

        // 监听毛玻璃透明效果变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGlassEffectChanged),
            name: .enableGlassEffectDidChange,
            object: nil
        )

        let settings = AppSettings.shared
        if settings.isFirstLaunch {
            AppNavigation.shared.openWelcome()
        }
    }

    /// 将系统中已安装的终端 / 编辑器信息、常用目录 / 文件类型图标
    /// 全部预加载并写入 SharedStore，供沙盒内的 FinderExtension 直接读取。
    /// FinderExtension 之后不再调用任何会触发 TCC 的 NSWorkspace API。
    private func preheatFinderMenuAssets() {
        let terminalCandidates: [(name: String, bundleID: String)] = [
            ("Terminal",  "com.apple.Terminal"),
            ("iTerm2",    "com.googlecode.iterm2"),
        ]
        let editorCandidates: [(name: String, bundleID: String)] = [
            ("VS Code",      "com.microsoft.VSCode"),
            ("Xcode",        "com.apple.dt.Xcode"),
            ("Sublime Text", "com.sublimetext.4"),
            ("TextEdit",     "com.apple.TextEdit"),
        ]
        let devTools = terminalCandidates + editorCandidates

        let dirPaths = FavoriteDirectoriesManager.shared.favorites.map { $0.path }
        let exts = NewFileTemplateManager.shared.enabledTemplates.map { $0.ext.lowercased() }

        // 同步预热：启动时一次性完成，所有 I/O 都在主进程进行，
        // 不会在 FinderExtension 沙盒内触发 TCC 弹窗
        IconCache.preheat(
            devTools: devTools,
            favoriteDirectoryPaths: dirPaths,
            fileTemplateExts: exts
        )
    }

    @objc private func handleFinderMenuAssetsChanged() {
        preheatFinderMenuAssets()
    }

    @objc private func updateActivationPolicy() {
        let showInDock = AppSettings.shared.showInDock
        if showInDock {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func openSettings() {
        openMainWindow()
    }

    func closeSettings() {
        // SwiftUI Window 由系统管理，关闭交给主 App scene
    }

    private func openMainWindow() {
        let targetTitle = "SnapClick 设置"
        for window in NSApp.windows where window.title == targetTitle {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        AppNavigation.shared.openMain()
    }

    private func applyAppearance(to window: NSWindow?) {
        guard let window else { return }
        switch AppSettings.shared.appAppearance {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark":  window.appearance = NSAppearance(named: .darkAqua)
        default:      window.appearance = nil
        }
    }

    private func applyGlassEffect(to window: NSWindow?) {
        guard let window else { return }
        if AppSettings.shared.enableGlassEffect {
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        }
    }

    @objc private func handleGlassEffectChanged() {
        // SwiftUI Window 自带 .background 适配外观变化，无需手动通知
    }

    private func setupFinderCommandObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            center,
            observer,
            { (_, observer, name, _, _) in
                guard let observer = observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                delegate.handleFinderCommand()
            },
            "com.snapclick.app.findercommand" as CFString,
            nil,
            .deliverImmediately
        )
    }

    @objc private func handleFinderCommand() {
        // 从命名剪贴板读取命令（与 FinderSync.sendCommand 配套）
        let pb = NSPasteboard(name: NSPasteboard.Name("com.snapclick.app.ipc"))
        guard let jsonStr = pb.string(forType: .string),
              let data = jsonStr.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        // 读取后清空，避免重复处理
        pb.clearContents()

        processFinderPayload(payload)
    }

    private func processFinderPayload(_ payload: [String: Any]) {
        guard let command = payload["cmd"] as? String else { return }

        let selectedPaths    = payload["items"] as? [String] ?? []
        let targetDirStr     = payload["dir"] as? String ?? ""
        let representedDict  = payload["dict"] as? [String: String]
        let representedString = payload["str"] as? String

        let selectedURLs = selectedPaths.map { URL(fileURLWithPath: $0) }
        let targetURL: URL? = targetDirStr.isEmpty ? nil : URL(fileURLWithPath: targetDirStr)

        DispatchQueue.main.async {
            switch command {
            case "createNewFile":
                guard let dest = targetURL, let dict = representedDict else { return }
                if let createdURL = FileOperations.shared.createNewFile(dict: dict, in: dest) {
                    FileOperations.revealAndRenameInFinder(createdURL)
                }

            case "cutFiles":
                FileOperations.shared.cutFiles(items: selectedURLs)

            case "copyFiles":
                FileOperations.shared.copyFiles(items: selectedURLs)

            case "pasteFiles":
                guard let dest = targetURL else { return }
                FileOperations.shared.pasteFiles(to: dest)

            case "moveToDirectory":
                let destPath = representedString ?? "__choose__"
                FileOperations.shared.moveOrCopy(items: selectedURLs, destPath: destPath, isCopy: false)

            case "copyToDirectory":
                let destPath = representedString ?? "__choose__"
                FileOperations.shared.moveOrCopy(items: selectedURLs, destPath: destPath, isCopy: true)

            case "copyPath":
                let kind = representedString ?? "full"
                FileOperations.shared.copyPath(items: selectedURLs, kind: kind)

            case "computeHash":
                let algo = representedString ?? "sha256"
                FileOperations.shared.computeHash(items: selectedURLs, algo: algo)

            case "openWithDevTool":
                guard let bundleID = representedString else { return }
                FileOperations.shared.openWithDevTool(items: selectedURLs, bundleID: bundleID)

            case "openInTerminal":
                guard let dest = targetURL else { return }
                let terminalBundleID = representedString ?? "com.apple.Terminal"
                FileOperations.shared.openInTerminal(directory: dest, terminalBundleID: terminalBundleID)

            case "openDirectory":
                guard let path = representedString, !path.isEmpty else { return }
                NSWorkspace.shared.open(URL(fileURLWithPath: path))

            case "airDrop":
                FileOperations.shared.airDrop(items: selectedURLs)

            default:
                break
            }
        }
    }

}
