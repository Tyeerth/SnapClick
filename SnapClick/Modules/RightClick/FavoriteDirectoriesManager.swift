import Foundation
import Combine

// MARK: - 数据模型

/// 单条收藏目录记录（与 FinderExtension/MenuBuilder 中的私有结构体保持字段一致）
struct FavoriteDirectory: Codable, Identifiable {
    var id: String
    var name: String
    var path: String

    init(name: String, path: String) {
        self.id   = UUID().uuidString
        self.name = name
        self.path = path
    }
}

// MARK: - 管理器

/// 常用目录管理器，负责在 App Group UserDefaults 中持久化收藏目录列表
/// Finder Extension 和主 App 通过同一 App Group 共享数据
final class FavoriteDirectoriesManager: ObservableObject {

    // MARK: - 单例
    static let shared = FavoriteDirectoriesManager()

    // MARK: - 常量
    private let appGroupID  = "group.com.snapclick.shared"
    private let storageKey  = "favoriteDirectories"

    // MARK: - 已发布属性
    @Published var favorites: [FavoriteDirectory] = []

    // MARK: - 内部属性
    private var userDefaults: UserDefaults?

    // MARK: - 初始化
    private init() {
        userDefaults = UserDefaults(suiteName: appGroupID)
        load()
    }

    // MARK: - 公共接口

    /// 添加一条收藏目录（如果路径已存在则忽略）
    func add(name: String, path: String) {
        guard !favorites.contains(where: { $0.path == path }) else { return }
        favorites.append(FavoriteDirectory(name: name, path: path))
        save()
    }

    /// 按 IndexSet 删除收藏目录
    func remove(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save()
    }

    /// 删除单条记录（按 ID）
    func remove(id: String) {
        favorites.removeAll { $0.id == id }
        save()
    }

    /// 重新排序
    func reorder(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// 更新某条记录的名称
    func rename(id: String, newName: String) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].name = newName
        save()
    }

    /// 强制从 App Group 重新加载（供 Finder Extension 调用）
    func reload() {
        load()
    }

    // MARK: - 私有方法

    private func load() {
        guard let ud = userDefaults,
              let data = ud.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FavoriteDirectory].self, from: data) else {
            // 首次启动写入默认收藏目录
            favorites = Self.defaultDirectories()
            save()
            return
        }
        favorites = decoded
    }

    private func save() {
        guard let ud = userDefaults,
              let encoded = try? JSONEncoder().encode(favorites) else { return }
        ud.set(encoded, forKey: storageKey)
        ud.synchronize()
    }

    /// 默认收藏目录列表（首次启动时写入）
    private static func defaultDirectories() -> [FavoriteDirectory] {
        let home = NSHomeDirectory()
        return [
            FavoriteDirectory(name: "桌面",   path: "\(home)/Desktop"),
            FavoriteDirectory(name: "文稿",   path: "\(home)/Documents"),
            FavoriteDirectory(name: "下载",   path: "\(home)/Downloads"),
            FavoriteDirectory(name: "图片",   path: "\(home)/Pictures"),
            FavoriteDirectory(name: "个人收藏", path: home),
        ]
    }
}
