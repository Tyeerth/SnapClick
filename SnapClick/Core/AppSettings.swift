import SwiftUI

// MARK: - AppSettings

/// 全局应用设置
/// 使用 UserDefaults + @AppStorage 持久化，支持 SwiftUI 双向绑定
final class AppSettings: ObservableObject {

    // MARK: 单例

    static let shared = AppSettings()

    private init() {}

    // MARK: 截图设置

    /// 截图保存路径（默认桌面）
    @AppStorage("screenshotSavePath")
    var screenshotSavePath: String = "~/Desktop"

    /// 截图格式（PNG / JPG / TIFF / GIF / BMP）
    @AppStorage("screenshotFormat")
    var screenshotFormat: String = "PNG"

    /// 是否为截图添加圆角
    @AppStorage("screenshotAddRoundCorner")
    var screenshotAddRoundCorner: Bool = true

    /// 截图圆角半径（点）
    @AppStorage("screenshotCornerRadius")
    var screenshotCornerRadius: Double = 12.0

    /// 是否为截图添加阴影
    @AppStorage("screenshotAddShadow")
    var screenshotAddShadow: Bool = true


    // MARK: 快捷键设置（存储为可读字符串描述，由 HotkeyManager 解析）

    /// 区域截图快捷键
    @AppStorage("hotkeyAreaScreenshot")
    var hotkeyAreaScreenshot: String = "ctrl+shift+a"

    /// 长截图快捷键
    @AppStorage("hotkeyLongScreenshot")
    var hotkeyLongScreenshot: String = "ctrl+shift+l"

    /// 屏幕取色快捷键
    @AppStorage("hotkeyColorPicker")
    var hotkeyColorPicker: String = "ctrl+shift+c"

    /// 贴图快捷键
    @AppStorage("hotkeyPin")
    var hotkeyPin: String = "ctrl+shift+p"

    // MARK: 通用设置

    /// 是否首次启动（用于显示引导页）
    @AppStorage("isFirstLaunch")
    var isFirstLaunch: Bool = true

    /// 菜单栏图标风格 (camera.fill / camera.circle.fill / camera.viewfinder)
    @AppStorage("menuBarIconStyle")
    var menuBarIconStyle: String = "camera.fill"

    /// 系统语言选择
    @AppStorage("appLanguage")
    var appLanguage: String = "zh-CN"

    // MARK: 新建文件设置

    @AppStorage("templateShowIcons")
    var templateShowIcons: Bool = true

    @AppStorage("templateSoundEffects")
    var templateSoundEffects: Bool = true

    @AppStorage("templateAutoOpen")
    var templateAutoOpen: Bool = false
}
import Foundation
import SwiftUI

public class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()
    
    // 监听 UserDefaults 变化，方便后续动态刷新（如果需要的话）
    @AppStorage("appLanguage") public var appLanguage: String = "zh-CN"
    
    // 翻译字典：Key 是中文原文，Value 是根据语言不同对应的值
    private let translations: [String: [String: String]] = [
        "en": [
            "SnapClick": "SnapClick",
            "v1.0.2": "v1.0.2",
            "版本 1.0.2": "Version 1.0.2",
            "SETUP PROGRESS": "SETUP PROGRESS",
            "已启用": "Enabled",
            "欢迎使用 SnapClick": "Welcome to SnapClick",
            "让您的 macOS 效率飞跃，请授予以下权限以开启全部功能": "Boost your macOS productivity. Please grant the following permissions to enable all features.",
            "完成设置": "Complete Setup",
            "您可以随时在系统偏好设置中撤销或调整这些权限。": "You can revoke or adjust these permissions at any time in System Settings.",
            "已授权": "Authorized",
            "未授权": "Unauthorized",
            " / 4 已授权": " / 4 Authorized",
            "搜索设置": "Search Settings",
            "请选择一项设置": "Please select a setting",
            "系统权限状态": "System Permission Status",
            "外观偏好": "Appearance Preferences",
            "系统语言": "System Language",
            "应用界面及菜单的呈现语言": "Display language for the app interface and menus",
            "简体中文": "Simplified Chinese",
            "English (US)": "English (US)",
            "日本語": "Japanese",
            "全局快捷键": "Global Shortcuts",
            "Power Up Your Workflow": "Power Up Your Workflow",
            "启用 Finder 右键插件，解锁高级新建文件、隔空投送、剪切粘贴与 MD5 计算等专属生产力工具。": "Enable Finder Right-Click Extension to unlock advanced features like new file creation, AirDrop, cut/paste, and MD5 calculation.",
            "专为 macOS 打造的原生效率整合包\n右键增强 · 截图标注 · 屏幕录制 · 贴图取色": "A native productivity suite built for macOS\nRight-Click Enhancements · Screenshot Annotations · Screen Recording · Color Picker & Pin",
            "保存路径与格式": "Save Path & Format",
            "保存路径": "Save Path",
            "默认格式": "Default Format",
            "截图外观美化": "Screenshot Beautification",
            "添加圆角": "Add Rounded Corners",
            "圆角半径": "Corner Radius",
            "添加阴影": "Add Shadow",
            "重启应用以生效": "Restart App to Apply",
            "您更改了系统语言，需要重新启动 SnapClick 才能完全应用新的语言设置。": "You have changed the system language. SnapClick needs to restart to fully apply the new language settings.",
            "立即重启": "Restart Now",
            "稍后": "Later",
            "启动取色": "Launch Color Picker",
            "暂无历史记录": "No History",
            "贴图快捷键": "Pin Image Shortcut",
            "复制": "Copy",
            "清空历史": "Clear History",
            "常用目录": "Common Directories",
            "这些目录将显示在右键菜单的\"移动到\"和\"复制到\"子菜单中。": "These directories will appear in the \"Move to\" and \"Copy to\" submenus of the right-click menu.",
            "新建文件模板": "New File Templates",
            "勾选的模板将显示在右键菜单\"新建文件\"子菜单中。": "Checked templates will appear in the \"New File\" submenu of the right-click menu.",
            "暂无自定义模板": "No Custom Templates",
            "内置": "Built-in",
            "添加自定义模板": "Add Custom Template",
            "开发者工具": "Developer Tools",
            "已安装的工具会自动显示在\"用…打开\"子菜单中，无需手动配置。": "Installed tools will automatically appear in the \"Open with...\" submenu. No manual configuration needed.",
            "如需添加更多工具，请确保对应应用已通过 App Store 或官网安装。": "To add more tools, please ensure the corresponding applications are installed via the App Store or official website.",
            "矩形": "Rectangle",
            "椭圆": "Ellipse",
            "箭头": "Arrow",
            "画笔": "Pen",
            "马赛克": "Mosaic",
            "文本": "Text",
            "序号": "Number",
            "高亮": "Highlight",
            "橡皮擦": "Eraser",
            "拖动": "Drag",
            "麦克风权限": "Microphone Permission",
            "用于视频录制时捕获高清晰人声与环境音": "Used to capture clear vocals and ambient sound during video recording",
            "屏幕录制": "Screen Recording",
            "全屏录像、区域录制及窗口捕获必需权限": "Required for full-screen recording, area recording, and window capture",
            "辅助功能": "Accessibility",
            "自动化": "Automation",
            "关闭贴图": "Close Pin",
            "复制图片": "Copy Image",
            "存储到历史": "Save to History"
        ],
        "ja": [
            "SnapClick": "SnapClick",
            "v1.0.2": "v1.0.2",
            "版本 1.0.2": "バージョン 1.0.2",
            "SETUP PROGRESS": "セットアップの進行状況",
            "已启用": "有効",
            "欢迎使用 SnapClick": "SnapClick へようこそ",
            "让您的 macOS 效率飞跃，请授予以下权限以开启全部功能": "macOS の生産性を向上させます。すべての機能を有効にするには以下の権限を付与してください。",
            "完成设置": "セットアップを完了",
            "您可以随时在系统偏好设置中撤销或调整这些权限。": "これらの権限はシステム設定でいつでも取り消しや調整が可能です。",
            "已授权": "承認済み",
            "未授权": "未承認",
            " / 4 已授权": " / 4 承認済み",
            "搜索设置": "設定を検索",
            "请选择一项设置": "設定を選択してください",
            "系统权限状态": "システムの権限状態",
            "外观偏好": "外観の設定",
            "系统语言": "システム言語",
            "应用界面及菜单的呈现语言": "アプリのインターフェイスとメニューの表示言語",
            "简体中文": "簡体字中国語",
            "English (US)": "英語 (米国)",
            "日本語": "日本語",
            "全局快捷键": "グローバルショートカット",
            "Power Up Your Workflow": "ワークフローを強化",
            "启用 Finder 右键插件，解锁高级新建文件、隔空投送、剪切粘贴与 MD5 计算等专属生产力工具。": "Finder の右クリック拡張を有効にし、新規ファイル作成、AirDrop、切り取り/貼り付け、MD5 計算などの高度な機能のロックを解除します。",
            "专为 macOS 打造的原生效率整合包\n右键增强 · 截图标注 · 屏幕录制 · 贴图取色": "macOS 専用のネイティブ生産性スイート\n右クリック拡張 · スクリーンショット注釈 · 画面録画 · カラーピッカー＆ピン留め",
            "保存路径与格式": "保存パスとフォーマット",
            "保存路径": "保存パス",
            "默认格式": "デフォルトのフォーマット",
            "截图外观美化": "スクリーンショットの美化",
            "添加圆角": "角丸を追加",
            "圆角半径": "角丸の半径",
            "添加阴影": "シャドウを追加",
            "重启应用以生效": "アプリを再起動して適用",
            "您更改了系统语言，需要重新启动 SnapClick 才能完全应用新的语言设置。": "システム言語を変更しました。新しい言語設定を完全に適用するには SnapClick を再起動する必要があります。",
            "立即重启": "今すぐ再起動",
            "稍后": "後で",
            "启动取色": "カラーピッカーを起動",
            "暂无历史记录": "履歴なし",
            "贴图快捷键": "画像のピン留めショートカット",
            "复制": "コピー",
            "清空历史": "履歴を消去",
            "常用目录": "よく使うディレクトリ",
            "这些目录将显示在右键菜单的\"移动到\"和\"复制到\"子菜单中。": "これらのディレクトリは、右クリックメニューの「〜へ移動」および「〜へコピー」サブメニューに表示されます。",
            "新建文件模板": "新規ファイルテンプレート",
            "勾选的模板将显示在右键菜单\"新建文件\"子菜单中。": "チェックしたテンプレートは、右クリックメニューの「新規ファイル」サブメニューに表示されます。",
            "暂无自定义模板": "カスタムテンプレートなし",
            "内置": "組み込み",
            "添加自定义模板": "カスタムテンプレートを追加",
            "开发者工具": "開発者ツール",
            "已安装的工具会自动显示在\"用…打开\"子菜单中，无需手动配置。": "インストールされたツールは自動的に「このアプリケーションで開く」サブメニューに表示されます。手動設定は不要です。",
            "如需添加更多工具，请确保对应应用已通过 App Store 或官网安装。": "さらにツールを追加するには、App Store または公式サイト経由で該当するアプリがインストールされていることを確認してください。",
            "矩形": "長方形",
            "椭圆": "楕円",
            "箭头": "矢印",
            "画笔": "ペン",
            "马赛克": "モザイク",
            "文本": "テキスト",
            "序号": "番号",
            "高亮": "ハイライト",
            "橡皮擦": "消しゴム",
            "拖动": "ドラッグ",
            "麦克风权限": "マイクの権限",
            "用于视频录制时捕获高清晰人声与环境音": "ビデオ録画中のクリアな音声や環境音のキャプチャに使用されます",
            "屏幕录制": "画面録画",
            "全屏录像、区域录制及窗口捕获必需权限": "全画面録画、領域録画、ウィンドウキャプチャに必須の権限",
            "辅助功能": "アクセシビリティ",
            "自动化": "オートメーション",
            "关闭贴图": "ピン留めを閉じる",
            "复制图片": "画像をコピー",
            "存储到历史": "履歴に保存"
        ]
    ]
    
    public func localized(_ text: String) -> String {
        let currentLang = appLanguage
        if currentLang == "zh-CN" { return text }
        if let langDict = translations[currentLang], let localizedStr = langDict[text] {
            return localizedStr
        }
        return text // 默认返回原文（中文）
    }
}

public extension String {
    var localized: String {
        return LanguageManager.shared.localized(self)
    }
}
