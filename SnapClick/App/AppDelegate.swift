import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = NSImage(named: "AppIcon")

        statusBarController = StatusBarController(appDelegate: self)
        _ = PermissionManager.shared
        HotkeyManager.shared.registerAll()
        cacheInstalledApps()
        setupFinderCommandObserver()

        let settings = AppSettings.shared
        if settings.isFirstLaunch {
            showWelcomeWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func openSettings() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: MainWindow()
                .environmentObject(ColorPickerEngine.shared)
                .environmentObject(PinWindowManager.shared))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SnapClick 设置"
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cacheInstalledApps() {
        let terminals = [
            (name: "Terminal", bundleID: "com.apple.Terminal"),
            (name: "iTerm2", bundleID: "com.googlecode.iterm2"),
            (name: "Warp", bundleID: "dev.warp.Warp-Stable")
        ]

        let devTools = [
            (name: "VS Code", bundleID: "com.microsoft.VSCode"),
            (name: "Cursor", bundleID: "anysphere.cursor"),
            (name: "Xcode", bundleID: "com.apple.dt.Xcode"),
            (name: "Sublime Text", bundleID: "com.sublimetext.4"),
            (name: "Sublime Text 3", bundleID: "com.sublimetext.3")
        ]

        let installedTerminals = terminals.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
        let installedDevTools = devTools.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }

        let ud = AppGroup.defaults
        if let data = try? JSONEncoder().encode(installedTerminals.map { ["name": $0.name, "bundleID": $0.bundleID] }) {
            ud.set(data, forKey: "cachedInstalledTerminals")
        }
        if let data = try? JSONEncoder().encode(installedDevTools.map { ["name": $0.name, "bundleID": $0.bundleID] }) {
            ud.set(data, forKey: "cachedInstalledDevTools")
        }
        ud.synchronize()
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
        let pb = NSPasteboard(name: NSPasteboard.Name("com.snapclick.app.ipc"))
        guard let json = pb.string(forType: .string),
              let data = json.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = payload["cmd"] as? String
        else { return }

        pb.clearContents()

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
                
            case "airDrop":
                FileOperations.shared.airDrop(items: selectedURLs)
                
            default:
                break
            }
        }
    }

    private func showWelcomeWindow() {
        let hostingView = NSHostingView(rootView: WelcomeView {
            AppSettings.shared.isFirstLaunch = false
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 SnapClick".localized
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        welcomeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
