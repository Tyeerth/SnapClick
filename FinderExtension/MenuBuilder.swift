import Cocoa
import FinderSync
import UniformTypeIdentifiers

enum MenuBuilder {

    static func buildMenu(for menuKind: FIMenuKind, target: AnyObject) -> NSMenu {
        resetActionData()
        let menu = NSMenu(title: "")

        let hasSelection = (menuKind != .contextualMenuForContainer)
        let isContainer  = (menuKind == .contextualMenuForContainer)

        // 打开常用目录（仅在点击空白处时显示）
        if isContainer, let favItem = makeOpenFavDirItem(target: target) {
            menu.addItem(favItem)
        }

        menu.addItem(makeNewFileItem(target: target))

        if let termItem = makeOpenInTerminalItem(target: target) {
            menu.addItem(termItem)
        }

        // 空白处右键：拷贝当前目录的完整路径
        if isContainer {
            menu.addItem(makeCopyCurrentDirPathItem(target: target))
        }

        // 编辑器 / IDE 类工具（无论是空白处还是选中文件都显示）
        let devItems = makeDevToolItems(target: target)
        if !devItems.isEmpty {
            let devMenu = NSMenuItem(title: "用其他软件打开", action: nil, keyEquivalent: "")
            devMenu.image = sfSymbol("square.grid.2x2", size: 14)
            let devSub = NSMenu(title: "用其他软件打开")
            devItems.forEach { devSub.addItem($0) }
            devMenu.submenu = devSub
            menu.addItem(devMenu)
        }

        if hasSelection {
            menu.addItem(makeFavoriteDirsItem(target: target))
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

    /// 打开常用目录（带文件夹真实图标）—仅在空白处右键时显示
    private static func makeOpenFavDirItem(target: AnyObject) -> NSMenuItem? {
        let dirs = cachedFavoriteDirectories()
        guard !dirs.isEmpty else { return nil }

        let item = NSMenuItem(title: "打开常用目录", action: nil, keyEquivalent: "")
        item.image = sfSymbol("folder.fill.badge.plus", size: 14)

        let subMenu = NSMenu(title: "打开常用目录")
        for dir in dirs {
            let name = dir["name"] ?? ""
            let path = dir["path"] ?? ""
            guard !path.isEmpty else { continue }

            let mi = NSMenuItem(
                title: name,
                action: #selector(FinderSyncExtension.openFavoriteDirectory(_:)),
                keyEquivalent: ""
            )
            mi.target = target
            MenuBuilder.setRepresentedObject(path, for: mi)

            // 优先使用主 App 预热好的真实文件夹图标 Data，
            // 命中失败时回退到 SF Symbol（不再调用 icon(forFile:)）
            if let img = cachedDirectoryIcon(for: path) {
                mi.image = img
            } else {
                mi.image = sfSymbol("folder", size: 14)
            }

            subMenu.addItem(mi)
        }

        item.submenu = subMenu
        return item
    }

    private static func makeOpenInTerminalItem(target: AnyObject) -> NSMenuItem? {
        let item = NSMenuItem(title: "在终端中打开", action: #selector(FinderSyncExtension.openInTerminal(_:)), keyEquivalent: "")
        item.target = target
        item.image = sfSymbol("terminal.fill", size: 14)
        MenuBuilder.setRepresentedObject("com.apple.Terminal", for: item)
        return item
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
        let item = NSMenuItem(title: "拷贝路径", action: #selector(FinderSyncExtension.copyPath(_:)), keyEquivalent: "")
        item.target = target
        item.image = sfSymbol("link", size: 14)
        MenuBuilder.setRepresentedObject("full", for: item)
        return item
    }

    /// 空白处右键：拷贝当前目录的完整路径
    private static func makeCopyCurrentDirPathItem(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(
            title: "拷贝当前目录路径",
            action: #selector(FinderSyncExtension.copyTargetDirectoryPath(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.image = sfSymbol("link", size: 14)
        MenuBuilder.setRepresentedObject("full", for: item)
        return item
    }

    private static func makeDevToolItems(target: AnyObject) -> [NSMenuItem] {
        let tools = cachedDevTools()
        var items: [NSMenuItem] = []
        for tool in tools {
            let name = tool["name"] ?? "开发工具"
            let bundleID = tool["bundleID"] ?? ""
            let mi = NSMenuItem(title: name, action: #selector(FinderSyncExtension.openWithDevTool(_:)), keyEquivalent: "")
            mi.target = target
            MenuBuilder.setRepresentedObject(bundleID, for: mi)
            // 优先使用主 App 预热好的应用图标 Data，
            // 不再调用 urlForApplication / icon(forFile:)（会触发 TCC）
            if let img = cachedDevToolIcon(for: bundleID) {
                mi.image = img
            } else {
                mi.image = sfSymbol("app.badge", size: 14)
            }
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

    /// 从 SharedStore 读取常用目录列表
    private static func cachedFavoriteDirectories() -> [[String: String]] {
        struct FavDir: Codable { var id: String; var name: String; var path: String }
        let ud = AppGroup.defaults
        guard let data = ud.data(forKey: "favoriteDirectories"),
              let decoded = try? JSONDecoder().decode([FavDir].self, from: data),
              !decoded.isEmpty else {
            // 回退默认目录
            let home = NSHomeDirectory()
            return [
                ["name": "桌面",   "path": "\(home)/Desktop"],
                ["name": "文稿",   "path": "\(home)/Documents"],
                ["name": "下载",   "path": "\(home)/Downloads"],
                ["name": "图片",   "path": "\(home)/Pictures"],
            ]
        }
        return decoded.map { ["name": $0.name, "path": $0.path] }
    }


    private static func fileTypeIcon(ext: String) -> NSImage? {
        // 优先读取主 App 预热好的图标 Data（避免每次 NSWorkspace.icon(for:) 同步调用）
        if let data = IconCache.fileTypeIconData(for: ext),
           let img = NSImage(data: data) {
            img.size = NSSize(width: 16, height: 16)
            return img
        }
        // 冷启动场景：主 App 还没来得及预热，回退到 SF Symbol 占位
        return sfSymbol("doc.text", size: 14)
    }

    private static func sfSymbol(_ name: String, size: CGFloat = 14) -> NSImage? {
        return cachedSFSymbol(name, size: size)
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

    // MARK: - 图标内存缓存（NSCache）
    // SharedStore 的 PNG Data 在同一次右键中可能被多次引用（NSCache 按需懒加载），
    // 命中失败时再去读 SharedStore，并写回 NSCache；冷启动时如果主 App 还没预热，
    // 也由 NSCache 兜底。finderMenuAssetsDidChange 通知会清空所有缓存。

    private static let devToolIconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    private static let directoryIconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    private static let sfSymbolCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 128
        return c
    }()

    /// 收到资源变更通知时清空所有内存图标缓存
    static func clearInMemoryIconCaches() {
        devToolIconCache.removeAllObjects()
        directoryIconCache.removeAllObjects()
        sfSymbolCache.removeAllObjects()
    }

    private static func cachedDevToolIcon(for bundleID: String) -> NSImage? {
        let key = bundleID as NSString
        if let cached = devToolIconCache.object(forKey: key) {
            return cached
        }
        guard let data = IconCache.devToolIconData(for: bundleID),
              let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        devToolIconCache.setObject(img, forKey: key)
        return img
    }

    private static func cachedDirectoryIcon(for path: String) -> NSImage? {
        let key = path as NSString
        if let cached = directoryIconCache.object(forKey: key) {
            return cached
        }
        guard let data = IconCache.directoryIconData(for: path),
              let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        directoryIconCache.setObject(img, forKey: key)
        return img
    }

    private static func cachedSFSymbol(_ name: String, size: CGFloat) -> NSImage? {
        let key = "\(name)@\(Int(size))" as NSString
        if let cached = sfSymbolCache.object(forKey: key) {
            return cached
        }
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        img.size = NSSize(width: size, height: size)
        sfSymbolCache.setObject(img, forKey: key)
        return img
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
