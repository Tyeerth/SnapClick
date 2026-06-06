import SwiftUI
import ServiceManagement

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

    /// 系统语言选择 — 通过 LanguageManager 桥接以触发实时刷新
    var appLanguage: String {
        get { LanguageManager.shared.appLanguage }
        set { LanguageManager.shared.appLanguage = newValue }
    }

    /// 开机自启动
    @AppStorage("launchAtLogin")
    var launchAtLogin: Bool = false {
        didSet {
            updateLaunchAtLogin()
        }
    }

    /// 在菜单栏显示图标
    @AppStorage("showInMenuBar")
    var showInMenuBar: Bool = true {
        didSet {
            NotificationCenter.default.post(name: .showInMenuBarDidChange, object: nil)
        }
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[AppSettings] 开机自启动设置失败: \(error)")
            }
        }
    }

    // MARK: 新建文件设置

    @AppStorage("templateShowIcons")
    var templateShowIcons: Bool = true

    @AppStorage("templateSoundEffects")
    var templateSoundEffects: Bool = true

    @AppStorage("templateAutoOpen")
    var templateAutoOpen: Bool = false
}

// MARK: - LanguageManager

/// 语言管理器
/// - 使用 @Published 触发 SwiftUI 实时刷新
/// - 字典覆盖所有 UI 中通过 `.localized` 引用的中文文案
public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()

    /// 当前语言（持久化到 UserDefaults，并触发 objectWillChange）
    @Published public var appLanguage: String {
        didSet {
            UserDefaults.standard.set(appLanguage, forKey: "appLanguage")
            // 广播通知用于 AppKit 部分（菜单栏等）的刷新
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    private init() {
        self.appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-CN"
    }

    // MARK: - 翻译字典

    private let translations: [String: [String: String]] = [
        "en": [
            // 应用 & 版本
            "SnapClick": "SnapClick",
            "v1.0.2": "v1.0.2",
            "版本 1.0.2": "Version 1.0.2",
            "设置": "Settings",
            "设置…": "Settings…",
            "退出 SnapClick": "Quit SnapClick",
            "请按下组合键...": "Press a key combination…",
            "无": "None",
            "更改…": "Change…",

            // 侧边栏 / 导航
            "通用": "General",
            "截图与标注": "Screenshot & Annotation",
            "贴图 & 取色": "Pin & Color",
            "右键菜单": "Right-Click Menu",
            "关于": "About",
            "请选择一个设置项": "Please select a setting",
            "从左侧侧边栏选择要配置的功能模块": "Select a module to configure from the sidebar",

            // 欢迎页
            "SETUP PROGRESS": "SETUP PROGRESS",
            "已启用": "Enabled",
            "欢迎使用 SnapClick": "Welcome to SnapClick",
            "让您的 macOS 效率飞跃，请授予以下权限以开启全部功能": "Boost your macOS productivity. Please grant the following permissions to enable all features.",
            "完成设置": "Complete Setup",
            "您可以随时在系统偏好设置中撤销或调整这些权限。": "You can revoke or adjust these permissions at any time in System Settings.",
            "已授权": "Authorized",
            "未授权": "Unauthorized",
            "去授权": "Authorize",
            "去启用": "Enable",
            " / 3 已授权": " / 3 Authorized",

            // 通用设置页
            "权限状态概览": "Permissions Overview",
            "全部已授权": "All Permissions Granted",
            "存在未授权项": "Some Permissions Missing",
            "屏幕录制权限": "Screen Recording Permission",
            "区域/窗口截图及放大镜取色所需": "Required for screenshots & magnifier color picker",
            "辅助功能权限": "Accessibility Permission",
            "全局快捷键拦截与响应所需": "Required for global hotkey interception",
            "Finder 右键扩展": "Finder Right-Click Extension",
            "在 Finder 中显示增强右键菜单所需": "Required to show enhanced right-click menu in Finder",
            "刷新权限状态": "Refresh Permissions",
            "启动与系统": "Startup & System",
            "开机自启动": "Launch at Login",
            "在菜单栏显示图标": "Show Icon in Menu Bar",
            "语言与外观偏好": "Language & Appearance",
            "系统语言": "System Language",
            "应用界面及菜单的呈现语言": "Display language for the app interface and menus",
            "简体中文": "Simplified Chinese",
            "English (US)": "English (US)",
            "日本語": "Japanese",
            "全局快捷键": "Global Shortcuts",
            "区域截图": "Area Screenshot",
            "长截图": "Long Screenshot",
            "屏幕取色": "Color Picker",
            "贴图": "Pin Image",

            // 截图设置
            "保存路径与格式": "Save Path & Format",
            "保存路径": "Save Path",
            "默认格式": "Default Format",
            "截图外观美化": "Screenshot Beautification",
            "添加圆角": "Add Rounded Corners",
            "圆角半径": "Corner Radius",
            "添加阴影": "Add Shadow",

            // 取色 & 贴图
            "取色器": "Color Picker",
            "贴图板": "Pin Board",
            "启动取色": "Launch Color Picker",
            "默认复制格式": "Default Copy Format",
            "颜色历史（最近 20 个）": "Color History (Latest 20)",
            "快捷键": "Shortcut",
            "暂无历史记录": "No History",
            "贴图快捷键": "Pin Image Shortcut",
            "复制": "Copy",
            "清空历史": "Clear History",
            "窗口控制": "Window Control",
            "显示全部": "Show All",
            "隐藏全部": "Hide All",
            "关闭全部": "Close All",
            "关闭贴图": "Close Pin",
            "复制图片": "Copy Image",
            "存储到历史": "Save to History",

            // 右键菜单设置
            "常用目录": "Common Directories",
            "常用目录 (Common Directories)": "Common Directories",
            "从右键菜单快速访问常用文件夹。": "Quickly access common folders from the right-click menu.",
            "恢复默认": "Restore Defaults",
            "添加目录": "Add Directory",
            "选择目录": "Select Directory",
            "桌面": "Desktop",
            "文稿": "Documents",
            "下载": "Downloads",
            "图片": "Pictures",
            "名称": "Name",
            "路径": "Path",
            "暂无常用目录，请点击上方按钮添加": "No common directories yet. Click the button above to add.",
            "新建常用文件 (New File Templates)": "New File Templates",
            "新建常用文件，这些文件将显示在右键菜单中。": "Create common files. These templates will appear in the right-click menu.",
            "添加": "Add",
            "导入": "Import",
            "图标": "Icon",
            "显示名称": "Display Name",
            "后缀": "Extension",
            "主菜单": "Main Menu",
            "操作": "Actions",
            "内置": "Built-in",
            "显示图标": "Show Icons",
            "开启提示音": "Enable Sound Effects",
            "自动打开": "Auto Open",
            "Pro Tip:": "Pro Tip:",
            "在 Finder 中按住 Option (⌥) 键右击，可查看系统原生右键菜单。": "Hold Option (⌥) and right-click in Finder to see the native system right-click menu.",
            "添加自定义模板": "Add Custom Template",
            "模板名称（如 Vue 组件）": "Template name (e.g. Vue Component)",
            "扩展名（如 vue）": "Extension (e.g. vue)",
            "取消": "Cancel",
            "开发者工具": "Developer Tools",
            "已安装的工具会自动显示在\"用…打开\"子菜单中，无需手动配置。": "Installed tools will automatically appear in the \"Open With…\" submenu.",
            "已安装": "Installed",
            "未安装": "Not Installed",
            "如需添加更多工具，请确保对应应用已通过 App Store 或官网安装。": "To add more tools, please ensure they are installed via the App Store or official website.",
            "新建文件模板": "New File Templates",

            // 关于
            "专为 macOS 打造的原生效率整合包\n右键增强 · 截图标注 · 屏幕录制 · 贴图取色":
                "A native productivity suite built for macOS\nRight-Click · Screenshots · Screen Recording · Color Picker",

            // 提示对话框
            "剪贴板未包含图片": "Clipboard does not contain an image",
            "请先使用 ⌘C 复制一张图片或使用截图功能，随后即可在此直接贴图。": "Please copy an image with ⌘C or take a screenshot first, then you can pin it here.",
            "好的": "OK",
            "需要屏幕录制权限": "Screen Recording Permission Required",
            "请在系统设置 → 隐私与安全性 → 屏幕录制中授权 SnapClick。": "Please authorize SnapClick in System Settings → Privacy & Security → Screen Recording.",
            "去设置": "Open Settings",
            "需要辅助功能权限": "Accessibility Permission Required",
            "请在系统设置 → 隐私与安全性 → 辅助功能中授权 SnapClick。": "Please authorize SnapClick in System Settings → Privacy & Security → Accessibility.",

            // 欢迎页权限卡片
            "Finder 增强": "Finder Enhancement",
            "屏幕录制 (Screen Recording)": "Screen Recording",
            "辅助功能 (Accessibility)": "Accessibility",
            "Finder 右键扩展 (Finder Extension)": "Finder Extension",
            "用于区域/窗口截图及放大镜取色": "Required for area/window screenshots and magnifier color picker",
            "用于全局快捷键拦截与极速响应": "Required for global hotkey interception and rapid response",
            "直接在系统右键菜单中集成高级新建文件与复制工具": "Integrate new file creation and copy tools directly in the system right-click menu",

            // 取色器
            "单击取色并复制到剪贴板": "Click to pick color and copy to clipboard",
        ],
        "ja": [
            "SnapClick": "SnapClick",
            "v1.0.2": "v1.0.2",
            "版本 1.0.2": "バージョン 1.0.2",
            "设置": "設定",
            "设置…": "設定…",
            "退出 SnapClick": "SnapClick を終了",
            "请按下组合键...": "キーの組み合わせを押してください…",
            "无": "なし",
            "更改…": "変更…",

            "通用": "一般",
            "截图与标注": "スクリーンショットと注釈",
            "贴图 & 取色": "ピン留めとカラーピッカー",
            "右键菜单": "右クリックメニュー",
            "关于": "情報",
            "请选择一个设置项": "設定項目を選択してください",
            "从左侧侧边栏选择要配置的功能模块": "左のサイドバーから設定するモジュールを選択",

            "SETUP PROGRESS": "セットアップの進行状況",
            "已启用": "有効",
            "欢迎使用 SnapClick": "SnapClick へようこそ",
            "让您的 macOS 效率飞跃，请授予以下权限以开启全部功能": "macOS の生産性を向上させます。すべての機能を有効にするには以下の権限を付与してください。",
            "完成设置": "セットアップを完了",
            "您可以随时在系统偏好设置中撤销或调整这些权限。": "これらの権限はシステム設定でいつでも取り消しや調整が可能です。",
            "已授权": "承認済み",
            "未授权": "未承認",
            "去授权": "認証",
            "去启用": "有効化",
            " / 3 已授权": " / 3 承認済み",

            "权限状态概览": "権限の概要",
            "全部已授权": "すべて承認済み",
            "存在未授权项": "未承認の項目があります",
            "屏幕录制权限": "画面録画の権限",
            "区域/窗口截图及放大镜取色所需": "スクリーンショットとカラーピッカーに必要",
            "辅助功能权限": "アクセシビリティの権限",
            "全局快捷键拦截与响应所需": "グローバルショートカットの取得に必要",
            "Finder 右键扩展": "Finder 右クリック拡張",
            "在 Finder 中显示增强右键菜单所需": "Finder で右クリックメニューを拡張するために必要",
            "刷新权限状态": "権限を更新",
            "启动与系统": "起動とシステム",
            "开机自启动": "ログイン時に起動",
            "在菜单栏显示图标": "メニューバーにアイコンを表示",
            "语言与外观偏好": "言語と外観",
            "系统语言": "システム言語",
            "应用界面及菜单的呈现语言": "アプリのインターフェイスとメニューの表示言語",
            "简体中文": "簡体字中国語",
            "English (US)": "英語 (米国)",
            "日本語": "日本語",
            "全局快捷键": "グローバルショートカット",
            "区域截图": "領域スクリーンショット",
            "长截图": "ロングスクリーンショット",
            "屏幕取色": "カラーピッカー",
            "贴图": "ピン留め",

            "保存路径与格式": "保存パスとフォーマット",
            "保存路径": "保存パス",
            "默认格式": "デフォルトのフォーマット",
            "截图外观美化": "スクリーンショットの美化",
            "添加圆角": "角丸を追加",
            "圆角半径": "角丸の半径",
            "添加阴影": "シャドウを追加",

            "取色器": "カラーピッカー",
            "贴图板": "ピンボード",
            "启动取色": "カラーピッカーを起動",
            "默认复制格式": "デフォルトコピー形式",
            "颜色历史（最近 20 个）": "カラー履歴（最近 20 件）",
            "快捷键": "ショートカット",
            "暂无历史记录": "履歴なし",
            "贴图快捷键": "画像のピン留めショートカット",
            "复制": "コピー",
            "清空历史": "履歴を消去",
            "窗口控制": "ウィンドウ制御",
            "显示全部": "すべて表示",
            "隐藏全部": "すべて非表示",
            "关闭全部": "すべて閉じる",
            "关闭贴图": "ピン留めを閉じる",
            "复制图片": "画像をコピー",
            "存储到历史": "履歴に保存",

            "常用目录": "よく使うディレクトリ",
            "常用目录 (Common Directories)": "よく使うディレクトリ",
            "从右键菜单快速访问常用文件夹。": "右クリックメニューからよく使うフォルダにすばやくアクセス。",
            "恢复默认": "デフォルトに戻す",
            "添加目录": "ディレクトリを追加",
            "选择目录": "ディレクトリを選択",
            "桌面": "デスクトップ",
            "文稿": "書類",
            "下载": "ダウンロード",
            "图片": "ピクチャ",
            "名称": "名前",
            "路径": "パス",
            "暂无常用目录，请点击上方按钮添加": "よく使うディレクトリがありません。上のボタンで追加してください。",
            "新建常用文件 (New File Templates)": "新規ファイルテンプレート",
            "新建常用文件，这些文件将显示在右键菜单中。": "新しいファイルを作成。テンプレートは右クリックメニューに表示されます。",
            "添加": "追加",
            "导入": "インポート",
            "图标": "アイコン",
            "显示名称": "表示名",
            "后缀": "拡張子",
            "主菜单": "メインメニュー",
            "操作": "操作",
            "内置": "組み込み",
            "显示图标": "アイコンを表示",
            "开启提示音": "効果音を有効",
            "自动打开": "自動で開く",
            "Pro Tip:": "ヒント:",
            "在 Finder 中按住 Option (⌥) 键右击，可查看系统原生右键菜单。": "Finder で Option (⌥) を押しながら右クリックすると、ネイティブメニューが表示されます。",
            "添加自定义模板": "カスタムテンプレートを追加",
            "模板名称（如 Vue 组件）": "テンプレート名（例：Vue コンポーネント）",
            "扩展名（如 vue）": "拡張子（例：vue）",
            "取消": "キャンセル",
            "开发者工具": "開発者ツール",
            "已安装的工具会自动显示在\"用…打开\"子菜单中，无需手动配置。": "インストールされたツールは自動的に「このアプリケーションで開く」サブメニューに表示されます。",
            "已安装": "インストール済み",
            "未安装": "未インストール",
            "如需添加更多工具，请确保对应应用已通过 App Store 或官网安装。": "ツールを追加するには、App Store または公式サイト経由でインストールしてください。",
            "新建文件模板": "新規ファイルテンプレート",

            "专为 macOS 打造的原生效率整合包\n右键增强 · 截图标注 · 屏幕录制 · 贴图取色":
                "macOS 専用のネイティブ生産性スイート\n右クリック · スクリーンショット · 画面録画 · カラーピッカー",

            // 提示対話
            "剪贴板未包含图片": "クリップボードに画像が含まれていません",
            "请先使用 ⌘C 复制一张图片或使用截图功能，随后即可在此直接贴图。": "⌘C で画像をコピーするか、スクリーンショットを撮ってからピン留めしてください。",
            "好的": "OK",
            "需要屏幕录制权限": "画面録画の権限が必要です",
            "请在系统设置 → 隐私与安全性 → 屏幕录制中授权 SnapClick。": "システム設定 → プライバシーとセキュリティ → 画面録画 で SnapClick を承認してください。",
            "去设置": "設定を開く",
            "需要辅助功能权限": "アクセシビリティの権限が必要です",
            "请在系统设置 → 隐私与安全性 → 辅助功能中授权 SnapClick。": "システム設定 → プライバシーとセキュリティ → アクセシビリティ で SnapClick を承認してください。",

            // ウェルカムページ権限カード
            "Finder 增强": "Finder 拡張",
            "屏幕录制 (Screen Recording)": "画面録画",
            "辅助功能 (Accessibility)": "アクセシビリティ",
            "Finder 右键扩展 (Finder Extension)": "Finder 拡張機能",
            "用于区域/窗口截图及放大镜取色": "領域/ウィンドウのスクリーンショットとカラーピッカーに必要",
            "用于全局快捷键拦截与极速响应": "グローバルショートカットの取得と高速応答に必要",
            "直接在系统右键菜单中集成高级新建文件与复制工具": "システムの右クリックメニューに新規ファイル作成とコピーツールを統合",

            // カラーピッカー
            "单击取色并复制到剪贴板": "クリックして色を取得しクリップボードにコピー",
        ]
    ]

    public func localized(_ text: String) -> String {
        let currentLang = appLanguage
        if currentLang == "zh-CN" { return text }
        if let langDict = translations[currentLang], let localizedStr = langDict[text] {
            return localizedStr
        }
        return text
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("AppLanguageDidChange")
    static let showInMenuBarDidChange = Notification.Name("ShowInMenuBarDidChange")
}

// MARK: - String Extension

public extension String {
    /// 通过 LanguageManager 翻译当前字符串
    var localized: String {
        return LanguageManager.shared.localized(self)
    }
}
