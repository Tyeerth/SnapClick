import SwiftUI
import AppKit

// MARK: - VisualEffectView
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
        nsView.state = state
    }
}

// MARK: - Liquid Glass 背景（环境光折射 + 壁纸动态色彩渗透）

/// 窗口级 Liquid Glass 背景：在系统壁纸之上叠一层柔和的径向渐变，
/// 营造「环境光折射 + 动态色彩渗透」的氛围感。
struct LiquidGlassBackdrop: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            // 系统毛玻璃基底（最贴近系统壁纸）
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)

            // 环境光折射层：左上 → 右下的多色径向晕染，模拟系统壁纸的色彩渗透
            LinearGradient(
                colors: [
                    Color(red: 99/255,  green: 132/255, blue: 245/255).opacity(0.10),
                    Color(red: 236/255, green: 100/255, blue: 145/255).opacity(0.06),
                    Color(red: 52/255,  green: 199/255, blue: 189/255).opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
            .opacity(settings.enableGlassEffect ? settings.glassOpacity : 0.0)

            // 整体环境色调（与外观同步），降低饱和度让卡片更突出
            // glassOpacity 越小，环境色调越淡，面板越透
            DT.windowBackdrop
                .opacity(settings.enableGlassEffect ? 0.25 * settings.glassOpacity : 1.0)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 窗口外观同步

struct WindowAppearanceSync: NSViewRepresentable {
    let appearance: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        switch appearance {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark":  window.appearance = NSAppearance(named: .darkAqua)
        default:      window.appearance = nil
        }
    }
}

// MARK: - 设计 Token

enum DT {
    // 颜色
    static let sidebarBg        = Color.clear
    static let sidebarSelected  = Color(red: 59/255,  green: 130/255, blue: 246/255)
    static let accent           = Color(red: 59/255,  green: 130/255, blue: 246/255)

    // Liquid Glass 卡片底色（白色叠加层，提高不透明度以保证可读性）
    static let cardBg           = Color.dynamic(
        light: Color.white.opacity(0.22),
        dark: Color(white: 1, opacity: 0.14)
    )
    // Liquid Glass 高光边框（1px rgba(255,255,255,0.3)）
    static let cardBorder       = Color.dynamic(
        light: Color.white.opacity(0.60),
        dark: Color.white.opacity(0.26)
    )
    static let groupLabel       = Color.dynamic(light: Color(red: 148/255, green: 163/255, blue: 184/255), dark: Color(red: 107/255, green: 114/255, blue: 128/255))
    static let successGreen     = Color(red: 34/255,  green: 197/255, blue: 94/255)
    static let warningOrange    = Color(red: 249/255, green: 115/255, blue: 22/255)

    // 间距
    static let contentPadding: CGFloat = 28
    // 圆角：卡片 24，侧边栏 28
    static let cardRadius: CGFloat     = 24
    static let rowPadH: CGFloat        = 18
    static let rowPadV: CGFloat        = 12

    // 悬浮玻璃侧边栏（四周统一边距）
    static let sidebarWidth: CGFloat        = 196
    static let sidebarInset: CGFloat        = 8
    static let sidebarGap: CGFloat          = 4
    static let sidebarCornerRadius: CGFloat = 30

    // Liquid Glass 侧边栏 — 半透明白色叠加（保证内容可读，营造「磨砂」质感）
    static let sidebarGlassOverlay = Color.dynamic(
        light: Color.white.opacity(0.22),
        dark: Color(white: 1, opacity: 0.12)
    )

    // Liquid Glass 侧边栏 — 顶部高光（环境光折射，模拟玻璃边缘的反射）
    static let sidebarTopHighlight = Color.dynamic(
        light: Color.white.opacity(0.55),
        dark: Color.white.opacity(0.22)
    )

    // Liquid Glass 侧边栏 — 底部高光（极淡，几乎透明）
    static let sidebarBottomHighlight = Color.dynamic(
        light: Color.white.opacity(0.12),
        dark: Color.white.opacity(0.05)
    )

    // Liquid Glass 侧边栏 — 淡蓝 tinted glass（3-5% 品牌蓝渗透，Apple tinted glass 风格）
    // 顶部稍重（环境光折射更明显），底部较淡；仅让品牌蓝色轻微渗透背景
    static let sidebarBlueTintTop = Color.dynamic(
        light: Color(red: 91/255, green: 124/255, blue: 255/255).opacity(0.05),
        dark:  Color(red: 91/255, green: 124/255, blue: 255/255).opacity(0.07)
    )
    static let sidebarBlueTintBottom = Color.dynamic(
        light: Color(red: 91/255, green: 124/255, blue: 255/255).opacity(0.02),
        dark:  Color(red: 91/255, green: 124/255, blue: 255/255).opacity(0.03)
    )

    // 导航胶囊间距（呼吸感）
    static let navCapsuleSpacing: CGFloat = 4
    static let navCapsuleHPad: CGFloat    = 10
    static let navCapsuleVPad: CGFloat    = 8

    // 导航胶囊 Hover 背景（极淡玻璃高亮）
    static let navCapsuleHoverBg = Color.dynamic(
        light: Color.white.opacity(0.16),
        dark: Color.white.opacity(0.08)
    )

    // 导航胶囊 Selected — macOS Sequoia 磨砂玻璃（中性灰白）
    // 不使用任何强调色作为底色，仅靠亮度和层级区分状态
    static let navCapsuleSelectedMaterial: NSVisualEffectView.Material = .hudWindow
    // 选中态极淡白色描边（10% 白色，0.5px）— 表现玻璃边缘
    static let navCapsuleSelectedBorder = Color.white.opacity(0.10)
    // 选中态文字：纯白（dark 模式接近 95% 白色）
    static let navCapsuleSelectedText = Color.dynamic(
        light: Color(red: 15/255,  green: 23/255, blue: 42/255),
        dark:  Color(red: 248/255, green: 250/255, blue: 252/255)
    )
    // 选中态强调色（仅用于图标和文字）— 系统蓝
    static let navCapsuleSelectedAccent = Color.dynamic(
        light: Color(red: 0/255,   green: 122/255, blue: 255/255),
        dark:  Color(red: 110/255, green: 188/255, blue: 255/255)
    )
    // 未选中态文字：65-75% 白色透明（dark 模式约 70% 白色）
    static let navCapsuleUnselectedText = Color.dynamic(
        light: Color(red: 100/255, green: 116/255, blue: 139/255),
        dark:  Color.white.opacity(0.70)
    )

    // 外层背景（窗口底色，与侧边栏玻璃形成对比）
    // 跟随系统外观营造「环境光折射」的氛围色
    static let windowBackdrop = Color.dynamic(
        light: Color(red: 235/255, green: 238/255, blue: 245/255),
        dark: Color(red: 18/255, green: 20/255, blue: 28/255)
    )

    // Liquid Glass 强调色（用于系统壁纸动态色彩渗透）
    static let liquidGlassTint = Color.dynamic(
        light: Color(red: 99/255, green: 132/255, blue: 245/255).opacity(0.12),
        dark: Color(red: 99/255, green: 132/255, blue: 245/255).opacity(0.18)
    )

    // 浮起阴影（柔和、扩散较大）
    static let cardShadowRadius: CGFloat = 24
    static let cardShadowY: CGFloat      = 10
    static let cardShadowOpacity: Double = 0.10

    // Tab 栏背景（浅灰 / 深灰）
    static let tabBg = Color.dynamic(
        light: Color.white.opacity(0.15),
        dark: Color(white: 1, opacity: 0.08)
    )
    // 信息提示横幅背景
    static let infoBannerBg = Color.dynamic(
        light: Color.white.opacity(0.18),
        dark: Color(white: 1, opacity: 0.08)
    )
    // 信息提示横幅边框
    static let infoBannerBorder = Color.dynamic(
        light: Color.white.opacity(0.55),
        dark: Color.white.opacity(0.20)
    )
    // 行悬停背景
    static let rowHoverBg = Color.dynamic(
        light: Color.white.opacity(0.18),
        dark: Color(white: 1, opacity: 0.06)
    )
    // 表头背景
    static let tableHeaderBg = Color.dynamic(
        light: Color.white.opacity(0.10),
        dark: Color(white: 1, opacity: 0.04)
    )
    // 内置标签背景
    static let badgeBg = Color.dynamic(
        light: Color.white.opacity(0.18),
        dark: Color(white: 1, opacity: 0.10)
    )
    // 占位符/最浅文字
    static let placeholderText = Color.dynamic(
        light: Color(red: 148/255, green: 163/255, blue: 184/255),
        dark: Color(white: 1, opacity: 0.30)
    )
    // KeyBadge 背景
    static let keyBadgeBg = Color.dynamic(
        light: Color.white.opacity(0.35),
        dark: Color(white: 1, opacity: 0.14)
    )
    // KeyBadge 边框
    static let keyBadgeBorder = Color.dynamic(
        light: Color.white.opacity(0.6),
        dark: Color.white.opacity(0.22)
    )
    // 未选中 Tab / 次要控件文字（与 customSecondaryText 一致）
    static let unselectedTabText = Color.dynamic(
        light: Color(red: 71/255, green: 85/255, blue: 105/255),
        dark: Color(red: 156/255, green: 163/255, blue: 175/255)
    )
    // 未选中格式 Badge 背景
    static let unselectedBadgeBg = Color.dynamic(
        light: Color.white.opacity(0.20),
        dark: Color(white: 1, opacity: 0.08)
    )
    // 未安装应用图标占位背景
    static let appIconPlaceholderBg = Color.dynamic(
        light: Color.white.opacity(0.20),
        dark: Color(white: 1, opacity: 0.08)
    )
    // 空态图片占位背景
    static let emptyImagePlaceholderBg = Color.dynamic(
        light: Color.white.opacity(0.20),
        dark: Color(white: 1, opacity: 0.08)
    )
}

// MARK: - 侧边栏导航项

enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case general         = "general"
    case screenshot      = "screenshot"
    case recording       = "recording"
    case audioRecording  = "audioRecording"
    case pinAndColor     = "pinAndColor"
    case contextMenu     = "contextMenu"
    case shortcuts       = "shortcuts"
    case about           = "about"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .general:         return "通用".localized
        case .screenshot:      return "截图与标注".localized
        case .recording:       return "屏幕录制".localized
        case .audioRecording:  return "音频录制".localized
        case .pinAndColor:     return "贴图 & 取色".localized
        case .contextMenu:     return "Finder 右键".localized
        case .shortcuts:       return "快捷键".localized
        case .about:           return "关于".localized
        }
    }

    var symbolName: String {
        switch self {
        case .general:         return "gearshape"
        case .screenshot:      return "camera.viewfinder"
        case .recording:       return "record.circle"
        case .audioRecording:  return "waveform.circle.fill"
        case .pinAndColor:     return "pin.circle"
        case .contextMenu:     return "folder.badge.gearshape"
        case .shortcuts:       return "keyboard"
        case .about:           return "info.circle"
        }
    }
}

// MARK: - 侧边栏导航项组件

private struct SidebarNavItem: View {
    let dest: SettingsDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: dest.symbolName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, height: 20)

                Text(dest.localizedTitle)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(textColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DT.navCapsuleHPad)
            .padding(.vertical, DT.navCapsuleVPad)
            .frame(maxWidth: .infinity)
            .background(capsuleBackground)
            .overlay(capsuleBorder)
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.20), value: isSelected)
        .accessibilityLabel(dest.localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconColor: Color {
        if isSelected {
            return DT.navCapsuleSelectedAccent
        }
        return isHovered ? .customMediumText : DT.navCapsuleUnselectedText
    }

    private var textColor: Color {
        if isSelected {
            return DT.navCapsuleSelectedAccent
        }
        return isHovered ? .customMediumText : DT.navCapsuleUnselectedText
    }

    @ViewBuilder
    private var capsuleBackground: some View {
        if isSelected {
            ZStack {
                // 1. 真实毛玻璃基底（NSVisualEffectView .hudWindow）
                // 制造 18-24px 背景模糊，参考 macOS 系统设置侧边栏
                VisualEffectView(
                    material: DT.navCapsuleSelectedMaterial,
                    blendingMode: .withinWindow,
                    state: .active
                )
                .clipShape(Capsule(style: .continuous))

                // 2. 极淡白色叠加（8%）— 让玻璃层可识别但不抢戏
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        } else if isHovered {
            Capsule(style: .continuous)
                .fill(DT.navCapsuleHoverBg)
        } else {
            Capsule(style: .continuous)
                .fill(Color.clear)
        }
    }

    @ViewBuilder
    private var capsuleBorder: some View {
        if isSelected {
            // 极淡白色描边（10% 白色，0.5px）— 仅表现玻璃边缘
            Capsule(style: .continuous)
                .stroke(DT.navCapsuleSelectedBorder, lineWidth: 0.5)
        } else {
            Capsule(style: .continuous)
                .stroke(Color.clear, lineWidth: 0.5)
        }
    }
}

// MARK: - 内容区顶部 Header

struct SettingsPageHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.customPrimaryText)
    }
}

// MARK: - 设计卡片容器

struct DesignCard<Content: View>: View {
    let content: Content
    @ObservedObject private var settings = AppSettings.shared

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            ZStack {
                if settings.enableGlassEffect {
                    VisualEffectView(material: .contentBackground, blendingMode: .withinWindow)
                }
                DT.cardBg.opacity(settings.glassOpacity)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous))
        .overlay(
            // 1px 高光边框：顶部稍亮、底部稍暗，模拟玻璃边缘的折射高光
            RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(settings.enableGlassEffect ? 0.60 : 0.35),
                            Color.white.opacity(settings.enableGlassEffect ? 0.18 : 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(settings.enableGlassEffect ? 0.18 : 0.08),
            radius: settings.enableGlassEffect ? 24 : 8,
            x: 0,
            y: settings.enableGlassEffect ? 10 : 2
        )
    }
}

// 保持旧名兼容
typealias WhiteCard = DesignCard

// MARK: - 设计卡片行分隔线

struct CardDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, DT.rowPadH)
    }
}

// MARK: - 段落标题

struct SectionLabel: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.customMediumText)
        }
    }
}

// MARK: - MainWindow

struct MainWindow: View {
    @State private var selectedDestination: SettingsDestination? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            // ── Liquid Glass 窗口背景（系统毛玻璃 + 环境光折射 + 动态色彩渗透） ──
            LiquidGlassBackdrop()

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selectedDestination: $selectedDestination)
                    .navigationSplitViewColumnWidth(min: DT.sidebarWidth,
                                                    ideal: DT.sidebarWidth,
                                                    max: DT.sidebarWidth)
            } detail: {
                DetailView(selectedDestination: $selectedDestination)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(minWidth: 820, idealWidth: 880, minHeight: 540, idealHeight: 600)
        .background(WindowAppearanceSync(appearance: settings.appAppearance))
        .preferredColorScheme(settings.appAppearance == "light" ? .light : (settings.appAppearance == "dark" ? .dark : nil))
    }
}

// MARK: - 侧边栏

private struct SidebarView: View {
    @Binding var selectedDestination: SettingsDestination?
    @ObservedObject private var permMgr = PermissionManager.shared
    @AppStorage("isFinderEnabled") private var isFinderEnabled: Bool = false
    @ObservedObject private var settings = AppSettings.shared

    private var allGranted: Bool {
        permMgr.hasScreenRecordingPermission && permMgr.hasAccessibilityPermission && isFinderEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 59/255, green: 130/255, blue: 246/255),
                                         Color(red: 99/255, green: 102/255, blue: 241/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .shadow(color: DT.accent.opacity(0.35), radius: 4, x: 0, y: 2)

                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text("SnapClick".localized)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.customPrimaryText)
                    Text("v\(UpdateChecker.shared.currentVersion)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DT.groupLabel)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 22)

            VStack(spacing: DT.navCapsuleSpacing) {
                ForEach(SettingsDestination.allCases) { dest in
                    SidebarNavItem(dest: dest, isSelected: selectedDestination == dest) {
                        selectedDestination = dest
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Circle()
                    .fill(allGranted ? DT.successGreen : DT.warningOrange)
                    .frame(width: 6, height: 6)
                Text(allGranted ? "全部已授权".localized : "存在未授权项".localized)
                    .font(.system(size: 10.5))
                    .foregroundStyle(allGranted ? DT.successGreen : DT.warningOrange)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(width: DT.sidebarWidth)
        .background(sidebarGlassBackground)
    }

    @ViewBuilder
    private var sidebarGlassBackground: some View {
        ZStack {
            if settings.enableGlassEffect {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                DT.sidebarGlassOverlay
                    .opacity(settings.glassOpacity)
                LinearGradient(
                    colors: [
                        Color.white.opacity(settings.enableGlassEffect ? 0.12 * settings.glassOpacity : 0.04),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                // Apple tinted glass：3-5% 品牌蓝从顶部渗透到底部，
                // 极低饱和度，仅在仔细观察时透出冷调蓝
                LinearGradient(
                    colors: [DT.sidebarBlueTintTop, DT.sidebarBlueTintBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(settings.glassOpacity)
            } else {
                Color.dynamic(
                    light: Color(white: 0.97),
                    dark: Color(white: 0.16)
                )
            }
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [
                    DT.sidebarTopHighlight,
                    DT.sidebarBottomHighlight
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

// MARK: - 内容详情区

private struct DetailView: View {
    @Binding var selectedDestination: SettingsDestination?
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            if let dest = selectedDestination {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        SettingsPageHeader(title: dest.localizedTitle)

                        switch dest {
                        case .general:
                            GeneralSettingsView(selectedDestination: $selectedDestination)
                        case .screenshot:
                            ScreenshotSettingsView()
                        case .recording:
                            RecordingSettingsView()
                        case .audioRecording:
                            AudioRecordingSettingsView()
                        case .pinAndColor:
                            PinColorSettingsView()
                        case .contextMenu:
                            RightClickSettingsView()
                        case .shortcuts:
                            ShortcutsSettingsView()
                        case .about:
                            AboutView()
                        }
                    }
                    .padding(.horizontal, DT.contentPadding)
                    .padding(.bottom, DT.contentPadding)
                    .padding(.top, DT.contentPadding + 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ScrollViewConfigurator())
                }
                .scrollContentBackground(.hidden)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("请从左侧选择设置项".localized)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// MARK: - 通用设置页

private struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permMgr = PermissionManager.shared
    @Binding var selectedDestination: SettingsDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {

            // ── 权限状态 ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "权限状态".localized, icon: "lock.shield", color: .blue)

                DesignCard {
                    PermissionRow(
                        icon: "video.badge.checkmark",
                        iconColor: .blue,
                        title: "屏幕录制".localized,
                        description: "区域截图及取色所需".localized,
                        isGranted: permMgr.hasScreenRecordingPermission,
                        onAction: { permMgr.requestScreenRecordingPermission() }
                    )

                    CardDivider()

                    PermissionRow(
                        icon: "accessibility",
                        iconColor: .purple,
                        title: "辅助功能".localized,
                        description: "全局快捷键拦截所需".localized,
                        isGranted: permMgr.hasAccessibilityPermission,
                        onAction: { permMgr.requestAccessibilityPermission() }
                    )

                    CardDivider()

                    PermissionRow(
                        icon: "folder.badge.gearshape",
                        iconColor: Color(red: 20/255, green: 184/255, blue: 166/255),
                        title: "Finder 扩展".localized,
                        description: "右键菜单与图标覆盖所需".localized,
                        isGranted: permMgr.hasFinderExtensionPermission,
                        actionLabel: "去启用".localized,
                        onAction: { permMgr.requestFinderExtensionPermission() }
                    )

                    CardDivider()

                    // ── 可选权限：完全磁盘访问 ──────────────────────────
                    OptionalPermissionRow(
                        icon: "externaldrive.badge.checkmark",
                        iconColor: .orange,
                        title: "完全磁盘访问".localized,
                        description: "可选 · 用于访问外接磁盘中的文件".localized,
                        isGranted: permMgr.hasFullDiskAccessPermission,
                        onAction: { permMgr.requestFullDiskAccessPermission() }
                    )
                }

                // 重新检测按钮
                HStack {
                    Spacer()
                    Button {
                        permMgr.refreshAllPermissions()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .rotationEffect(.degrees(permMgr.isRefreshing ? 360 : 0))
                                .animation(
                                    permMgr.isRefreshing
                                        ? .linear(duration: 0.7).repeatForever(autoreverses: false)
                                        : .default,
                                    value: permMgr.isRefreshing
                                )
                            Text(permMgr.isRefreshing ? "检测中…".localized : "重新检测".localized)
                                .font(.system(size: 11.5, weight: .medium))
                                .animation(.none, value: permMgr.isRefreshing)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(permMgr.isRefreshing ? DT.accent.opacity(0.7) : .secondary)
                    .disabled(permMgr.isRefreshing)
                    .padding(.top, 2)
                }
            }

            // ── 启动与可见性 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "启动与可见性".localized, icon: "power.circle", color: .green)

                DesignCard {
                    ToggleRow(
                        title: "开机自启动".localized,
                        description: "登录时自动启动 SnapClick".localized,
                        isOn: $settings.launchAtLogin
                    )
                    CardDivider()
                    ToggleRow(
                        title: "在程序坞中显示图标".localized,
                        description: "在下方程序坞中显示应用图标".localized,
                        isOn: $settings.showInDock
                    )
                }
            }

            // ── 语言与外观 ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "语言与外观".localized, icon: "globe", color: .orange)

                DesignCard {
                    // 系统语言
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("系统语言".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.customPrimaryText)
                            Text("界面及菜单呈现语言".localized)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.appLanguage) {
                            Text("简体中文").tag("zh-CN")
                            Text("English (US)").tag("en")
                            Text("日本語").tag("ja")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .padding(.horizontal, DT.rowPadH)
                    .padding(.vertical, DT.rowPadV)

                    CardDivider()

                    // 外观模式
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("外观模式".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.customPrimaryText)
                            Text("界面颜色主题偏好".localized)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 0) {
                            AppearanceModeButton(
                                label: "Light",
                                icon: "sun.max",
                                isSelected: settings.appAppearance == "light"
                            ) { settings.appAppearance = "light" }

                            AppearanceModeButton(
                                label: "Dark",
                                icon: "moon",
                                isSelected: settings.appAppearance == "dark"
                            ) { settings.appAppearance = "dark" }

                            AppearanceModeButton(
                                label: "Auto",
                                icon: "circle.lefthalf.filled",
                                isSelected: settings.appAppearance == "auto"
                            ) { settings.appAppearance = "auto" }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.customControlBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(DT.cardBorder, lineWidth: 0.5)
                                )
                        )
                    }
                    .padding(.horizontal, DT.rowPadH)
                    .padding(.vertical, DT.rowPadV)

                    CardDivider()

                    ToggleRow(
                        title: "毛玻璃效果".localized,
                        description: "使窗口背景呈现半透明的玻璃质感".localized,
                        isOn: $settings.enableGlassEffect
                    )
                }
            }
        }
    }
}

// MARK: - 权限状态行

private struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    var actionLabel: String? = nil
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.customPrimaryText)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.successGreen)
                    Text("已授权".localized)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(DT.successGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(DT.successGreen.opacity(0.1))
                        .overlay(Capsule().stroke(DT.successGreen.opacity(0.2), lineWidth: 0.75))
                )
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DT.warningOrange)
                    Text("未授权".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(DT.warningOrange)
                }

                Button(actionLabel ?? "去授权".localized) { onAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DT.accent)
            }
        }
        .padding(.horizontal, DT.rowPadH)
        .padding(.vertical, DT.rowPadV)
    }
}

// MARK: - 可选权限行（视觉上区别于强制权限）

private struct OptionalPermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.customPrimaryText)
                    // "可选" 标签
                    Text("可选".localized)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.orange.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.12))
                                .overlay(Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 0.75))
                        )
                }
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.successGreen)
                    Text("已授权".localized)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(DT.successGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(DT.successGreen.opacity(0.1))
                        .overlay(Capsule().stroke(DT.successGreen.opacity(0.2), lineWidth: 0.75))
                )
            } else {
                Button("去开启".localized) { onAction() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
            }
        }
        .padding(.horizontal, DT.rowPadH)
        .padding(.vertical, DT.rowPadV)
    }
}

// MARK: - Toggle 行

struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.customPrimaryText)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, DT.rowPadH)
        .padding(.vertical, DT.rowPadV)
    }
}

// MARK: - 外观模式按钮

private struct AppearanceModeButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .customSecondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? DT.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 截图与标注设置页

private struct ScreenshotSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {

            // ── 实时预览区 ──────────────────────────────────────────
            LivePreviewCard(
                hasRoundCorner: settings.screenshotAddRoundCorner,
                cornerRadius: settings.screenshotCornerRadius,
                hasShadow: settings.screenshotAddShadow
            )

            // ── 两列设置区 ──────────────────────────────────────────
            HStack(alignment: .top, spacing: 16) {
                // 左列：外观美化
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "截图外观".localized, icon: "paintbrush.pointed", color: .purple)

                    DesignCard {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("圆角半径".localized)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Corner Radius")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(settings.screenshotCornerRadius)) px")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DT.accent)
                                    .frame(width: 46, alignment: .trailing)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.top, DT.rowPadV)

                            Slider(value: $settings.screenshotCornerRadius, in: 0...32, step: 1)
                                .padding(.horizontal, DT.rowPadH)
                                .padding(.bottom, DT.rowPadV)
                                .tint(DT.accent)

                            CardDivider()

                            ToggleRow(
                                title: "添加阴影".localized,
                                description: "为截图添加投影效果".localized,
                                isOn: $settings.screenshotAddShadow
                            )

                            CardDivider()

                            ToggleRow(
                                title: "窗口透明".localized,
                                description: "保留截图原始透明度".localized,
                                isOn: $settings.screenshotAddRoundCorner
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // 右列：保存路径与格式
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "储存设置".localized, icon: "internaldrive", color: .teal)

                    DesignCard {
                        VStack(spacing: 0) {
                            // 保存路径
                            VStack(alignment: .leading, spacing: 8) {
                                Text("保存位置".localized)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DT.accent)
                                        Text(URL(fileURLWithPath: settings.screenshotSavePath).lastPathComponent)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(.customControlBg)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(DT.cardBorder, lineWidth: 0.5)
                                            )
                                    )

                                    Button("更改…".localized) {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = false
                                        panel.canChooseDirectories = true
                                        panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK, let url = panel.url {
                                            SandboxManager.shared.saveBookmark(for: url)
                                            settings.screenshotSavePath = url.path
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.top, DT.rowPadV)
                            .padding(.bottom, 10)

                            CardDivider()

                            // 格式选择
                            VStack(alignment: .leading, spacing: 8) {
                                Text("默认格式".localized)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 6) {
                                    ForEach(["PNG", "JPG", "PDF", "HEIF"], id: \.self) { fmt in
                                        FormatBadge(format: fmt, isSelected: settings.screenshotFormat == fmt) {
                                            settings.screenshotFormat = fmt
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

        }
    }
}

// MARK: - 截图实时预览卡

private struct LivePreviewCard: View {
    let hasRoundCorner: Bool
    let cornerRadius: Double
    let hasShadow: Bool

    var body: some View {
        ZStack {
            // 背景渐变
            RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 224/255, green: 231/255, blue: 255/255),
                            Color(red: 219/255, green: 234/255, blue: 254/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                        .stroke(Color(red: 196/255, green: 214/255, blue: 254/255), lineWidth: 0.75)
                )

            // 标签
            VStack(alignment: .leading) {
                HStack {
                    Text("实时预览".localized)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 99/255, green: 102/255, blue: 241/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(red: 238/255, green: 242/255, blue: 255/255))
                                .overlay(Capsule().stroke(Color(red: 199/255, green: 210/255, blue: 254/255), lineWidth: 0.5))
                        )
                    Spacer()
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // 模拟截图
                HStack {
                    Spacer()
                    MockScreenshotView(
                        cornerRadius: hasRoundCorner ? cornerRadius : 0,
                        hasShadow: hasShadow
                    )
                    Spacer()
                }
                .padding(.vertical, 16)
            }
        }
        .frame(height: 160)
    }
}

private struct MockScreenshotView: View {
    let cornerRadius: Double
    let hasShadow: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 6) {
                Circle().fill(Color(red: 255/255, green: 95/255, blue: 87/255)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 255/255, green: 189/255, blue: 46/255)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 40/255, green: 200/255, blue: 64/255)).frame(width: 10, height: 10)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 240/255, green: 240/255, blue: 240/255))

            // 内容
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(height: 8).frame(maxWidth: 160)
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15)).frame(height: 6).frame(maxWidth: 120)
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.gray.opacity(0.2))
                    .padding(.top, 4)
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .frame(width: 200)
        .clipShape(RoundedRectangle(cornerRadius: max(cornerRadius, 4), style: .continuous))
        .shadow(
            color: hasShadow ? Color.black.opacity(0.18) : Color.clear,
            radius: hasShadow ? 12 : 0,
            x: 0,
            y: hasShadow ? 6 : 0
        )
    }
}

// MARK: - 格式 Badge

private struct FormatBadge: View {
    let format: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(format)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .customSecondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? DT.accent : .customControlBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isSelected ? DT.accent : DT.cardBorder, lineWidth: 0.75)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 快捷键卡片

struct ShortcutCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var hotkey: String

    var body: some View {
        DesignCard {
            VStack(spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(iconColor.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundStyle(iconColor)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.customPrimaryText)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HotkeyRecorderView(hotkey: $hotkey)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
        }
    }
}

// MARK: - 快捷键录制组件

struct HotkeyRecorderView: View {
    @Binding var hotkey: String
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: {
            if isRecording { stopRecording() } else { startRecording() }
        }) {
            HStack(spacing: 4) {
                if isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("按下组合键…".localized)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DT.accent)
                } else if hotkey.isEmpty {
                    Text("点击录制".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    // 显示键盘按键样式
                    ForEach(hotkey.split(separator: "+").map(String.init), id: \.self) { key in
                        KeyBadge(key: key.uppercased())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecording ? DT.accent.opacity(0.08) : .customControlBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isRecording ? DT.accent.opacity(0.4) : DT.cardBorder, lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("录制快捷键"))
        .accessibilityValue(Text(hotkey.isEmpty ? "未设置" : hotkey))
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            var keys: [String] = []

            if modifiers.contains(.control) { keys.append("ctrl") }
            if modifiers.contains(.option)  { keys.append("option") }
            if modifiers.contains(.shift)   { keys.append("shift") }
            if modifiers.contains(.command) { keys.append("cmd") }

            let isModifierOnly = [54, 55, 56, 58, 59, 60, 61, 62].contains(Int(keyCode))
            if !isModifierOnly {
                let specialKeys: [UInt16: String] = [
                    49: "space", 36: "enter", 48: "tab",
                    126: "up", 125: "down", 123: "left", 124: "right", 53: "esc",
                    122: "f1", 120: "f2", 99: "f3", 118: "f4",
                    96: "f5", 97: "f6", 98: "f7", 100: "f8",
                    101: "f9", 109: "f10", 103: "f11", 111: "f12"
                ]
                let keyStr: String
                if let special = specialKeys[keyCode] {
                    keyStr = special
                } else if let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty {
                    keyStr = chars
                } else {
                    keyStr = ""
                }
                if !keyStr.isEmpty {
                    keys.append(keyStr)
                    self.hotkey = keys.joined(separator: "+")
                    self.stopRecording()
                    return nil
                }
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - 键盘按键样式

struct KeyBadge: View {
    let key: String

    private var displayKey: String {
        switch key.lowercased() {
        case "cmd", "command": return "⌘"
        case "shift":          return "⇧"
        case "option", "opt":  return "⌥"
        case "ctrl", "control":return "⌃"
        case "enter":          return "↵"
        case "space":          return "Space"
        case "tab":            return "⇥"
        case "esc":            return "Esc"
        default:               return key
        }
    }

    var body: some View {
        Text(displayKey)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.customMediumText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DT.keyBadgeBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(DT.keyBadgeBorder, lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 0, x: 0, y: 1)
            )
    }
}

// MARK: - 关于页

private struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {

            // App 图标 + 名称
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 59/255, green: 130/255, blue: 246/255),
                                         Color(red: 99/255, green: 102/255, blue: 241/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: DT.accent.opacity(0.3), radius: 10, x: 0, y: 5)

                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("SnapClick")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.customPrimaryText)
                    Text(String(format: "版本 %@".localized, UpdateChecker.shared.currentVersion))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("官方网站".localized) {
                            if let url = URL(string: "http://snapclick.cn/") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("检查更新".localized) {
                            UpdateChecker.shared.checkForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(DT.accent)
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }

            // 功能卡片 2×2
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                FeatureCard(
                    icon: "contextualmenu.and.cursorarrow",
                    iconColor: .blue,
                    title: "右键增强".localized,
                    description: "强化右键菜单，支持可编程快捷操作与快速新建。".localized
                )
                FeatureCard(
                    icon: "camera.viewfinder",
                    iconColor: .indigo,
                    title: "截图标注".localized,
                    description: "像素级区域截图，内置即时标注与 OCR 提取。".localized
                )
                FeatureCard(
                    icon: "record.circle",
                    iconColor: .red,
                    title: "屏幕录制".localized,
                    description: "高性能屏幕录制，支持音频路由与 GIF 导出。".localized
                )
                FeatureCard(
                    icon: "eyedropper.halffull",
                    iconColor: Color(red: 20/255, green: 184/255, blue: 166/255),
                    title: "取色器".localized,
                    description: "从屏幕任意位置拾取颜色，支持多格式输出。".localized
                )
            }

            // 版权信息
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("© 2026 SnapClick Team. All rights reserved.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("专为 macOS 打造的原生效率工具集".localized)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - 功能特性卡片

private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    @State private var isHovered = false

    var body: some View {
        DesignCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.customPrimaryText)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(14)
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}


// MARK: - 屏幕录制设置页

private struct RecordingSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {

            // ── 仿选区交互态预览卡 ───────────────────────────────────
            RecordingPreviewCard()

            // ── 录制范围 ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "录制范围".localized, icon: "viewfinder.rectangular", color: .red)

                HStack(spacing: 12) {
                    RecordingModeCard(
                        icon: "crop",
                        iconColor: .red,
                        title: "选区录制".localized,
                        subtitle: "单击选取录制区域".localized,
                        isSelected: settings.recordDefaultMode == "area",
                        action: {
                            updateRecordingMode("area")
                        }
                    )
                    RecordingModeCard(
                        icon: "display",
                        iconColor: Color(red: 99/255, green: 102/255, blue: 241/255),
                        title: "全屏录制".localized,
                        subtitle: "立即录制全屏".localized,
                        isSelected: settings.recordDefaultMode == "screen",
                        action: {
                            updateRecordingMode("screen")
                        }
                    )
                    RecordingModeCard(
                        icon: "macwindow",
                        iconColor: .teal,
                        title: "应用窗口".localized,
                        subtitle: "选取目标窗口".localized,
                        isSelected: settings.recordDefaultMode == "window",
                        action: {
                            updateRecordingMode("window")
                        }
                    )
                }
            }

            // ── 两列布局 ─────────────────────────────────────────────
            HStack(alignment: .top, spacing: 16) {

                // 左列 — 视频参数
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "视频参数".localized, icon: "film.stack", color: .indigo)

                    DesignCard {
                        VStack(spacing: 0) {

                            // 清晰度（与 HUD 共用 recordQuality，设置面板调档位后 HUD 打开时直接同步显示）
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("清晰度".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Recording Quality")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.recordQuality) {
                                    Text("标清".localized).tag("标清")
                                    Text("超清".localized).tag("超清")
                                    Text("原画".localized).tag("原画")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 110)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 帧率
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("帧率".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Frame Rate (FPS)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 0) {
                                    ForEach([30, 60, 120], id: \.self) { fps in
                                        Button {
                                            settings.recordFPS = fps
                                        } label: {
                                            Text("\(fps)")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(settings.recordFPS == fps ? .white : .customSecondaryText)
                                                .frame(width: 36, height: 26)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                        .fill(settings.recordFPS == fps ? DT.accent : Color.clear)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(3)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(.customControlBg)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(DT.cardBorder, lineWidth: 0.5)
                                        )
                                )
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 视频格式
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("视频格式".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Output Format")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    ForEach(["MOV", "MP4"], id: \.self) { fmt in
                                        FormatBadge(format: fmt, isSelected: settings.recordFormat == fmt) {
                                            settings.recordFormat = fmt
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 编解码
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("编解码".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Video Codec")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    ForEach(["H.264", "HEVC"], id: \.self) { codec in
                                        FormatBadge(format: codec, isSelected: settings.recordCodec == codec) {
                                            settings.recordCodec = codec
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // 右列 — 音频 & 高级
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "音频与高级".localized, icon: "waveform.circle", color: .orange)

                    DesignCard {
                        VStack(spacing: 0) {

                            // 系统声音
                            ToggleRow(
                                title: "系统声音".localized,
                                description: "录制系统内部声音（macOS 13+）".localized,
                                isOn: $settings.recordSystemAudio
                            )

                            CardDivider()

                            // 麦克风
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("麦克风".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Microphone Input")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.recordMicrophone) {
                                    Text("无".localized).tag("无")
                                    Text("内置麦克风").tag("内置麦克风")
                                    Text("外置 USB").tag("外置 USB")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 110)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 定时录制
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("定时录制".localized)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.customPrimaryText)
                                    Text("Countdown Timer")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $settings.recordTimer) {
                                    Text("关闭".localized).tag(0)
                                    Text("3 秒").tag(3)
                                    Text("5 秒").tag(5)
                                    Text("10 秒").tag(10)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 80)
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.vertical, DT.rowPadV)

                            CardDivider()

                            // 鼠标高亮
                            ToggleRow(
                                title: "鼠标高亮".localized,
                                description: "录制时高亮显示鼠标光标位置".localized,
                                isOn: $settings.recordHighlightCursor
                            )

                            CardDivider()

                            // 保存位置
                            VStack(alignment: .leading, spacing: 8) {
                                Text("保存位置".localized)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.red)
                                        Text(URL(fileURLWithPath: settings.recordSavePath).lastPathComponent)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(.customControlBg)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(DT.cardBorder, lineWidth: 0.5)
                                            )
                                    )

                                    Button("更改…".localized) {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = false
                                        panel.canChooseDirectories = true
                                        panel.allowsMultipleSelection = false
                                        if panel.runModal() == .OK, let url = panel.url {
                                            settings.recordSavePath = url.path
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, DT.rowPadH)
                            .padding(.top, DT.rowPadV)
                            .padding(.bottom, DT.rowPadV)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func updateRecordingMode(_ mode: String) {
        settings.recordDefaultMode = mode
    }
}

// MARK: - 录制预览卡（仿 Stitch 选区交互态）

private struct RecordingPreviewCard: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // 背景：暗色桌面蒙层
            RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 30/255, green: 27/255, blue: 75/255),
                            Color(red: 49/255, green: 46/255, blue: 129/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                        .stroke(Color(red: 67/255, green: 56/255, blue: 202/255).opacity(0.4), lineWidth: 0.75)
                )

            // 半透明遮罩（模拟桌面被蒙住）
            RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                .fill(Color.black.opacity(0.35))

            VStack(spacing: 0) {
                // 顶部标签行
                HStack {
                    Label("录制预览".localized, systemImage: "record.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 252/255, green: 165/255, blue: 165/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.15))
                                .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 0.5))
                        )
                    Spacer()
                    // 录制状态点
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulse ? 1.3 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: pulse
                            )
                        Text("REC")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // 选区演示区
                Spacer()

                ZStack {
                    // 选区边框（蓝色，仿 Stitch 样式）
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color(red: 0, green: 112/255, blue: 235/255), lineWidth: 1.5)
                        .frame(width: 200, height: 76)

                    // 尺寸 Tooltip（左上角）
                    VStack {
                        HStack {
                            Text("1920 × 1080")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color(red: 0, green: 112/255, blue: 235/255))
                                )
                                .offset(x: 0, y: -13)
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: 200, height: 76)

                    // 四角手柄
                    SelectionHandlesView(width: 200, height: 76)
                }

                Spacer()

                // 底部浮动控制条（仿 Stitch 样式）
                HStack(spacing: 16) {
                    // 分辨率标签
                    VStack(spacing: 3) {
                        Text("RESOLUTION")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("4K UHD")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    RecordingPreviewDivider()

                    // 帧率标签
                    VStack(spacing: 3) {
                        Text("FPS")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("60 fps")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    RecordingPreviewDivider()

                    // 麦克风图标
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))

                    RecordingPreviewDivider()

                    // 系统声音图标
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0, green: 112/255, blue: 235/255))

                    RecordingPreviewDivider()

                    // 定时图标
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Off")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // 录制按钮（红色）
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2.5)
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(Color(red: 186/255, green: 26/255, blue: 26/255))
                            .frame(width: 26, height: 26)
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.7))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.75)
                        )
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .frame(height: 200)
        .onAppear { pulse = true }
        .clipShape(RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous))
    }
}

// MARK: - 选区控制手柄

private struct SelectionHandlesView: View {
    let width: CGFloat
    let height: CGFloat

    private let handleSize: CGFloat = 6
    private let handleColor = Color(red: 0, green: 112/255, blue: 235/255)

    var body: some View {
        ZStack {
            // 四角
            handle(x: -(width / 2), y: -(height / 2))
            handle(x:  (width / 2), y: -(height / 2))
            handle(x: -(width / 2), y:  (height / 2))
            handle(x:  (width / 2), y:  (height / 2))
            // 四边中点
            handle(x: 0,            y: -(height / 2))
            handle(x: 0,            y:  (height / 2))
            handle(x: -(width / 2), y: 0)
            handle(x:  (width / 2), y: 0)
        }
    }

    private func handle(x: CGFloat, y: CGFloat) -> some View {
        Rectangle()
            .fill(handleColor)
            .frame(width: handleSize, height: handleSize)
            .overlay(
                Rectangle()
                    .stroke(Color.white, lineWidth: 0.75)
            )
            .offset(x: x, y: y)
    }
}

// MARK: - 录制预览分隔线

private struct RecordingPreviewDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 20)
    }
}

// MARK: - 录制模式卡片

private struct RecordingModeCard: View {
    @ObservedObject private var settings = AppSettings.shared
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? iconColor.opacity(0.15) : iconColor.opacity(0.08))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .customPrimaryText : .customSecondaryText)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                    .fill(DT.cardBg.opacity(settings.glassOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                            .fill(isSelected ? Color.clear : (hovered ? Color.primary.opacity(0.03) : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                            .stroke(isSelected ? iconColor.opacity(0.5) : DT.cardBorder, lineWidth: isSelected ? 1.5 : 0.75)
                    )
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered in
            hovered = isHovered
            if isHovered {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}


// MARK: - Color Extension for Dynamic Dark Mode
extension Color {
    static func dynamic(light: Color, dark: Color) -> Color {
        return Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(dark)
            } else {
                return NSColor(light)
            }
        })
    }
    
    static let customPrimaryText = Color.dynamic(
        light: Color(red: 15/255, green: 23/255, blue: 42/255),
        dark: Color(red: 243/255, green: 244/255, blue: 246/255)
    )
    static let customMediumText = Color.dynamic(
        light: Color(red: 30/255, green: 41/255, blue: 59/255),
        dark: Color(red: 229/255, green: 231/255, blue: 235/255)
    )
    static let customSecondaryText = Color.dynamic(
        light: Color(red: 71/255, green: 85/255, blue: 105/255),
        dark: Color(red: 156/255, green: 163/255, blue: 175/255)
    )
    static let customControlBg = Color.dynamic(
        light: Color.white.opacity(0.20),
        dark: Color(white: 1, opacity: 0.08)
    )
}

extension ShapeStyle where Self == Color {
    static var customPrimaryText: Color { Color.customPrimaryText }
    static var customMediumText: Color { Color.customMediumText }
    static var customSecondaryText: Color { Color.customSecondaryText }
    static var customControlBg: Color { Color.customControlBg }
}

// MARK: - 自定义滚动条

class CustomScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool {
        return true
    }

    override func drawKnob() {
        guard let window = self.window else { return }
        let knobRect = rect(for: .knob)
        if knobRect.isEmpty { return }
        
        // 限制宽度与边距，使滑块变得更纤细、更精致
        let insetRect = knobRect.insetBy(dx: 4.5, dy: 2)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 3, yRadius: 3)
        
        let isDark = window.appearance?.name.rawValue.contains("dark") ?? false
        let color = isDark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.12)
            
        color.set()
        path.fill()
    }
    
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // 背景轨道不画任何东西，保持透明，减少视觉干扰
    }
}

class ScrollViewConfiguratorNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window != nil {
            if let scrollView = self.enclosingScrollView {
                scrollView.hasVerticalScroller = true
                scrollView.drawsBackground = false
                if !(scrollView.verticalScroller is CustomScroller) {
                    let customScroller = CustomScroller()
                    scrollView.verticalScroller = customScroller
                }
            }
        }
    }
}

struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return ScrollViewConfiguratorNSView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
