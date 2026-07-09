import SwiftUI

@main
struct SnapClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appNavigation = AppNavigation.shared

    var body: some Scene {
        Window("SnapClick 设置", id: "main") {
            MainWindow()
                .environmentObject(appNavigation)
                .environmentObject(ColorPickerEngine.shared)
                .environmentObject(PinWindowManager.shared)
                .frame(minWidth: 820, idealWidth: 880, minHeight: 540, idealHeight: 600)
        }
        .defaultSize(width: 880, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…".localized) {
                    appNavigation.openMain()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("欢迎使用 SnapClick".localized, id: "welcome") {
            WelcomeView {
                AppSettings.shared.isFirstLaunch = false
                appNavigation.openMain()
            }
            .frame(minWidth: 600, idealWidth: 600, minHeight: 560, idealHeight: 560)
        }
        .defaultSize(width: 600, height: 560)
        .windowResizability(.contentSize)
    }
}
