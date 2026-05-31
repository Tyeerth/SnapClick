import Foundation

enum AppGroup {
    static let id = "group.com.snapclick.shared"

    static let defaults: UserDefaults = {
        guard let suite = UserDefaults(suiteName: id) else {
            fatalError("无法初始化 App Group UserDefaults，请检查 entitlements 中的 App Group 配置")
        }
        return suite
    }()
}
