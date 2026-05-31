import Foundation
import AppKit

enum NamingRule: String {
    case standard = "Standard"
    case customPrefix = "CustomPrefix"
}

class ScreenshotSettings: ObservableObject {
    static let shared = ScreenshotSettings()
    
    private init() {}
    
    var saveDirectory: String {
        get { AppSettings.shared.screenshotSavePath }
        set { AppSettings.shared.screenshotSavePath = newValue }
    }
    
    var format: ScreenshotFormat {
        get { ScreenshotFormat(rawValue: AppSettings.shared.screenshotFormat) ?? .png }
        set { AppSettings.shared.screenshotFormat = newValue.rawValue }
    }
    
    var enableRoundedCorners: Bool {
        get { AppSettings.shared.screenshotAddRoundCorner }
        set { AppSettings.shared.screenshotAddRoundCorner = newValue }
    }
    
    var cornerRadius: CGFloat {
        get { CGFloat(AppSettings.shared.screenshotCornerRadius) }
        set { AppSettings.shared.screenshotCornerRadius = Double(newValue) }
    }
    
    var enableShadow: Bool {
        get { AppSettings.shared.screenshotAddShadow }
        set { AppSettings.shared.screenshotAddShadow = newValue }
    }
    
    var namingRule: NamingRule {
        get { .standard }
    }
    
    var customPrefix: String {
        get { "截图" }
    }
}
