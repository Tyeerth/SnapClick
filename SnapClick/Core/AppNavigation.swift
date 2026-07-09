import SwiftUI
import Combine

/// 全局导航协调器，让非 SwiftUI 入口（状态栏菜单、Dock 点击、IPC 回调）
/// 能触发 SwiftUI Window 打开。每次自增 request ID，监听端用
/// `.onReceive(appNavigation.$mainRequestID.dropFirst())` 捕获并调用
/// `@Environment(\.openWindow)`。
final class AppNavigation: ObservableObject {

    static let shared = AppNavigation()

    @Published private(set) var mainRequestID: UUID = UUID()
    @Published private(set) var welcomeRequestID: UUID = UUID()

    private init() {}

    func openMain() {
        mainRequestID = UUID()
    }

    func openWelcome() {
        welcomeRequestID = UUID()
    }
}
