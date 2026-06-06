import SwiftUI
import AppKit

// MARK: - 侧边栏导航项

/// 侧边栏导航目的地
enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
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

/// 主设置窗口 — 使用 NavigationSplitView 提供原生侧边栏与适应性
struct MainWindow: View {
    @State private var selectedDestination: SettingsDestination? = .general
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // ── 侧边栏 ─────────────────────────────────────────
            List(selection: $selectedDestination) {
                Section {
                    ForEach(SettingsDestination.allCases) { dest in
                        Label(dest.rawValue.localized, systemImage: dest.symbolName)
                            .tag(dest)
                    }
                } header: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.accentColor.gradient)
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("SnapClick".localized)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("v1.0.2".localized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .textCase(nil)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // ── 内容工作区 ─────────────────────────────────────
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
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
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("请选择一个设置项".localized)
                                .font(.title)
                            Text("从左侧侧边栏选择要配置的功能模块".localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selectedDestination?.rawValue.localized ?? "设置".localized)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 580)
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
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - 通用设置页

private struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permMgr = PermissionManager.shared
    @Binding var selectedDestination: SettingsDestination?

    @AppStorage("isFinderEnabled") private var isFinderEnabled: Bool = false

    @State private var launchAtLogin = true
    @State private var showInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── 权限状态实时概览 ─────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("权限状态概览".localized)
                        .font(.headline)

                    Spacer()

                    let allGranted = permMgr.hasScreenRecordingPermission
                        && permMgr.hasAccessibilityPermission
                        && isFinderEnabled

                    if allGranted {
                        Label("全部已授权".localized, systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Label("存在未授权项".localized, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                WhiteCard {
                    VStack(spacing: 0) {
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
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("刷新所有权限状态"))
                }
            }

            // ── 启动与系统 ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("启动与系统".localized)
                    .font(.headline)

                WhiteCard {
                    HStack {
                        Toggle("开机自启动".localized, isOn: $launchAtLogin)
                        Spacer()
                        Toggle("在菜单栏显示图标".localized, isOn: $showInMenuBar)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            // ── 语言与外观偏好 ─────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("语言与外观偏好".localized)
                    .font(.headline)

                WhiteCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("系统语言".localized)
                                .font(.body.weight(.semibold))
                            Text("应用界面及菜单的呈现语言".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $settings.appLanguage) {
                            Text("简体中文").tag("zh-CN")
                            Text("English (US)").tag("en")
                            Text("日本語").tag("ja")
                        }
                        .labelsHidden()
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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isGranted {
                Label("已授权".localized, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text("\(title) 已授权"))
            } else {
                Label("未授权".localized, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                Button(actionLabel ?? "去授权".localized, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel(Text("授权 \(title)"))
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
                    .font(.headline)

                WhiteCard {
                    VStack(spacing: 0) {
                        HStack {
                            Text("保存路径".localized)
                                .font(.body)
                            Spacer()
                            Text(settings.screenshotSavePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                            .accessibilityLabel(Text("更改截图保存路径"))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.horizontal, 16)

                        HStack {
                            Text("默认格式".localized)
                                .font(.body)
                            Spacer()
                            Picker("", selection: $settings.screenshotFormat) {
                                ForEach(["PNG", "JPG", "TIFF", "GIF", "BMP"], id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
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
                    .font(.headline)

                WhiteCard {
                    VStack(spacing: 0) {
                        Toggle("添加圆角".localized, isOn: $settings.screenshotAddRoundCorner)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                        if settings.screenshotAddRoundCorner {
                            Divider().padding(.horizontal, 16)
                            HStack {
                                Text("圆角半径".localized)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Slider(value: $settings.screenshotCornerRadius, in: 4...24, step: 1)
                                    .frame(width: 180)
                                Text("\(Int(settings.screenshotCornerRadius)) px")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }

                        Divider().padding(.horizontal, 16)

                        Toggle("添加阴影".localized, isOn: $settings.screenshotAddShadow)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
            }

            // 3. 全局快捷键
            VStack(alignment: .leading, spacing: 10) {
                Text("全局快捷键".localized)
                    .font(.headline)

                WhiteCard {
                    VStack(spacing: 0) {
                        HStack {
                            Text("区域截图".localized)
                                .font(.body)
                            Spacer()
                            HotkeyRecorderView(hotkey: $settings.hotkeyAreaScreenshot)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.horizontal, 16)

                        HStack {
                            Text("长截图".localized)
                                .font(.body)
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
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                .frame(width: 140, height: 24)
                .background(Color.primary.opacity(isRecording ? 0.08 : 0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
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
            if modifiers.contains(.option) { keys.append("option") }
            if modifiers.contains(.shift) { keys.append("shift") }
            if modifiers.contains(.command) { keys.append("cmd") }

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

            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            .padding(.top, 10)

            VStack(spacing: 6) {
                Text("SnapClick")
                    .font(.title.weight(.bold))

                Text("版本 1.0.2".localized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(width: 240)

            Text("专为 macOS 打造的原生效率整合包\n右键增强 · 截图标注 · 屏幕录制 · 贴图取色".localized)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)

            Spacer()

            Text("© 2026 SnapClick Team. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
