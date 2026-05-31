import SwiftUI

// MARK: - VisualEffectView
/// 桥接 NSVisualEffectView 以在 SwiftUI 中展现系统级通透毛玻璃 (Vibrancy) 效果
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - WelcomeView

/// 首次启动权限引导页
/// 采用 screen4.html 极富质感的双栏 Onboarding 风格，融合原生交通灯、毛玻璃侧边栏、 Setup Progress 平滑进度条与 Glass-card 卡片
struct WelcomeView: View {

    /// 点击「开始使用」后的回调，由调用方（AppDelegate）关闭窗口
    let onComplete: () -> Void

    @ObservedObject private var permission = PermissionManager.shared
    @AppStorage("isFinderEnabled") private var isFinderEnabled: Bool = false

    private var grantedCount: Int {
        var count = 0
        if permission.hasScreenRecordingPermission { count += 1 }
        if permission.hasAccessibilityPermission { count += 1 }
        if isFinderEnabled { count += 1 }
        return count
    }

    var body: some View {
        HStack(spacing: 0) {
            
            // ── 左侧：Vibrancy 毛玻璃侧边栏 ──────────────────────────────────────────
            ZStack(alignment: .topLeading) {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                
                VStack(alignment: .leading, spacing: 0) {
                    
                    // 品牌 Header
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.62, blue: 1.0), Color(red: 0.0, green: 0.36, blue: 0.88)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 34, height: 34)
                                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 0) {
                            Text("SnapClick".localized)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                            Text("v1.0.2".localized)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .tracking(1)
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 20)
                    
                    // 导航伪菜单（营造一致的侧边栏结构）
                    VStack(alignment: .leading, spacing: 6) {
                        FakeSidebarItem(icon: "gearshape", title: "通用", isActive: true)
                        FakeSidebarItem(icon: "folder", title: "Finder 增强")
                        FakeSidebarItem(icon: "camera.viewfinder", title: "截图与标注")
                    }
                    .padding(.top, 36)
                    .padding(.horizontal, 8)
                    
                    Spacer()
                    
                    // 底部：Setup Progress 进度面板
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SETUP PROGRESS".localized)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue.opacity(0.8))
                            .tracking(0.5)
                        
                        // 自定义高质感平滑进度条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 5)
                                
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0.14, green: 0.62, blue: 1.0), Color(red: 0.0, green: 0.36, blue: 0.88)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                                    .frame(width: geo.size.width * CGFloat(grantedCount) / 3.0, height: 5)
                                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: grantedCount)
                            }
                        }
                        .frame(height: 5)
                        
                        Text("\(grantedCount)" + " / 3 已授权".localized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.all, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 220)
            
            Divider()
                .background(Color.primary.opacity(0.1))
            
            // ── 右侧：Main Content 主面板 ──────────────────────────────────────────
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // 模拟原生 Traffic Lights (交通灯) 与帮助小问号
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.25))
                            .frame(width: 10, height: 10)
                        
                        Spacer()
                        
                        Button(action: {}) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            
                            // 欢迎头部
                            VStack(spacing: 6) {
                                Text("欢迎使用 SnapClick".localized)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Text("让您的 macOS 效率飞跃，请授予以下权限以开启全部功能".localized)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .padding(.top, 8)
                            
                            // 权限卡片列表 (Glass Card 样式)
                            VStack(spacing: 10) {
                                PermissionGlassCard(
                                    icon: "video.badge.checkmark",
                                    iconBgColor: .blue.opacity(0.12),
                                    iconColor: .blue,
                                    title: "屏幕录制 (Screen Recording)",
                                    description: "用于区域/窗口截图及放大镜取色",
                                    isGranted: permission.hasScreenRecordingPermission,
                                    onAuthorize: {
                                        permission.requestScreenRecordingPermission()
                                    }
                                )
                                
                                PermissionGlassCard(
                                    icon: "accessibility",
                                    iconBgColor: .purple.opacity(0.12),
                                    iconColor: .purple,
                                    title: "辅助功能 (Accessibility)",
                                    description: "用于全局快捷键拦截与极速响应响应",
                                    isGranted: permission.hasAccessibilityPermission,
                                    onAuthorize: {
                                        permission.requestAccessibilityPermission()
                                    }
                                )
                                
                                PermissionGlassCard(
                                    icon: "folder.badge.gearshape",
                                    iconBgColor: .teal.opacity(0.12),
                                    iconColor: .teal,
                                    title: "Finder 右键扩展 (Finder Extension)",
                                    description: "直接在系统右键菜单中集成高级新建文件与复制工具",
                                    isGranted: isFinderEnabled,
                                    onAuthorize: {
                                        // 标记为 true
                                        isFinderEnabled = true
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.extensions?FinderSync") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                )
                            }
                            .padding(.horizontal, 20)
                            
                            // 底部操作区与注意事项
                            VStack(spacing: 8) {
                                Button(action: onComplete) {
                                    Text("完成设置".localized)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 38)
                                        .background(
                                            LinearGradient(
                                                colors: [.blue, .blue.opacity(0.85)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .shadow(color: Color.blue.opacity(0.2), radius: 6, x: 0, y: 3)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 20)
                                
                                Text("您可以随时在系统偏好设置中撤销或调整这些权限。".localized)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .padding(.top, 4)
                            .padding(.bottom, 20)
                        }
                    }
                }
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
    }
}

// MARK: - PermissionGlassCard

/// 精致的毛玻璃权限选项卡
private struct PermissionGlassCard: View {
    let icon: String
    let iconBgColor: Color
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let onAuthorize: () -> Void
    
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            
            // 左侧精美渐变图标背景
            ZStack {
                Circle()
                    .fill(iconBgColor)
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            // 中间详细描述
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 右侧按钮交互（如果已授权，流畅地缩放并替换为绿色 check 圆标）
            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("已启用".localized)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 74, height: 24)
                .background(Color.green)
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isGranted)
            } else {
                Button(action: onAuthorize) {
                    Text(title.contains("Finder") ? "去启用" : "去授权")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 74, height: 24)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isGranted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.95 : 0.6))
                .shadow(color: .black.opacity(isHovered ? 0.04 : 0.01), radius: isHovered ? 6 : 2, x: 0, y: isHovered ? 3 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(isHovered ? 0.12 : 0.05), lineWidth: 0.5)
        )
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}

// MARK: - FakeSidebarItem

/// 伪侧边栏项目
private struct FakeSidebarItem: View {
    let icon: String
    let title: String
    var isActive: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? .white : .secondary)
                .frame(width: 16)
            
            Text(title)
                .font(.system(size: 12, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? .white : .primary)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.blue : Color.clear)
        )
    }
}

// MARK: - 预览
#Preview {
    WelcomeView(onComplete: {})
        .preferredColorScheme(.light)
}
