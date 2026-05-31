import Cocoa
import FinderSync
import UniformTypeIdentifiers

enum MenuBuilder {

    private static let appGroupID = "group.com.snapclick.shared"

    static func buildMenu(for menuKind: FIMenuKind, target: AnyObject) -> NSMenu {
        resetActionData()
        let menu = NSMenu(title: "")

        let hasSelection = (menuKind != .contextualMenuForContainer)

        menu.addItem(makeNewFileItem(target: target))

        if let termItem = makeOpenInTerminalItem(target: target) {
            menu.addItem(termItem)
        }

        if hasSelection {
            menu.addItem(.separator())
            menu.addItem(makeFavoriteDirsItem(target: target))
            menu.addItem(.separator())
            menu.addItem(makeCopyPathItem(target: target))
        }

        return menu
    }

    private static func makeNewFileItem(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        item.image = sfSymbol("doc.badge.plus", size: 14)

        let subMenu = NSMenu(title: "新建文件")
        
        var templates: [TemplateEntry] = []
        let ud = AppGroup.defaults
        if let data = ud.data(forKey: "fileTemplates"),
           let decoded = try? JSONDecoder().decode([TemplateEntry].self, from: data) {
            templates = decoded.filter { $0.isEnabled }
        } else if let customList = ud.array(forKey: "customTemplates") as? [[String: String]] {
            templates = customList.compactMap { dict -> TemplateEntry? in
                guard let name = dict["name"], let ext = dict["ext"] else { return nil }
                return TemplateEntry(name: name, ext: ext, isEnabled: true, defaultContent: dict["content"])
            }
        }

        if templates.isEmpty {
            templates = defaultTemplates()
        }

        for tpl in templates {
            let mi = NSMenuItem(
                title: tpl.name,
                action: #selector(FinderSyncExtension.createNewFile(_:)),
                keyEquivalent: ""
            )
            mi.target = target
            MenuBuilder.setRepresentedObject([
                "ext": tpl.ext,
                "name": tpl.name,
                "content": tpl.defaultContent ?? ""
            ], for: mi)
            mi.image = fileTypeIcon(ext: tpl.ext)
            subMenu.addItem(mi)
        }

        item.submenu = subMenu
        return item
    }

    private static func makeOpenInTerminalItem(target: AnyObject) -> NSMenuItem? {
        let terminals = cachedTerminals()

        guard !terminals.isEmpty else {
            let item = NSMenuItem(title: "在终端中打开", action: #selector(FinderSyncExtension.openInTerminal(_:)), keyEquivalent: "")
            item.target = target
            MenuBuilder.setRepresentedObject("com.apple.Terminal", for: item)
            item.image = sfSymbol("terminal.fill", size: 14)
            return item
        }

        if terminals.count == 1 {
            let term = terminals[0]
            let item = NSMenuItem(title: "在 \(term["name"] ?? "Terminal") 中打开", action: #selector(FinderSyncExtension.openInTerminal(_:)), keyEquivalent: "")
            item.target = target
            MenuBuilder.setRepresentedObject(term["bundleID"] ?? "com.apple.Terminal", for: item)
            item.image = sfSymbol("terminal.fill", size: 14)
            return item
        } else {
            let item = NSMenuItem(title: "在终端中打开", action: nil, keyEquivalent: "")
            item.image = sfSymbol("terminal.fill", size: 14)

            let subMenu = NSMenu(title: "在终端中打开")
            for term in terminals {
                let name = term["name"] ?? "Terminal"
                let bundleID = term["bundleID"] ?? "com.apple.Terminal"
                let mi = NSMenuItem(title: name, action: #selector(FinderSyncExtension.openInTerminal(_:)), keyEquivalent: "")
                mi.target = target
                MenuBuilder.setRepresentedObject(bundleID, for: mi)
                mi.image = sfSymbol("terminal.fill", size: 14)
                subMenu.addItem(mi)
            }
            item.submenu = subMenu
            return item
        }
    }

    private static func makeFavoriteDirsItem(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "常用目录", action: nil, keyEquivalent: "")
        item.image = sfSymbol("folder.fill", size: 14)

        let subMenu = NSMenu(title: "常用目录")

        var dirs: [FavoriteDirectoryEntry] = []
        let ud = AppGroup.defaults
        if let data = ud.data(forKey: "favoriteDirectories"),
           let decoded = try? JSONDecoder().decode([FavoriteDirectoryEntry].self, from: data) {
            dirs = decoded
        } else {
            let home = NSHomeDirectory()
            dirs = [
                FavoriteDirectoryEntry(id: "1", name: "桌面", path: "\(home)/Desktop"),
                FavoriteDirectoryEntry(id: "2", name: "文稿", path: "\(home)/Documents"),
                FavoriteDirectoryEntry(id: "3", name: "下载", path: "\(home)/Downloads"),
                FavoriteDirectoryEntry(id: "4", name: "图片", path: "\(home)/Pictures")
            ]
        }

        let copySub = NSMenu(title: "复制到")
        for dir in dirs {
            let mi = NSMenuItem(title: dir.name, action: #selector(FinderSyncExtension.copyToDirectory(_:)), keyEquivalent: "")
            mi.target = target
            MenuBuilder.setRepresentedObject(dir.path, for: mi)
            mi.image = sfSymbol("folder", size: 14)
            copySub.addItem(mi)
        }
        copySub.addItem(.separator())
        let chooseCopy = NSMenuItem(title: "选择其他文件夹...", action: #selector(FinderSyncExtension.copyToDirectory(_:)), keyEquivalent: "")
        chooseCopy.target = target
        MenuBuilder.setRepresentedObject("__choose__", for: chooseCopy)
        chooseCopy.image = sfSymbol("ellipsis", size: 14)
        copySub.addItem(chooseCopy)

        let copyItem = NSMenuItem(title: "复制到", action: nil, keyEquivalent: "")
        copyItem.image = sfSymbol("doc.on.doc.fill", size: 14)
        copyItem.submenu = copySub
        subMenu.addItem(copyItem)

        let moveSub = NSMenu(title: "移动到")
        for dir in dirs {
            let mi = NSMenuItem(title: dir.name, action: #selector(FinderSyncExtension.moveToDirectory(_:)), keyEquivalent: "")
            mi.target = target
            MenuBuilder.setRepresentedObject(dir.path, for: mi)
            mi.image = sfSymbol("folder", size: 14)
            moveSub.addItem(mi)
        }
        moveSub.addItem(.separator())
        let chooseMove = NSMenuItem(title: "选择其他文件夹...", action: #selector(FinderSyncExtension.moveToDirectory(_:)), keyEquivalent: "")
        chooseMove.target = target
        MenuBuilder.setRepresentedObject("__choose__", for: chooseMove)
        chooseMove.image = sfSymbol("ellipsis", size: 14)
        moveSub.addItem(chooseMove)

        let moveItem = NSMenuItem(title: "移动到", action: nil, keyEquivalent: "")
        moveItem.image = sfSymbol("arrow.up.right.and.arrow.down.left.rectangle", size: 14)
        moveItem.submenu = moveSub
        subMenu.addItem(moveItem)

        item.submenu = subMenu
        return item
    }

    private static func makeCopyPathItem(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "拷贝路径", action: nil, keyEquivalent: "")
        item.image = sfSymbol("link", size: 14)

        let subMenu = NSMenu(title: "拷贝路径")

        let options = [
            (title: "完整路径", kind: "full"),
            (title: "仅文件名", kind: "filename"),
            (title: "File URL", kind: "url")
        ]

        for opt in options {
            let mi = NSMenuItem(title: opt.title, action: #selector(FinderSyncExtension.copyPath(_:)), keyEquivalent: "")
            mi.target = target
            MenuBuilder.setRepresentedObject(opt.kind, for: mi)
            mi.image = sfSymbol("doc.on.clipboard", size: 14)
            subMenu.addItem(mi)
        }

        item.submenu = subMenu
        return item
    }

    private static func makeDevToolItems(target: AnyObject) -> [NSMenuItem] {
        let tools = cachedDevTools()
        var items: [NSMenuItem] = []
        for tool in tools {
            let name = tool["name"] ?? "开发工具"
            let bundleID = tool["bundleID"] ?? ""
            let mi = NSMenuItem(title: "用 \(name) 打开", action: #selector(FinderSyncExtension.openWithDevTool(_:)), keyEquivalent: "")
            mi.target = target
            MenuBuilder.setRepresentedObject(bundleID, for: mi)
            mi.image = sfSymbol("hammer.fill", size: 14)
            items.append(mi)
        }
        return items
    }

    private static func makeCutItem(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "剪切文件", action: #selector(FinderSyncExtension.cutFiles(_:)), keyEquivalent: "")
        item.target = target
        item.image = sfSymbol("scissors", size: 14)
        return item
    }

    private static func makeHashItem(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "查看哈希", action: nil, keyEquivalent: "")
        item.image = sfSymbol("lock.fill", size: 14)

        let subMenu = NSMenu(title: "查看哈希")
        let algos = ["MD5", "SHA-1", "SHA-256"]

        for algo in algos {
            let mi = NSMenuItem(title: algo, action: #selector(FinderSyncExtension.computeHash(_:)), keyEquivalent: "")
            mi.target = target
            MenuBuilder.setRepresentedObject(algo.lowercased().replacingOccurrences(of: "-", with: ""), for: mi)
            mi.image = sfSymbol("checkmark.seal", size: 14)
            subMenu.addItem(mi)
        }

        item.submenu = subMenu
        return item
    }

    private static func makeAirDropItem(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "隔空投送", action: #selector(FinderSyncExtension.airDrop(_:)), keyEquivalent: "")
        item.target = target
        item.image = sfSymbol("paperplane.fill", size: 14)
        return item
    }

    private static func cachedTerminals() -> [[String: String]] {
        let ud = AppGroup.defaults
        guard let data = ud.data(forKey: "cachedInstalledTerminals"),
              let decoded = try? JSONDecoder().decode([[String: String]].self, from: data),
              !decoded.isEmpty else {
            return [["name": "Terminal", "bundleID": "com.apple.Terminal"]]
        }
        return decoded
    }

    private static func cachedDevTools() -> [[String: String]] {
        let ud = AppGroup.defaults
        guard let data = ud.data(forKey: "cachedInstalledDevTools"),
              let decoded = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func fileTypeIcon(ext: String) -> NSImage? {
        if #available(macOS 12.0, *) {
            if let uttype = UTType(filenameExtension: ext) {
                let icon = NSWorkspace.shared.icon(for: uttype)
                icon.size = NSSize(width: 16, height: 16)
                return icon
            }
        }
        let icon = NSWorkspace.shared.icon(forFileType: ext)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private static func sfSymbol(_ name: String, size: CGFloat = 14) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.size = NSSize(width: size, height: size)
        return img
    }

    private static func defaultTemplates() -> [TemplateEntry] {
        return [
            TemplateEntry(name: "文本文档", ext: "txt", isEnabled: true, defaultContent: ""),
            TemplateEntry(name: "Markdown", ext: "md", isEnabled: true, defaultContent: "# 新建文档\n\n"),
            TemplateEntry(name: "Word 文档", ext: "docx", isEnabled: true, defaultContent: ""),
            TemplateEntry(name: "Excel 表格", ext: "xlsx", isEnabled: true, defaultContent: ""),
            TemplateEntry(name: "PPT 演示", ext: "pptx", isEnabled: true, defaultContent: "")
        ]
    }

    private static var actionData: [Int: Any] = [:]
    private static var nextTag = 1

    static func setRepresentedObject(_ obj: Any, for item: NSMenuItem) {
        let tag = nextTag
        item.tag = tag
        actionData[tag] = obj
        nextTag += 1
    }

    static func getRepresentedObject(for tag: Int) -> Any? {
        return actionData[tag]
    }

    static func resetActionData() {
        actionData.removeAll()
        nextTag = 1
    }
}

private struct FavoriteDirectoryEntry: Codable {
    var id: String
    var name: String
    var path: String
}

private struct TemplateEntry: Codable {
    var name: String
    var ext: String
    var isEnabled: Bool
    var defaultContent: String?
}
