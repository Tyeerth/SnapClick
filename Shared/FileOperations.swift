import Cocoa
import CryptoKit
import AppKit
import ApplicationServices

class FileOperations {

    static let shared = FileOperations()

    private let appGroupID = "group.com.snapclick.shared"
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
            if ext == "docx" || ext == "xlsx" || ext == "pptx" {
                if let officeData = Self.minimalOfficeData(ext: ext) {
                    try officeData.write(to: finalURL)
                } else {
                    try Data().write(to: finalURL)
                }
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
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            showAlert(title: "打开失败", message: "未检测到已安装此应用，请确认已在 Mac 上安装该程序。")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(items, withApplicationAt: appURL, configuration: config, completionHandler: nil)
    }

    func openInTerminal(directory: URL, terminalBundleID: String) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID) != nil else {
            showAlert(title: "打开终端失败", message: "未找到对应的终端程序（\(terminalBundleID)）。")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", terminalBundleID, directory.path]
        do {
            try process.run()
        } catch {
            showAlert(title: "打开终端失败", message: "无法启动终端程序：\(error.localizedDescription)")
        }
    }

    func airDrop(items: [URL]) {
        guard !items.isEmpty else { return }
        DispatchQueue.main.async {
            if let service = NSSharingService(named: .sendViaAirDrop) {
                service.perform(withItems: items)
            }
        }
    }

    private static func minimalOfficeData(ext: String) -> Data? {
        let contentType: String
        switch ext {
        case "docx":
            contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx":
            contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "pptx":
            contentType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        default:
            return nil
        }

        var data = Data()
        let zip = ZipWriter()
        zip.addEntry(name: "[Content_Types].xml", data: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="\(contentType)"/>
        </Types>
        """.data(using: .utf8)!, to: &data)

        zip.addEntry(name: "_rels/.rels", data: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """.data(using: .utf8)!, to: &data)

        let mainPart: String
        switch ext {
        case "docx":
            mainPart = "word/document.xml"
        case "xlsx":
            mainPart = "xl/workbook.xml"
        case "pptx":
            mainPart = "ppt/presentation.xml"
        default:
            mainPart = "word/document.xml"
        }

        let mainData: Data
        switch ext {
        case "docx":
            mainData = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body><w:p><w:r><w:t></w:t></w:r></w:p></w:body>
            </w:document>
            """.data(using: .utf8)!
        case "xlsx":
            mainData = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
            </workbook>
            """.data(using: .utf8)!
        case "pptx":
            mainData = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <p:sldIdLst/>
            </p:presentation>
            """.data(using: .utf8)!
        default:
            mainData = Data()
        }

        zip.addEntry(name: mainPart, data: mainData, to: &data)
        zip.finish(to: &data)
        return data
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

private final class ZipWriter {
    private struct Entry {
        let name: String
        let data: Data
        let offset: UInt32
        let crc32: UInt32
    }

    private var entries: [Entry] = []

    func addEntry(name: String, data: Data, to output: inout Data) {
        let offset = UInt32(output.count)
        let crc = crc32(data)

        output.append(localFileHeader(name: name, data: data, crc32: crc))
        output.append(data)

        entries.append(Entry(name: name, data: data, offset: offset, crc32: crc))
    }

    func finish(to output: inout Data) {
        let centralDirOffset = UInt32(output.count)

        for entry in entries {
            output.append(centralDirectoryHeader(entry: entry))
        }

        let centralDirSize = UInt32(output.count) - centralDirOffset
        let commentLen: UInt16 = 0

        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        eocd.append(contentsOf: [0x00, 0x00])
        eocd.append(contentsOf: [0x00, 0x00])
        eocd.append(uint16: UInt16(entries.count))
        eocd.append(uint16: UInt16(entries.count))
        eocd.append(uint32: centralDirSize)
        eocd.append(uint32: centralDirOffset)
        eocd.append(uint16: commentLen)

        output.append(eocd)
    }

    private func localFileHeader(name: String, data: Data, crc32: UInt32) -> Data {
        let nameData = name.data(using: .utf8)!
        var header = Data()
        header.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        header.append(uint16: 20)
        header.append(uint16: 0)
        header.append(uint16: 0)
        header.append(uint16: 0)
        header.append(uint32: crc32)
        header.append(uint32: UInt32(data.count))
        header.append(uint32: UInt32(data.count))
        header.append(uint16: UInt16(nameData.count))
        header.append(uint16: 0)
        header.append(nameData)
        return header
    }

    private func centralDirectoryHeader(entry: Entry) -> Data {
        let nameData = entry.name.data(using: .utf8)!
        var header = Data()
        header.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        header.append(uint16: 20)
        header.append(uint16: 20)
        header.append(uint16: 0)
        header.append(uint16: 0)
        header.append(uint16: 0)
        header.append(uint32: entry.crc32)
        header.append(uint32: UInt32(entry.data.count))
        header.append(uint32: UInt32(entry.data.count))
        header.append(uint16: UInt16(nameData.count))
        header.append(uint16: 0)
        header.append(uint16: 0)
        header.append(uint16: 0)
        header.append(uint16: 0)
        header.append(uint32: 0)
        header.append(uint32: entry.offset)
        header.append(nameData)
        return header
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table: [UInt32] = {
            var t = [UInt32](repeating: 0, count: 256)
            for i in 0..<256 {
                var c = UInt32(i)
                for _ in 0..<8 {
                    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
                }
                t[i] = c
            }
            return t
        }()
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
