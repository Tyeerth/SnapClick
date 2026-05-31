import SwiftUI

@main
struct SnapClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            MainWindow()
        }
    }
}
