import AppKit
import Foundation
import UniformTypeIdentifiers

/// 跨进程共享的图标 Data 缓存。
///
/// 主 App 在启动 / 数据变更时预加载各类图标并写入 SharedStore，
/// FinderExtension 在沙盒中直接读取 Data → NSImage，避免每次右键
/// 触发 NSWorkspace.urlForApplication / icon(forFile:) 等会触发
/// TCC 权限检查的同步 I/O。
///
/// 存储格式：单个 JSON 字典，键为图标 key（bundleID / path / ext），
/// 值为 PNG Data 的 Base64 字符串。
enum IconCache {

    // MARK: - 存储键

    private static let devToolIconsKey   = "cachedDevToolIcons"      // value: {bundleID: base64}
    private static let directoryIconsKey = "cachedFavoriteDirIcons" // value: {path: base64}
    private static let fileTypeIconsKey  = "cachedFileTypeIcons"     // value: {ext: base64}
    private static let devToolPathsKey   = "cachedDevToolPaths"      // value: {bundleID: appPath}

    // MARK: - 公共接口（主 App 侧写入）

    /// 预热所有图标缓存：dev tool 图标 + 常用目录图标 + 内置文件类型图标
    static func preheat(
        devTools: [(name: String, bundleID: String)],
        favoriteDirectoryPaths: [String],
        fileTemplateExts: [String]
    ) {
        let ws = NSWorkspace.shared
        let store = AppGroup.defaults

        // 1. dev tool：app 路径 + 图标
        var devIconMap: [String: String] = [:]
        var pathMap: [String: String] = [:]
        for tool in devTools {
            if let appURL = ws.urlForApplication(withBundleIdentifier: tool.bundleID) {
                pathMap[tool.bundleID] = appURL.path
                if let png = pngBase64(forFile: appURL.path) {
                    devIconMap[tool.bundleID] = png
                }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: devIconMap) {
            store.set(data, forKey: devToolIconsKey)
        }
        if let data = try? JSONSerialization.data(withJSONObject: pathMap) {
            store.set(data, forKey: devToolPathsKey)
        }

        // 2. 常用目录：真实文件夹图标
        var dirIconMap: [String: String] = [:]
        for path in favoriteDirectoryPaths {
            if let png = pngBase64(forFile: path) {
                dirIconMap[path] = png
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dirIconMap) {
            store.set(data, forKey: directoryIconsKey)
        }

        // 3. 文件类型图标（按扩展名）
        var typeIconMap: [String: String] = [:]
        for ext in fileTemplateExts {
            if let png = fileTypeIconBase64(ext: ext) {
                typeIconMap[ext] = png
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: typeIconMap) {
            store.set(data, forKey: fileTypeIconsKey)
        }
    }

    // MARK: - 公共接口（FinderExtension 侧读取）

    /// 读取 dev tool 的 app 路径（替代 urlForApplication）
    static func devToolPath(for bundleID: String) -> String? {
        guard let data = AppGroup.defaults.data(forKey: devToolPathsKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict[bundleID]
    }

    /// 读取 dev tool 的图标 Data
    static func devToolIconData(for bundleID: String) -> Data? {
        return iconData(forKey: bundleID, storageKey: devToolIconsKey)
    }

    /// 读取常用目录的图标 Data
    static func directoryIconData(for path: String) -> Data? {
        return iconData(forKey: path, storageKey: directoryIconsKey)
    }

    /// 读取文件类型的图标 Data
    static func fileTypeIconData(for ext: String) -> Data? {
        return iconData(forKey: ext.lowercased(), storageKey: fileTypeIconsKey)
    }

    // MARK: - 私有方法

    private static func iconData(forKey key: String, storageKey: String) -> Data? {
        guard let data = AppGroup.defaults.data(forKey: storageKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let base64 = dict[key] else {
            return nil
        }
        return Data(base64Encoded: base64)
    }

    /// 将指定路径的图标序列化为 PNG Data 的 Base64
    private static func pngBase64(forFile path: String) -> String? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 64, height: 64)
        guard let tiff = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png.base64EncodedString()
    }

    /// 将指定扩展名的系统图标序列化为 PNG Data 的 Base64
    private static func fileTypeIconBase64(ext: String) -> String? {
        let uttype = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: uttype)
        icon.size = NSSize(width: 64, height: 64)
        guard let tiff = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png.base64EncodedString()
    }
}
