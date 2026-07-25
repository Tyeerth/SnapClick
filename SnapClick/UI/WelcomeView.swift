import SwiftUI

// MARK: - WelcomeView

/// 首次启动权限引导页
struct WelcomeView: View {

    let onComplete: () -> Void

    @ObservedObject private var permission = PermissionManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @AppStorage("isFinderEnabled") private var isFinderEnabled: Bool = false

    private func handleComplete() {
        onComplete()
        if let welcome = NSApp.windows.first(where: { $0.title.contains("欢迎使用 SnapClick") }) {
            welcome.performClose(nil)
        } else {
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
        }
    }

    private var grantedCount: Int {
        var count = 0
        if permission.hasScreenRecordingPermission { count += 1 }
        if permission.hasAccessibilityPermission   { count += 1 }
        if isFinderEnabled                          { count += 1 }
        return count
    }

    var body: some View {
        ZStack {
            // ── Liquid Glass 窗口底面背景（与主窗口保持一致） ──────────────────
            LiquidGlassBackdrop()

            HStack(spacing: 0) {

                // ── 左侧侧边栏 ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {

                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 59/255, green: 130/255, blue: 246/255),
                                            Color(red: 99/255, green: 102/255, blue: 241/255)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)
                                .shadow(color: DT.accent.opacity(0.4), radius: 4, x: 0, y: 2)

                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 15, weight: .bold))
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
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                    // 伪导航菜单（与主窗口视觉一致）
                    VStack(spacing: 2) {
                        WelcomeSidebarItem(icon: "gearshape",         title: "通用",       isActive: true)
                        WelcomeSidebarItem(icon: "folder.badge.gearshape", title: "Finder 右键")
                        WelcomeSidebarItem(icon: "camera.viewfinder", title: "截图与标注")
                        WelcomeSidebarItem(icon: "pin.circle",        title: "贴图 & 取色")
                    }
                    .padding(.horizontal, 8)

                    Spacer()

                    // 进度面板
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("SETUP PROGRESS".localized)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DT.accent)
                                .tracking(0.5)
                            Spacer()
                            Text("\(grantedCount) / 3")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [DT.accent, Color(red: 99/255, green: 102/255, blue: 241/255)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(grantedCount) / 3.0, height: 5)
                                    .animation(.spring(response: 0.4), value: grantedCount)
                            }
                        }
                        .frame(height: 5)

                        Text(grantedCount == 3 ? "所有权限已就绪 ✓".localized : "\(grantedCount) / 3 已授权".localized)
                            .font(.system(size: 10.5))
                            .foregroundStyle(grantedCount == 3 ? DT.successGreen : Color.secondary)
                    }
                    .padding(14)
                    .background(
                        ZStack {
                            if settings.enableGlassEffect {
                                VisualEffectView(material: .contentBackground, blendingMode: .withinWindow)
                            }
                            Color.dynamic(
                                light: Color.white.opacity(0.18),
                                dark: Color(white: 1, opacity: 0.08)
                            )
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(settings.enableGlassEffect ? 0.55 : 0.25),
                                        Color.white.opacity(settings.enableGlassEffect ? 0.14 : 0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
                .frame(width: 210)
                .background(
                    ZStack {
                        if settings.enableGlassEffect {
                            VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                            Color.dynamic(
                                light: Color.white.opacity(0.18),
                                dark: Color(white: 1, opacity: 0.10)
                            )
                        } else {
                            Color.dynamic(
                                light: Color(white: 0.97),
                                dark: Color(white: 0.16)
                            )
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(settings.enableGlassEffect ? 0.60 : 0.30),
                                        Color.white.opacity(settings.enableGlassEffect ? 0.16 : 0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                )

                Divider().opacity(0.5)

                // ── 右侧主内容 ──────────────────────────────────────────
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 22) {

                            // 欢迎头部
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [DT.accent,
                                                         Color(red: 99/255, green: 102/255, blue: 241/255)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 64, height: 64)
                                        .shadow(color: DT.accent.opacity(0.35), radius: 10, x: 0, y: 5)

                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .accessibilityHidden(true)
                                .padding(.top, 24)

                                Text("欢迎使用 SnapClick".localized)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.customPrimaryText)

                                Text("让您的 macOS 效率飞跃，请授予以下权限以开启全部功能".localized)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }

                            // 权限卡片列表
                            VStack(spacing: 10) {
                                WelcomePermCard(
                                    icon: "video.badge.checkmark",
                                    iconColor: .blue,
                                    title: "屏幕录制 (Screen Recording)".localized,
                                    description: "用于区域/窗口截图及放大镜取色".localized,
                                    isGranted: permission.hasScreenRecordingPermission,
                                    onAuthorize: { permission.requestScreenRecordingPermission() }
                                )
                                WelcomePermCard(
                                    icon: "accessibility",
                                    iconColor: .purple,
                                    title: "辅助功能 (Accessibility)".localized,
                                    description: "用于全局快捷键拦截与极速响应".localized,
                                    isGranted: permission.hasAccessibilityPermission,
                                    onAuthorize: { permission.requestAccessibilityPermission() }
                                )
                                WelcomePermCard(
                                    icon: "folder.badge.gearshape",
                                    iconColor: Color(red: 20/255, green: 184/255, blue: 166/255),
                                    title: "Finder 右键扩展 (Finder Extension)".localized,
                                    description: "直接在系统右键菜单中集成高级新建文件与复制工具".localized,
                                    isGranted: isFinderEnabled,
                                    onAuthorize: {
                                        isFinderEnabled = true
                                        PermissionManager.shared.requestFinderExtensionPermission()
                                    }
                                )
                                WelcomePermCard(
                                    icon: "mic.fill",
                                    iconColor: Color(red: 168/255, green: 85/255, blue: 247/255),
                                    title: "麦克风 (Microphone)".localized,
                                    description: "用于音频录音功能，可在系统设置中随时调整".localized,
                                    isGranted: permission.hasMicrophonePermission,
                                    onAuthorize: { PermissionManager.shared.requestMicrophonePermission() }
                                )
                            }
                            .padding(.horizontal, 20)

                            // 完成按钮
                            VStack(spacing: 8) {
                                Button(action: handleComplete) {
                                    HStack(spacing: 8) {
                                        if grantedCount == 3 {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                        Text("完成设置".localized)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(grantedCount == 3 ? DT.successGreen : DT.accent)
                                .keyboardShortcut(.defaultAction)
                                .padding(.horizontal, 20)
                                .animation(.spring(response: 0.3), value: grantedCount)

                                Text("您可以随时在系统偏好设置中撤销或调整这些权限。".localized)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.bottom, 24)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .frame(width: 820, height: 580)
        .onAppear {
            permission.refreshAllPermissions()
            permission.startPolling()
        }
        .onDisappear {
            permission.stopPolling()
        }
        .preferredColorScheme(settings.appAppearance == "light" ? .light : (settings.appAppearance == "dark" ? .dark : nil))
    }
}

// MARK: - 欢迎页侧边栏伪导航项

private struct WelcomeSidebarItem: View {
    let icon: String
    let title: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? DT.accent : .customSecondaryText)
                .frame(width: 18)

            Text(title.localized)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .customPrimaryText : .customMediumText)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? DT.accent.opacity(0.12) : Color.clear)
        )
    }
}

// MARK: - 权限卡片

private struct WelcomePermCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let onAuthorize: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 13))
                        .foregroundStyle(DT.successGreen)
                    Text("已启用".localized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DT.successGreen)
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isGranted)
            } else {
                Button(title.contains("Finder") ? "去启用".localized : "去授权".localized,
                       action: onAuthorize)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DT.accent)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isGranted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                if settings.enableGlassEffect {
                    VisualEffectView(material: .contentBackground, blendingMode: .withinWindow)
                }
                Color.dynamic(
                    light: Color.white.opacity(0.20),
                    dark: Color(white: 1, opacity: 0.10)
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous))
        .overlay(
            // 1px 高光边框
            RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(settings.enableGlassEffect ? 0.60 : 0.30),
                            Color.white.opacity(settings.enableGlassEffect ? 0.18 : 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(settings.enableGlassEffect ? 0.18 : 0.06),
            radius: settings.enableGlassEffect ? 20 : 4,
            x: 0,
            y: settings.enableGlassEffect ? 8 : 1
        )
        .onHover { hovered in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovered } }
    }
}

// MARK: - 预览
#Preview {
    WelcomeView(onComplete: {})
        .preferredColorScheme(.light)
}
