import Cocoa
import CryptoKit
import AppKit
import ApplicationServices

class FileOperations {

    static let shared = FileOperations()

    private let clipboardKey = "finderClipboard"
    private let clipboardModeKey = "finderClipboardMode"

    private init() {}

    @discardableResult
    func createNewFile(dict: [String: String], in destURL: URL) -> URL? {
        guard let ext = dict["ext"] else { return nil }

        let rawName = dict["name"] ?? "新建文件"
        let baseName = rawName.hasSuffix(".\(ext)") ? String(rawName.dropLast(ext.count + 1)) : rawName
        let content = dict["content"] ?? ""

        let finalURL = uniqueURL(in: destURL, name: baseName, ext: ext)

        do {
            if let templateURL = Self.officeTemplateURL(for: ext) {
                try FileManager.default.copyItem(at: templateURL, to: finalURL)
            } else {
                try content.write(to: finalURL, atomically: true, encoding: .utf8)
            }
            return finalURL
        } catch {
            showAlert(title: "新建文件失败", message: "无法在 \(destURL.path) 创建文件。错误：\(error.localizedDescription)")
            return nil
        }
    }

    func cutFiles(items: [URL]) {
        saveToClipboard(items: items, mode: "cut")
    }

    func copyFiles(items: [URL]) {
        saveToClipboard(items: items, mode: "copy")
    }

    private func saveToClipboard(items: [URL], mode: String) {
        let ud = AppGroup.defaults
        let paths = items.map { $0.path }
        ud.set(paths, forKey: clipboardKey)
        ud.set(mode, forKey: clipboardModeKey)
        ud.synchronize()
    }

    func pasteFiles(to destURL: URL) {
        let ud = AppGroup.defaults
        guard let paths = ud.stringArray(forKey: clipboardKey), !paths.isEmpty else {
            showAlert(title: "粘贴失败", message: "剪贴板为空，请先执行剪切或复制。")
            return
        }

        let mode = ud.string(forKey: clipboardModeKey) ?? "copy"
        let isCut = (mode == "cut")
        let fm = FileManager.default
        var errors: [String] = []

        for path in paths {
            let srcURL = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: srcURL.path) else {
                errors.append("源文件不存在: \(srcURL.lastPathComponent)")
                continue
            }

            let dstURL = uniqueURL(in: destURL, name: srcURL.deletingPathExtension().lastPathComponent, ext: srcURL.pathExtension)
            do {
                if isCut {
                    try fm.moveItem(at: srcURL, to: dstURL)
                } else {
                    try fm.copyItem(at: srcURL, to: dstURL)
                }
            } catch {
                errors.append("\(srcURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if isCut && errors.isEmpty {
            ud.removeObject(forKey: clipboardKey)
            ud.synchronize()
        }

        if !errors.isEmpty {
            showAlert(title: isCut ? "移动部分文件失败" : "复制部分文件失败", message: errors.joined(separator: "\n"))
        }
    }

    func moveOrCopy(items: [URL], destPath: String, isCopy: Bool) {
        if destPath == "__choose__" {
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = isCopy ? "复制到此处" : "移动到此处"
                
                if panel.runModal() == .OK, let chosenURL = panel.url {
                    self.performMoveOrCopy(items: items, to: chosenURL, isCopy: isCopy)
                }
            }
        } else {
            let destURL = URL(fileURLWithPath: destPath)
            performMoveOrCopy(items: items, to: destURL, isCopy: isCopy)
        }
    }

    private func performMoveOrCopy(items: [URL], to destBase: URL, isCopy: Bool) {
        let fm = FileManager.default
        var errors: [String] = []

        for src in items {
            let dst = uniqueURL(in: destBase, name: src.deletingPathExtension().lastPathComponent, ext: src.pathExtension)
            do {
                if isCopy {
                    try fm.copyItem(at: src, to: dst)
                } else {
                    try fm.moveItem(at: src, to: dst)
                }
            } catch {
                errors.append("\(src.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            showAlert(title: isCopy ? "复制部分失败" : "移动部分失败", message: errors.joined(separator: "\n"))
        }
    }

    func copyPath(items: [URL], kind: String) {
        guard !items.isEmpty else { return }
        let result: String
        
        switch kind {
        case "filename":
            result = items.map { $0.lastPathComponent }.joined(separator: "\n")
        case "url":
            result = items.map { $0.absoluteString }.joined(separator: "\n")
        default:
            result = items.map { $0.path }.joined(separator: "\n")
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(result, forType: .string)
    }

    func computeHash(items: [URL], algo: String) {
        let files = items.filter { !isDirectory($0) }
        guard !files.isEmpty else {
            showAlert(title: "计算哈希失败", message: "请选择有效的文件（文件夹不支持计算哈希）。")
            return
        }

        var results: [String] = []
        for file in files {
            if let hash = calculateHash(url: file, algo: algo) {
                results.append("\(file.lastPathComponent) (\(algo.uppercased())): \(hash)")
            } else {
                results.append("\(file.lastPathComponent): 计算失败")
            }
        }

        let resultText = results.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(resultText, forType: .string)

        showAlert(title: "哈希计算成功", message: "计算结果已成功复制到剪贴板！\n\n\(resultText)")
    }

    private func calculateHash(url: URL, algo: String) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        
        switch algo.lowercased() {
        case "md5":
            let hash = Insecure.MD5.hash(data: data)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        case "sha1":
            let hash = Insecure.SHA1.hash(data: data)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        case "sha256":
            let hash = SHA256.hash(data: data)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        default:
            return nil
        }
    }

    func openWithDevTool(items: [URL], bundleID: String) {
        guard !items.isEmpty else { return }
        // 通过 bundleID 反查已知路径（避开 NSWorkspace.urlForApplication 触发的 TCC 提示）
        let knownPaths: [String: String] = [
            "com.microsoft.VSCode":            "/Applications/Visual Studio Code.app",
            "com.todesktop.230313mzl4w4u92":    "/Applications/Cursor.app",
            "com.apple.dt.Xcode":               "/Applications/Xcode.app",
            "com.sublimetext.4":                "/Applications/Sublime Text.app",
            "com.sublimetext.3":                "/Applications/Sublime Text.app"
        ]
        guard let appPath = knownPaths[bundleID],
              Self.appExists(at: appPath) else {
            showAlert(title: "打开失败", message: "未检测到已安装此应用，请确认已在 Mac 上安装该程序。")
            return
        }
        let appURL = URL(fileURLWithPath: appPath)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(items, withApplicationAt: appURL, configuration: config, completionHandler: nil)
    }

    func openInTerminal(directory: URL, terminalBundleID: String) {
        let knownPaths: [String: String] = [
            "com.apple.Terminal":         "/System/Applications/Utilities/Terminal.app",
            "com.googlecode.iterm2":      "/Applications/iTerm.app",
            "dev.warp.Warp-Stable":       "/Applications/Warp.app"
        ]
        guard let appPath = knownPaths[terminalBundleID],
              Self.appExists(at: appPath) else {
            showAlert(title: "打开终端失败", message: "未找到对应的终端程序（\(terminalBundleID)）。")
            return
        }
        let appURL = URL(fileURLWithPath: appPath)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([directory], withApplicationAt: appURL, configuration: config, completionHandler: { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.showAlert(title: "打开终端失败", message: "无法启动终端程序：\(error.localizedDescription)")
                }
            }
        })
    }

    private static func appExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func airDrop(items: [URL]) {
        guard !items.isEmpty else { return }
        DispatchQueue.main.async {
            if let service = NSSharingService(named: .sendViaAirDrop) {
                service.perform(withItems: items)
            }
        }
    }

    private static func officeTemplateURL(for ext: String) -> URL? {
        let supportedExts = ["docx", "xlsx", "pptx", "pages", "key", "numbers"]
        guard supportedExts.contains(ext) else { return nil }
        return Bundle.main.url(forResource: "template", withExtension: ext)
    }

    static func revealInFinder(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-R", url.path]
        try? process.run()
    }

    static func revealAndRenameInFinder(_ url: URL) {
        revealInFinder(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard AXIsProcessTrusted() else { return }
            let returnKeyCode: CGKeyCode = 36
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: false) else { return }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }

    private func uniqueURL(in directory: URL, name: String, ext: String) -> URL {
        let fm = FileManager.default
        let extensionSuffix = ext.isEmpty ? "" : ".\(ext)"
        var finalURL = directory.appendingPathComponent("\(name)\(extensionSuffix)")
        var counter = 1
        while fm.fileExists(atPath: finalURL.path) {
            finalURL = directory.appendingPathComponent("\(name) \(counter)\(extensionSuffix)")
            counter += 1
        }
        return finalURL
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}

