import Cocoa
import FinderSync

class FinderSyncExtension: FIFinderSync {

    override init() {
        let home = NSHomeDirectory()
        var dirs: Set<URL> = [
            URL(fileURLWithPath: home),
            URL(fileURLWithPath: "/Volumes"),
            URL(fileURLWithPath: "/"),
        ]
        for sub in ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public"] {
            dirs.insert(URL(fileURLWithPath: "\(home)/\(sub)"))
        }
        FIFinderSyncController.default().directoryURLs = dirs
        super.init()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        return MenuBuilder.buildMenu(for: menuKind, target: self)
    }

    var finderSelectedItems: [URL] {
        return FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    var finderTargetDirectory: URL? {
        let selected = finderSelectedItems
        if let firstDir = selected.first(where: { isDirectory($0) }) {
            return firstDir
        }
        if let firstFile = selected.first {
            return firstFile.deletingLastPathComponent()
        }
        return FIFinderSyncController.default().targetedURL()
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }

    // MARK: - 进程间通讯（IPC）
    // 使用「命名剪贴板 (Named NSPasteboard)」作为 IPC 数据通道：
    // · 无需 App Group 权限，在沙盒与非沙盒进程之间天然互通
    // · 不会触发 kCFPreferencesAnyUser 相关警告
    // · Darwin 通知用于唤醒主应用，命名剪贴板用于传递数据

    private static let ipcPasteboardName = NSPasteboard.Name("com.snapclick.app.ipc")
    private static let ipcNotificationName = "com.snapclick.app.findercommand" as CFString

    private func sendCommand(_ command: String, selectedItems: [URL], targetDir: URL?, representedObject: Any?) {
        var payload: [String: Any] = [
            "cmd":   command,
            "items": selectedItems.map { $0.path },
            "dir":   targetDir?.path ?? "",
            "ts":    Date().timeIntervalSince1970
        ]
        if let dict = representedObject as? [String: String] {
            payload["dict"] = dict
        } else if let str = representedObject as? String {
            payload["str"] = str
        }

        // 序列化为 JSON 写入命名剪贴板
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        let pb = NSPasteboard(name: Self.ipcPasteboardName)
        pb.clearContents()
        pb.setString(jsonStr, forType: .string)

        // 通过 Darwin 通知唤醒主应用读取剪贴板数据
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(Self.ipcNotificationName),
            nil, nil, true
        )
    }

    @objc func createNewFile(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("createNewFile", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func cutFiles(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("cutFiles", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func copyFiles(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("copyFiles", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func pasteFiles(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("pasteFiles", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func moveToDirectory(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("moveToDirectory", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func copyToDirectory(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("copyToDirectory", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func copyPath(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("copyPath", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func copyTargetDirectoryPath(_ sender: NSMenuItem) {
        guard let dir = finderTargetDirectory else { return }
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        // 复用 copyPath 命令：把当前目录作为唯一 item，
        // 主 App 端的 FileOperations.copyPath 会按 path 字段拷贝到剪贴板
        sendCommand("copyPath", selectedItems: [dir], targetDir: dir, representedObject: obj)
    }

    @objc func computeHash(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("computeHash", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func openWithDevTool(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("openWithDevTool", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func openInTerminal(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("openInTerminal", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func airDrop(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("airDrop", selectedItems: finderSelectedItems, targetDir: finderTargetDirectory, representedObject: obj)
    }

    @objc func openFavoriteDirectory(_ sender: NSMenuItem) {
        let obj = MenuBuilder.getRepresentedObject(for: sender.tag)
        sendCommand("openDirectory", selectedItems: [], targetDir: finderTargetDirectory, representedObject: obj)
    }
}
