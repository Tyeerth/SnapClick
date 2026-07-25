import SwiftUI
import ServiceManagement

// MARK: - AppSettings

/// 全局应用设置
/// 使用 UserDefaults + @AppStorage 持久化，支持 SwiftUI 双向绑定
final class AppSettings: ObservableObject {

    // MARK: 单例

    static let shared = AppSettings()

    private init() {
    }

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

    /// 窗口截图快捷键
    @AppStorage("hotkeyWindowScreenshot")
    var hotkeyWindowScreenshot: String = "ctrl+shift+w"

    /// 选区截图快捷键（仅区域框选，不支持点击窗口）
    @AppStorage("hotkeyRegionScreenshot")
    var hotkeyRegionScreenshot: String = "ctrl+shift+s"

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
    var showInMenuBar: Bool = true {
        didSet {
            NotificationCenter.default.post(name: .showInMenuBarDidChange, object: nil)
        }
    }

    /// 在程序坞中显示图标
    @AppStorage("showInDock")
    var showInDock: Bool = false {
        didSet {
            NotificationCenter.default.post(name: .showInDockDidChange, object: nil)
        }
    }

    /// 外观模式（"light" / "dark" / "auto"）
    @AppStorage("appAppearance")
    var appAppearance: String = "auto"

    /// 是否开启毛玻璃/玻璃半透明效果
    @AppStorage("enableGlassEffect")
    var enableGlassEffect: Bool = true {
        didSet {
            NotificationCenter.default.post(name: .enableGlassEffectDidChange, object: nil)
        }
    }

    /// 玻璃面板透明度（0.3 ~ 1.0，值越小越透明）
    @AppStorage("glassOpacity")
    var glassOpacity: Double = 1.0 {
        didSet {
            NotificationCenter.default.post(name: .enableGlassEffectDidChange, object: nil)
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

    // MARK: 屏幕录制设置

    /// 录制文件保存路径（默认桌面）
    @AppStorage("recordSavePath")
    var recordSavePath: String = "~/Desktop"

    /// 录制格式（MOV / MP4）
    @AppStorage("recordFormat")
    var recordFormat: String = "MOV"

    /// 视频编解码（H.264 / HEVC）
    @AppStorage("recordCodec")
    var recordCodec: String = "HEVC"

    /// 帧率（30 / 60 / 120）
    @AppStorage("recordFPS")
    var recordFPS: Int = 60

    /// 录制清晰度档位（"标清" / "超清" / "原画"）
    /// 录制前参数面板（RecordingSelectionHUDView）下拉选项写入此处
    @AppStorage("recordQuality")
    var recordQuality: String = "超清"

    /// 全屏录制的目标屏幕（按 NSScreen.localizedName 匹配）
    /// 录制前参数面板的"屏幕"下拉写入此处；
    /// ScreenRecordingEngine 启动时按名字匹配，找不到时兑底到鼠标所在屏
    @AppStorage("recordFullScreenScreenName")
    var recordFullScreenScreenName: String = ""

    /// 录制系统音频
    @AppStorage("recordSystemAudio")
    var recordSystemAudio: Bool = true

    /// 麦克风设备名称（"无" 表示不录麦克风）
    @AppStorage("recordMicrophone")
    var recordMicrophone: String = "无"

    /// 定时录制秒数（默认 3 秒）
    @AppStorage("recordTimer")
    var recordTimer: Int = 3

    /// 鼠标高亮
    @AppStorage("recordHighlightCursor")
    var recordHighlightCursor: Bool = false

    /// 区域录制快捷键
    @AppStorage("hotkeyRecordArea")
    var hotkeyRecordArea: String = "ctrl+shift+r"

    /// 全屏录制快捷键
    @AppStorage("hotkeyRecordScreen")
    var hotkeyRecordScreen: String = "ctrl+shift+f"

    /// 停止录制快捷键
    @AppStorage("hotkeyStopRecording")
    var hotkeyStopRecording: String = "ctrl+shift+s"

    /// 默认录制范围/模式（"area" / "screen" / "window"）
    @AppStorage("recordDefaultMode")
    var recordDefaultMode: String = "area"

    // MARK: 音频录音设置

    /// 音频录音保存路径
    @AppStorage("audioRecordSavePath")
    var audioRecordSavePath: String = "~/Desktop"

    /// 音频质量（"经济" / "标准" / "高质量"）
    @AppStorage("audioRecordQuality")
    var audioRecordQuality: String = "标准"

    /// 音频采样率（Hz，44100 / 48000）
    @AppStorage("audioRecordSampleRate")
    var audioRecordSampleRate: Int = 44_100

    /// 录音声道数（1 单声道 / 2 立体声）
    @AppStorage("audioRecordChannels")
    var audioRecordChannels: Int = 2

    /// 麦克风设备名称（"无" 表示不录麦克风）
    @AppStorage("audioRecordMicrophone")
    var audioRecordMicrophone: String = "无"

    /// 录制系统音频（macOS 13+）
    @AppStorage("audioRecordSystemAudio")
    var audioRecordSystemAudio: Bool = true

    /// 录音倒计时秒数（0 表示关闭）
    @AppStorage("audioRecordCountdown")
    var audioRecordCountdown: Int = 3

    /// 录音时自动调整麦克风音量
    @AppStorage("audioRecordAutoAdjust")
    var audioRecordAutoAdjust: Bool = true

    /// 开始录音快捷键
    @AppStorage("hotkeyAudioRecord")
    var hotkeyAudioRecord: String = "ctrl+shift+m"

    /// 停止录音快捷键
    @AppStorage("hotkeyStopAudioRecord")
    var hotkeyStopAudioRecord: String = "ctrl+shift+n"
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
            "版本 %@": "Version %@",
            "发现新版本": "Update Available",
            "检测到新版本 %@，当前版本 %@。是否前往下载页面？": "A new version %@ is available (current: %@). Go to the download page?",
            "前往下载": "Download",
            "稍后": "Later",
            "已是最新版本": "You're Up to Date",
            "当前版本 %@ 已是最新。": "Current version %@ is the latest.",
            "好": "OK",
            "检查更新失败": "Update Check Failed",
            "无法连接到更新服务器，请检查网络后重试。": "Could not connect to the update server. Please check your network and try again.",
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
            "重新检测": "Re-check",
            "检测中…": "Checking…",
            "启动与系统": "Startup & System",
            "开机自启动": "Launch at Login",
            "在菜单栏显示图标": "Show Icon in Menu Bar",
            "在程序坞中显示图标": "Show Icon in Dock",
            "在下方程序坞中显示应用图标": "Show the application icon in the Dock",
            "语言与外观偏好": "Language & Appearance",
            "系统语言": "System Language",
            "应用界面及菜单的呈现语言": "Display language for the app interface and menus",
            "简体中文": "Simplified Chinese",
            "English (US)": "English (US)",
            "日本語": "Japanese",
            "毛玻璃效果": "Glass Effect",
            "使窗口背景呈现半透明的玻璃质感": "Make window backgrounds translucent and glassy",
            "面板透明度": "Panel Opacity",
            "透明": "Transparent",
            "不透明": "Opaque",
            "全局快捷键": "Global Shortcuts",
            "截图": "Screenshot",
            "区域截图": "Screenshot",
            "窗口截图": "Window Screenshot",
            "智能截图": "Smart Capture",
            "拖动鼠标框选": "Drag mouse to select",
            "拖动鼠标框选区域": "Drag mouse to select area",
            "点击截取窗口": "Click to capture window",
            "点击截取该窗口": "Click to capture this window",
            "或拖动选择截图区域": "or drag to select screenshot area",
            "点击选择窗口": "Click to select window",
            "拖动选择要长截图的区域": "Drag to select area for long screenshot",
            "拖动选择截图区域": "Drag to select screenshot area",
            "点击选择要截图的窗口": "Click to select window to capture",
            "点击截取窗口 · 拖拽选择区域": "Click to capture window · Drag to select area",
            "点击确认 · Enter 确定  |  ESC 取消": "Click to confirm · Press Enter  |  ESC Cancel",
            "选取目标窗口": "Select target window",
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
            "操作": "Actions",
            "编辑名称": "Rename",
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

            // 侧边栏 - 新增
            "Finder 右键": "Finder Right-Click",
            "请从左侧选择设置项": "Select a setting from the sidebar",

            // 截图设置 - 新增
            "截图外观": "Screenshot Appearance",
            "窗口透明": "Window Transparency",
            "保留截图原始透明度": "Preserve original transparency in screenshots",
            "储存设置": "Storage",

            // 快捷键 - 新增
            "快速编辑": "Quick Edit",
            "打开标注编辑": "Open annotation editor",
            "点击录制": "Click to Record",

            // 关于页 - 新增
            "官方网站": "Official Website",
            "检查更新": "Check for Updates",
            "高性能屏幕录制，支持音频路由与 GIF 导出。": "High-performance screen recording with audio routing & GIF export.",

            // 右键菜单 - 新增
            "菜单行为": "Menu Behavior",

            // 取色 & 贴图 - 新增
            "按下快捷键后，将鼠标悬停在目标颜色上并单击即可拾取，支持屏幕任意位置。": "After pressing the shortcut, hover over the target color and click to pick. Works anywhere on screen.",
            "从剪贴板抓取图片并钉在屏幕上": "Grab image from clipboard and pin it on screen",
            "使用贴图功能钉上图片后将在此显示最近记录": "Recently pinned images will appear here",

            // 屏幕录制 - 新增
            "屏幕录制": "Screen Recording",
            "音频录制": "Audio Recording",
            "按设置开始录制麦克风或系统音频": "Start recording microphone and/or system audio per settings",
            "停止并保存当前音频录制": "Stop and save the current audio recording",
            "开始录音": "Start Recording",
            "停止录音": "Stop Recording",
            "取消录音": "Cancel Recording",
            "确定取消": "Discard",
            "继续录音": "Continue Recording",
            "确定要取消录音吗？": "Discard this recording?",
            "取消录音将不会保存本次录制的音频文件，并且无法恢复。": "The current audio will be discarded and cannot be recovered. To keep it, click Stop first.",
            "录音中...": "Recording...",
            "录音已暂停": "Recording Paused",
            "正在录音...": "Recording...",
            "音频源": "Audio Source",
            "输出格式": "Output Format",
            "系统音频": "System Audio",
            "需要 macOS 13 或更高版本": "Requires macOS 13 or later",
            "质量": "Quality",
            "采样率": "Sample Rate",
            "声道": "Channels",
            "立体声": "Stereo",
            "单声道": "Mono",
            "倒计时": "Countdown",
            "3 秒": "3 sec",
            "5 秒": "5 sec",
            "10 秒": "10 sec",
            "M4A": "M4A",
            "M4A (只读)": "M4A (read-only)",
            "麦克风权限": "Microphone Permission",
            "需要麦克风权限": "Microphone Permission Required",
            "请在系统设置 → 隐私与安全性 → 麦克风中授权 SnapClick。": "Please authorize SnapClick in System Settings → Privacy & Security → Microphone.",
            "音频预览": "Audio Preview",
            "DURATION": "DURATION",
            "FORMAT": "FORMAT",
            "RATE": "RATE",
            "无法开始录音": "Cannot Start Recording",
            "无法开始音频录音": "Cannot Start Audio Recording",
            "停止录音失败": "Failed to Stop Recording",
            "屏幕录制进行中，请先停止屏幕录制再开始音频录音。": "Screen recording is in progress. Stop it first to start audio recording.",
            "暂停录音": "Pause Recording",
            "麦克风测试": "Microphone Test",
            "检测麦克风": "Test Microphone",
            "停止检测": "Stop Testing",
            "输入等级": "Input Level",
            "输入音量": "Input Volume",
            "自动调整麦克风音量": "Auto Adjust Microphone Volume",
            "录制时自动调整增益，避免音量过小或爆音": "Auto-adjust gain during recording to avoid quiet or clipped audio",
            "正在进行其他录制任务，请先停止后再检测麦克风": "Another recording is in progress. Stop it before testing the microphone.",
            "请先选择麦克风设备": "Please select a microphone first",
            "找不到可用的麦克风设备": "No available microphone found",
            "无法启动麦克风：": "Cannot start microphone: ",
            "录制预览": "Recording Preview",
            "录制范围": "Recording Area",
            "选区录制": "Area Selection",
            "全屏录制": "Full Screen",
            "应用窗口": "App Window",
            "视频参数": "Video Settings",
            "清晰度": "Quality",
            "标清": "SD",
            "超清": "HD",
            "原画": "Original",
            "帧率": "Frame Rate",
            "视频格式": "Format",
            "编解码": "Codec",
            "音频与高级": "Audio & Advanced",
            "系统声音": "System Audio",
            "录制系统内部声音（macOS 13+）": "Record internal system audio (macOS 13+)",
            "麦克风": "Microphone",
            "定时录制": "Countdown Timer",
            "关闭": "Off",
            "鼠标高亮": "Highlight Cursor",
            "录制时高亮显示鼠标光标位置": "Highlight mouse cursor during recording",
            "保存位置": "Save Location",
            "区域录制": "Area Record",
            "选取矩形录制区域": "Select rectangular area to record",
            "全屏开始": "Record Full Screen",
            "立即录制全屏": "Start full-screen recording immediately",
            "选区录制快捷键": "Area Recording Shortcut",
            "全屏录制快捷键": "Full Screen Shortcut",
            "单击选取录制区域": "Click to select recording area",
            "高帧率（流畅）": "High FPS (Smooth)",
            "无损": "Lossless",
            "取消录制？": "Cancel Recording?",
            "当前录制的视频将被丢弃且无法恢复。如需保留，请先点击停止按钮。": "The current recording will be discarded and cannot be recovered. To keep it, click Stop first.",
            "取消录制": "Cancel Recording",
            "继续录制": "Continue Recording",
            "取消并删除": "Cancel & Delete",
            "停止并保存": "Stop & Save",
        ],
        "ja": [
            "SnapClick": "SnapClick",
            "v1.0.2": "v1.0.2",
            "版本 1.0.2": "バージョン 1.0.2",
            "版本 %@": "バージョン %@",
            "发现新版本": "アップデートがあります",
            "检测到新版本 %@，当前版本 %@。是否前往下载页面？": "新しいバージョン %@ が利用可能です（現在: %@）。ダウンロードページを開きますか？",
            "前往下载": "ダウンロード",
            "稍后": "後で",
            "已是最新版本": "最新バージョンです",
            "当前版本 %@ 已是最新。": "現在のバージョン %@ が最新です。",
            "好": "OK",
            "检查更新失败": "アップデートの確認に失敗しました",
            "无法连接到更新服务器，请检查网络后重试。": "アップデートサーバーに接続できません。ネットワークを確認して再試行してください。",
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
            "重新检测": "再チェック",
            "检测中…": "確認中…",
            "启动与系统": "起動とシステム",
            "开机自启动": "ログイン時に起動",
            "在菜单栏显示图标": "メニューバーにアイコンを表示",
            "在程序坞中显示图标": "ドックにアイコンを表示",
            "在下方程序坞中显示应用图标": "ドックにアプリのアイコンを表示する",
            "语言与外观偏好": "言語と外観",
            "系统语言": "システム言語",
            "应用界面及菜单的呈现语言": "アプリのインターフェイスとメニューの表示言語",
            "简体中文": "簡体字中国語",
            "English (US)": "英語 (米国)",
            "日本語": "日本語",
            "毛玻璃效果": "すりガラス効果",
            "使窗口背景呈现半透明的玻璃质感": "ウィンドウの背景を半透明でガラスのような質感にします",
            "面板透明度": "パネル透明度",
            "透明": "透明",
            "不透明": "不透明",
            "全局快捷键": "グローバルショートカット",
            "截图": "スクリーンショット",
            "区域截图": "スクリーンショット",
            "窗口截图": "ウィンドウスクリーンショット",
            "智能截图": "スマートキャプチャ",
            "拖动鼠标框选": "ドラッグで選択",
            "拖动鼠标框选区域": "ドラッグで領域を選択",
            "点击截取窗口": "クリックでウィンドウキャプチャ",
            "点击截取该窗口": "このウィンドウをキャプチャ",
            "或拖动选择截图区域": "または領域をドラッグしてキャプチャ",
            "点击选择窗口": "クリックでウィンドウを選択",
            "拖动选择要长截图的区域": "ロングスクリーンショットの領域をドラッグ",
            "拖动选择截图区域": "スクリーンショットの領域をドラッグ",
            "点击选择要截图的窗口": "クリックでウィンドウを選択",
            "点击截取窗口 · 拖拽选择区域": "クリックでウィンドウキャプチャ · ドラッグで領域選択",
            "点击确认 · Enter 确定  |  ESC 取消": "クリックで確認 · Enterで決定  |  ESC キャンセル",
            "选取目标窗口": "対象ウィンドウを選択",
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
            "操作": "操作",
            "编辑名称": "名前を編集",
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

            // サイドバー - 新增
            "Finder 右键": "Finder 右クリック",
            "请从左侧选择设置项": "左のサイドバーから設定を選択",

            // スクリーンショット設定 - 新增
            "截图外观": "スクリーンショットの外観",
            "窗口透明": "ウィンドウ透明度",
            "保留截图原始透明度": "スクリーンショットの元の透明度を保持",
            "储存设置": "保存設定",

            // ショートカット - 新增
            "快速编辑": "クイック編集",
            "打开标注编辑": "注釈エディタを開く",
            "点击录制": "クリックして録画",

            // 情報ページ - 新增
            "官方网站": "公式サイト",
            "检查更新": "アップデートを確認",
            "高性能屏幕录制，支持音频路由与 GIF 导出。": "高性能な画面録画、オーディオルーティングと GIF エクスポートをサポート。",

            // 右クリックメニュー - 新增
            "菜单行为": "メニュー動作",

            // カラーピッカー & ピン留め - 新增
            "按下快捷键后，将鼠标悬停在目标颜色上并单击即可拾取，支持屏幕任意位置。": "ショートカットキーを押した後、対象の色にカーソルを合わせてクリックで取得。画面のどこでも可能。",
            "从剪贴板抓取图片并钉在屏幕上": "クリップボードから画像を取得して画面にピン留め",
            "使用贴图功能钉上图片后将在此显示最近记录": "ピン留め機能で画像を固定すると、ここに最近の記録が表示されます",

            // 画面録画 - 新增
            "屏幕录制": "画面録画",
            "音频录制": "音声録音",
            "开始录音": "録音開始",
            "停止录音": "録音停止",
            "取消录音": "録音をキャンセル",
            "确定取消": "破棄",
            "继续录音": "録音再開",
            "确定要取消录音吗？": "録音を破棄しますか？",
            "取消录音将不会保存本次录制的音频文件，并且无法恢复。": "現在の音声は破棄され、復元できません。残す場合は、先に停止ボタンをクリックしてください。",
            "录音中...": "録音中...",
            "录音已暂停": "録音一時停止中",
            "正在录音...": "録音中...",
            "音频源": "音声ソース",
            "输出格式": "出力形式",
            "系统音频": "システム音声",
            "需要 macOS 13 或更高版本": "macOS 13 以降が必要",
            "质量": "音質",
            "采样率": "サンプリングレート",
            "声道": "チャンネル",
            "立体声": "ステレオ",
            "单声道": "モノラル",
            "倒计时": "カウントダウン",
            "3 秒": "3 秒",
            "5 秒": "5 秒",
            "10 秒": "10 秒",
            "M4A": "M4A",
            "M4A (只读)": "M4A（読み取り専用）",
            "麦克风权限": "マイクの権限",
            "需要麦克风权限": "マイクの権限が必要です",
            "请在系统设置 → 隐私与安全性 → 麦克风中授权 SnapClick。": "システム設定 → プライバシーとセキュリティ → マイク で SnapClick を承認してください。",
            "音频预览": "音声プレビュー",
            "DURATION": "DURATION",
            "FORMAT": "FORMAT",
            "RATE": "RATE",
            "无法开始录音": "録音を開始できません",
            "无法开始音频录音": "音声録音を開始できません",
            "停止录音失败": "録音停止に失敗",
            "屏幕录制进行中，请先停止屏幕录制再开始音频录音。": "画面録画中です。先に停止してから音声録音を開始してください。",
            "暂停录音": "録音一時停止",
            "麦克风测试": "マイクテスト",
            "检测麦克风": "マイクをテスト",
            "停止检测": "テスト停止",
            "输入等级": "入力レベル",
            "输入音量": "入力音量",
            "自动调整麦克风音量": "マイク音量を自動調整",
            "录制时自动调整增益，避免音量过小或爆音": "録音中にゲインを自動調整し、音量の過不足を防ぎます",
            "正在进行其他录制任务，请先停止后再检测麦克风": "別の録画が進行中です。マイクをテストする前に停止してください",
            "请先选择麦克风设备": "まずマイクを選択してください",
            "找不到可用的麦克风设备": "利用可能なマイクが見つかりません",
            "无法启动麦克风：": "マイクを起動できません：",
            "麦克风权限被拒绝": "マイクの権限が拒否されました",
            "麦克风权限被拒绝，请在「系统设置 → 隐私与安全性 → 麦克风」中打开": "マイクの権限が拒否されました。「システム設定 → プライバシーとセキュリティ → マイク」で有効にしてください",
            " 可能正被其他应用占用": " は他のアプリで使用中の可能性があります",
            "录制范围": "録画範囲",
            "选区录制": "範囲選択",
            "全屏录制": "全画面",
            "应用窗口": "アプリウィンドウ",
            "视频参数": "映像設定",
            "清晰度": "画質",
            "标清": "SD",
            "超清": "HD",
            "原画": "オリジナル画質",
            "帧率": "フレームレート",
            "视频格式": "フォーマット",
            "编解码": "コーデック",
            "音频与高级": "オーディオと詳細",
            "系统声音": "システムオーディオ",
            "录制系统内部声音（macOS 13+）": "システム内部音声を録音（macOS 13+）",
            "麦克风": "マイク",
            "定时录制": "カウントダウン",
            "关闭": "オフ",
            "鼠标高亮": "カーソル強調",
            "录制时高亮显示鼠标光标位置": "録画中にマウスカーソルを強調表示",
            "保存位置": "保存場所",
            "区域录制": "範囲録画",
            "选取矩形录制区域": "録画する矩形領域を選択",
            "全屏开始": "全画面録画",
            "立即录制全屏": "全画面録画をすぐに開始",
            "选区录制快捷键": "範囲録画ショートカット",
            "全屏录制快捷键": "全画面録画ショートカット",
            "单击选取录制区域": "クリックして録画範囲を選択",
            "高帧率（流畅）": "高フレームレート（スムーズ）",
            "无损": "ロスレス",
            "取消录制？": "録画をキャンセルしますか？",
            "当前录制的视频将被丢弃且无法恢复。如需保留，请先点击停止按钮。": "現在の録画は破棄され、復元できません。残す場合は、先に停止ボタンをクリックしてください。",
            "取消录制": "録画をキャンセル",
            "继续录制": "録画を続行",
            "取消并删除": "キャンセルして削除",
            "停止并保存": "停止して保存",
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
    static let showInDockDidChange = Notification.Name("ShowInDockDidChange")
    static let enableGlassEffectDidChange = Notification.Name("EnableGlassEffectDidChange")
}

// MARK: - String Extension

public extension String {
    /// 通过 LanguageManager 翻译当前字符串
    var localized: String {
        return LanguageManager.shared.localized(self)
    }
}
