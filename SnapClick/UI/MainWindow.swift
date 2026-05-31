import SwiftUI
import AppKit

// MARK: - 侧边栏导航项

/// 侧边栏导航目的地
enum SettingsDestination: String, CaseIterable, Identifiable {
    case general     = "通用"
    case screenshot  = "截图与标注"
    case pinAndColor = "贴图 & 取色"
    case contextMenu = "右键菜单"
    case about       = "关于"

    var id: String { rawValue }

    /// 对应的 SF Symbol 图标名
    var symbolName: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .screenshot:  return "camera.viewfinder"
        case .pinAndColor: return "pin.circle"
        case .contextMenu: return "contextualmenu.and.cursorarrow"
        case .about:       return "info.circle"
        }
    }
}

// MARK: - MainWindow

/// 主设置窗口
struct MainWindow: View {
    @State private var selectedDestination: SettingsDestination? = .general

    var body: some View {
        HStack(spacing: 0) {
            
            // ── 左侧：侧边栏 ──────────────────────────────────────────
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
                    .padding(.bottom, 24)
                    
                    // 导航侧边栏选项列表
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(SettingsDestination.allCases) { dest in
                                Button(action: { selectedDestination = dest }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: dest.symbolName)
                                            .font(.system(size: 14, weight: selectedDestination == dest ? .semibold : .medium))
                                            .foregroundColor(selectedDestination == dest ? .white : .secondary)
                                            .frame(width: 20, alignment: .center)
                                        
                                        Text(dest.rawValue.localized)
                                            .font(.system(size: 13, weight: selectedDestination == dest ? .bold : .medium))
                                            .foregroundColor(selectedDestination == dest ? .white : .primary)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selectedDestination == dest ? Color.blue : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                }
            }
            .frame(width: 200)
            
            Divider()
                .background(Color.primary.opacity(0.1))
            
            // ── 右侧：内容工作区 ─────────────────────────────────────────
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // 原生顶部装饰条
                    HStack {
                        Spacer()
                    }
                    .frame(height: 12)
                    
                    // 动态切换视图
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 24) {
                            if let dest = selectedDestination {
                                switch dest {
                                case .general:
                                    GeneralSettingsView(selectedDestination: $selectedDestination)
                                case .screenshot:
                                    ScreenshotSettingsView()
                                case .pinAndColor:
                                    PinColorSettingsView()
                                case .contextMenu:
                                    RightClickSettingsView()
                                case .about:
                                    AboutView()
                                }
                            }
                        }
                        .padding(.all, 24)
                    }
                }
            }
        }
        .frame(width: 780, height: 520)
    }
}

// MARK: - WhiteCard 现代磨砂面板

struct WhiteCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - 通用设置页

private struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permMgr = PermissionManager.shared
    @Binding var selectedDestination: SettingsDestination?

    // Finder 扩展启用状态
    @AppStorage("isFinderEnabled") private var isFinderEnabled: Bool = false

    // 自启动与菜单栏状态，做简单的存储绑定
    @State private var launchAtLogin = true
    @State private var showInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // ── 权限状态实时概览 ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("权限状态概览".localized)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    Spacer()
                    
                    let allGranted = permMgr.hasScreenRecordingPermission
                        && permMgr.hasAccessibilityPermission
                        && isFinderEnabled
                    
                    if allGranted {
                        Label("全部已授权".localized, systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Label("存在未授权项".localized, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                
                WhiteCard {
                    VStack(spacing: 0) {
                        // 屏幕录制
                        PermissionStatusRow(
                            icon: "video.badge.checkmark",
                            iconColor: .blue,
                            title: "屏幕录制权限".localized,
                            description: "区域/窗口截图及放大镜取色所需".localized,
                            isGranted: permMgr.hasScreenRecordingPermission,
                            onAction: {
                                permMgr.requestScreenRecordingPermission()
                            }
                        )
                        
                        Divider().padding(.horizontal, 16)
                        
                        // 辅助功能
                        PermissionStatusRow(
                            icon: "accessibility",
                            iconColor: .purple,
                            title: "辅助功能权限".localized,
                            description: "全局快捷键拦截与响应所需".localized,
                            isGranted: permMgr.hasAccessibilityPermission,
                            onAction: {
                                permMgr.requestAccessibilityPermission()
                            }
                        )
                        
                        Divider().padding(.horizontal, 16)
                        
                        // Finder 右键插件
                        PermissionStatusRow(
                            icon: "folder.badge.gearshape",
                            iconColor: .teal,
                            title: "Finder 右键扩展".localized,
                            description: "在 Finder 中显示增强右键菜单所需".localized,
                            isGranted: isFinderEnabled,
                            actionLabel: "去启用".localized,
                            onAction: {
                                isFinderEnabled = true
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.extensions?FinderSync") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                    }
                }
                
                HStack {
                    Spacer()
                    Button(action: {
                        permMgr.refreshAllPermissions()
                    }) {
                        Label("刷新权限状态".localized, systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // ── 启动与系统 ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("启动与系统".localized)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary.opacity(0.8))
                
                WhiteCard {
                    VStack(spacing: 0) {
                        HStack {
                            Toggle("开机自启动".localized, isOn: $launchAtLogin)
                                .toggleStyle(.checkbox)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        Divider().padding(.horizontal, 16)
                        
                        HStack {
                            Toggle("在菜单栏显示图标".localized, isOn: $showInMenuBar)
                                .toggleStyle(.checkbox)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        Divider().padding(.horizontal, 16)
                        
                        HStack {
                            Text("菜单栏图标风格".localized)
                                .font(.system(size: 13, weight: .medium))
                            
                            Spacer()
                            
                            Picker("", selection: $settings.menuBarIconStyle) {
                                Text("默认相机".localized).tag("camera.fill")
                                Text("圆形相机".localized).tag("camera.circle.fill")
                                Text("镜头相机".localized).tag("camera.viewfinder")
                            }
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            
            // ── 语言与外观偏好 ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("语言与外观偏好".localized)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary.opacity(0.8))
                
                WhiteCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("系统语言".localized)
                                .font(.system(size: 13, weight: .semibold))
                            Text("应用界面及菜单的呈现语言".localized)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Picker("", selection: $settings.appLanguage) {
                            Text("简体中文").tag("zh-CN")
                            Text("English (US)").tag("en")
                            Text("日本語").tag("ja")
                        }
                        .frame(width: 140)
                    }
                    .padding(.all, 14)
                }
            }
        }
    }
}

// MARK: - 权限状态单行组件

private struct PermissionStatusRow: View {
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
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("已授权".localized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                    Text("未授权".localized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())

                Button(action: onAction) {
                    Text(actionLabel ?? "去授权".localized)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 截图与标注设置页

private struct ScreenshotSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // 1. 保存路径与格式
            VStack(alignment: .leading, spacing: 10) {
                Text("保存路径与格式".localized)
                    .font(.system(size: 15, weight: .bold))
                
                WhiteCard {
                    VStack(spacing: 0) {
                        HStack {
                            Text("保存路径".localized)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(settings.screenshotSavePath)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.trailing, 4)
                            
                            Button("更改…".localized) {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    settings.screenshotSavePath = url.path
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        Divider().padding(.horizontal, 16)
                        
                        HStack {
                            Text("默认格式".localized)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("", selection: $settings.screenshotFormat) {
                                ForEach(["PNG", "JPG", "TIFF", "GIF", "BMP"], id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            
            // 2. 外观美化
            VStack(alignment: .leading, spacing: 10) {
                Text("截图外观美化".localized)
                    .font(.system(size: 15, weight: .bold))
                
                WhiteCard {
                    VStack(spacing: 0) {
                        HStack {
                            Toggle("添加圆角".localized, isOn: $settings.screenshotAddRoundCorner)
                                .toggleStyle(.checkbox)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        if settings.screenshotAddRoundCorner {
                            Divider().padding(.horizontal, 16)
                            HStack {
                                Text("圆角半径".localized)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Slider(value: $settings.screenshotCornerRadius, in: 4...24, step: 1)
                                    .frame(width: 180)
                                Text("\(Int(settings.screenshotCornerRadius)) px")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        
                        Divider().padding(.horizontal, 16)
                        
                        HStack {
                            Toggle("添加阴影".localized, isOn: $settings.screenshotAddShadow)
                                .toggleStyle(.checkbox)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            
            // 3. 全局快捷键
            VStack(alignment: .leading, spacing: 10) {
                Text("全局快捷键".localized)
                    .font(.system(size: 15, weight: .bold))
                
                WhiteCard {
                    VStack(spacing: 0) {
                        HStack {
                            Text("区域截图".localized)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            HotkeyRecorderView(hotkey: $settings.hotkeyAreaScreenshot)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        
                        Divider().padding(.horizontal, 16)
                        
                        HStack {
                            Text("长截图".localized)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            HotkeyRecorderView(hotkey: $settings.hotkeyLongScreenshot)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
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
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            Text(isRecording ? "请按下组合键...".localized : (hotkey.isEmpty ? "无".localized : hotkey.uppercased()))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isRecording ? .blue : .primary)
                .frame(width: 140, height: 24)
                .background(Color.primary.opacity(isRecording ? 0.08 : 0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func startRecording() {
        isRecording = true
        // 抓取全局按键事件以进行绑定
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            var keys: [String] = []

            if modifiers.contains(.control) { keys.append("ctrl") }
            if modifiers.contains(.option) { keys.append("option") }
            if modifiers.contains(.shift) { keys.append("shift") }
            if modifiers.contains(.command) { keys.append("cmd") }

            // 过滤仅修饰键的事件（修饰键码：Control 59/62, Option 58/61, Shift 56/60, Command 55/54）
            let isModifierOnly = [54, 55, 56, 58, 59, 60, 61, 62].contains(Int(keyCode))
            
            if !isModifierOnly {
                let specialKeys: [UInt16: String] = [
                    49: "space",
                    36: "enter",
                    48: "tab",
                    126: "up",
                    125: "down",
                    123: "left",
                    124: "right",
                    53: "esc"
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
        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// MARK: - 关于视图

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            
            // 闪亮应用 Logo
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.62, blue: 1.0), Color(red: 0.0, green: 0.36, blue: 0.88)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)
            
            VStack(spacing: 6) {
                Text("SnapClick")
                    .font(.system(size: 22, weight: .bold))
                
                Text("版本 1.0.2".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(width: 240)
            
            Text("专为 macOS 打造的原生效率整合包\n右键增强 · 截图标注 · 屏幕录制 · 贴图取色".localized)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("© 2026 SnapClick Team. All rights reserved.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .padding(.vertical, 20)
    }
}

// MARK: - 预览预定义

#Preview {
    MainWindow()
        .preferredColorScheme(.light)
}