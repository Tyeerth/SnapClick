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

    private static let ipcPasteboardName = NSPasteboard.Name("com.snapclick.app.ipc")

    private func sendCommand(_ command: String, selectedItems: [URL], targetDir: URL?, representedObject: Any?) {
        var payload: [String: Any] = [
            "cmd":   command,
            "items": selectedItems.map { $0.path },
            "dir":   targetDir?.path ?? ""
        ]
        if let dict = representedObject as? [String: String] {
            payload["dict"] = dict
        } else if let str = representedObject as? String {
            payload["str"] = str
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            let pb = NSPasteboard(name: Self.ipcPasteboardName)
            pb.clearContents()
            pb.setString(json, forType: .string)
        }

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("com.snapclick.app.findercommand" as CFString),
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
}
