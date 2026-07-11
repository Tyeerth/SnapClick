import SwiftUI
import AppKit

// MARK: - 主设置页

/// 右键菜单增强设置页（重构版 — 匹配 Stitch 设计图）
struct RightClickSettingsView: View {

    // MARK: - 状态
    @StateObject private var favMgr = FavoriteDirectoriesManager.shared
    @StateObject private var tplMgr = NewFileTemplateManager.shared

    @State private var selectedTab: SettingsTab = .directories

    var body: some View {
        VStack(spacing: 0) {

            // ── 顶部 Tab 导航栏（Full Bleed 样式）──────────────────────────
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    TabButton(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DT.tabBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DT.cardBorder, lineWidth: 0.75)
                    )
            )
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            // ── 内容工作区 ──────────────────────────────────────────────
            Group {
                switch selectedTab {
                case .directories:
                    FavoriteDirectoriesSection(mgr: favMgr)
                case .templates:
                    NewFileTemplatesSection(mgr: tplMgr)
                case .devTools:
                    DevToolsSection()
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Tab 枚举
    enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
        case directories = "directories"
        case templates   = "templates"
        case devTools    = "devTools"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .directories: return "常用目录".localized
            case .templates:   return "新建文件模板".localized
            case .devTools:    return "开发者工具".localized
            }
        }

        var icon: String {
            switch self {
            case .directories: return "folder.fill"
            case .templates:   return "doc.badge.plus"
            case .devTools:    return "terminal.fill"
            }
        }
    }
}

// MARK: - Tab 按钮

private struct TabButton: View {
    let tab: RightClickSettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : DT.unselectedTabText)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? DT.accent : Color.clear)
                    .padding(2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 常用目录

private struct FavoriteDirectoriesSection: View {
    @ObservedObject var mgr: FavoriteDirectoriesManager

    @State private var editingID: String?
    @State private var editName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 标题 + 操作按钮
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("常用目录".localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.customPrimaryText)
                    Text("从右键菜单快速访问常用文件夹。".localized)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("恢复默认".localized) {
                        mgr.favorites.removeAll()
                        [("桌面", "Desktop"), ("文稿", "Documents"),
                         ("下载", "Downloads"), ("图片", "Pictures")].forEach { name, folder in
                            mgr.add(name: name.localized, path: "\(NSHomeDirectory())/\(folder)")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "选择目录".localized
                        if panel.runModal() == .OK, let url = panel.url {
                            mgr.add(name: url.lastPathComponent, path: url.path)
                        }
                    } label: {
                        Label("添加路径".localized, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DT.accent)
                }
            }

            // 目录表格
            DesignCard {
                VStack(spacing: 0) {
                    // 表头
                    HStack(spacing: 16) {
                        Text("名称".localized)
                            .frame(width: 130, alignment: .leading)
                        Text("路径".localized)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("操作".localized)
                            .frame(width: 60, alignment: .center)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.customSecondaryText)
                    .padding(.horizontal, DT.rowPadH)
                    .padding(.vertical, 8)
                    .background(DT.rowHoverBg)

                    Divider().opacity(0.5)

                    if mgr.favorites.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 28))
                                    .foregroundStyle(DT.placeholderText)
                                Text("暂无常用目录，请点击上方按钮添加".localized)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 28)
                            Spacer()
                        }
                    } else {
                        ForEach(mgr.favorites) { fav in
                            DirectoryRow(
                                fav: fav,
                                isEditing: editingID == fav.id,
                                editName: $editName,
                                onStartEdit: {
                                    editingID = fav.id
                                    editName = fav.name
                                },
                                onCommitEdit: {
                                    mgr.rename(id: fav.id, newName: editName)
                                    editingID = nil
                                },
                                onCancelEdit: { editingID = nil },
                                onDelete: { mgr.remove(id: fav.id) }
                            )
                            if fav.id != mgr.favorites.last?.id {
                                Divider().padding(.horizontal, DT.rowPadH).opacity(0.4)
                            }
                        }
                    }
                }
            }

            // 自动整理提示卡
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DT.accent.opacity(0.1))
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DT.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动整理".localized)
                        .font(.system(size: 13, weight: .semibold))
                    Text("让 SnapClick 根据文件类型自动分类新下载到对应目录。".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: .constant(false))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, DT.rowPadH)
            .padding(.vertical, DT.rowPadV)
            .background(
                RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                    .fill(DT.infoBannerBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.cardRadius, style: .continuous)
                            .stroke(DT.infoBannerBorder, lineWidth: 0.75)
                    )
            )
        }
    }
}

// MARK: - 目录行组件

private struct DirectoryRow: View {
    let fav: FavoriteDirectory
    let isEditing: Bool
    @Binding var editName: String
    let onStartEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // 图标 + 名称
            HStack(spacing: 8) {
                Image(systemName: iconForFolder(fav.name))
                    .font(.system(size: 14))
                    .foregroundStyle(DT.accent)
                    .frame(width: 18)

                if isEditing {
                    TextField("目录名称", text: $editName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { onCommitEdit() }
                } else {
                    Text(fav.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.customPrimaryText)
                }
            }
            .frame(width: 130, alignment: .leading)

            // 路径
            Text(fav.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 操作按钮
            HStack(spacing: 12) {
                if isEditing {
                    Button { onCommitEdit() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button { onCancelEdit() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { onStartEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(isHovered ? DT.accent : Color.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    Button { onDelete() } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(isHovered ? Color.red : Color.red.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 60, alignment: .center)
        }
        .padding(.horizontal, DT.rowPadH)
        .padding(.vertical, DT.rowPadV)
        .background(isHovered ? DT.rowHoverBg : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func iconForFolder(_ name: String) -> String {
        let l = name.lowercased()
        if l.contains("desktop") || l.contains("桌面") { return "desktopcomputer" }
        if l.contains("document") || l.contains("文稿") { return "doc.text.fill" }
        if l.contains("download") || l.contains("下载") { return "arrow.down.circle.fill" }
        if l.contains("picture") || l.contains("图片") { return "photo.fill" }
        return "folder.fill"
    }
}

// MARK: - 新建文件模板

private struct NewFileTemplatesSection: View {
    @ObservedObject var mgr: NewFileTemplateManager
    @ObservedObject private var settings = AppSettings.shared

    @State private var isAddingCustom = false
    @State private var customName = ""
    @State private var customExt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 标题 + 操作
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新建文件模板".localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.customPrimaryText)
                    Text("新建常用文件，这些文件将显示在右键菜单中。".localized)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("恢复默认".localized) {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button {
                        isAddingCustom = true
                    } label: {
                        Label("添加模板".localized, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DT.accent)
                    .popover(isPresented: $isAddingCustom, arrowEdge: .top) {
                        AddTemplatePopover(name: $customName, ext: $customExt) {
                            mgr.addCustom(name: customName, ext: customExt)
                            customName = ""; customExt = ""
                            isAddingCustom = false
                        } onCancel: {
                            customName = ""; customExt = ""
                            isAddingCustom = false
                        }
                    }
                }
            }

            // 模板表格
            DesignCard {
                VStack(spacing: 0) {
                    // 表头
                    HStack(spacing: 12) {
                        Text("").frame(width: 24)   // checkbox 占位
                        Text("").frame(width: 28)   // 图标占位
                        Text("名称".localized)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("后缀".localized)
                            .frame(width: 80, alignment: .leading)
                        Text("操作".localized)
                            .frame(width: 72, alignment: .center)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.customSecondaryText)
                    .padding(.horizontal, DT.rowPadH)
                    .padding(.vertical, 8)
                    .background(DT.rowHoverBg)

                    Divider().opacity(0.5)

                    ForEach(mgr.templates) { tpl in
                        TemplateRow(tpl: tpl, mgr: mgr)
                        if tpl.id != mgr.templates.last?.id {
                            Divider().padding(.horizontal, DT.rowPadH).opacity(0.4)
                        }
                    }
                }
            }

            // 菜单行为选项（卡片式）
            VStack(alignment: .leading, spacing: 10) {
                Text("菜单行为".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.customPrimaryText)

                DesignCard {
                    ToggleRow(
                        title: "显示图标".localized,
                        description: "在右键菜单中显示文件类型图标".localized,
                        isOn: $settings.templateShowIcons
                    )
                    CardDivider()
                    ToggleRow(
                        title: "创建提示音".localized,
                        description: "文件创建成功时播放提示音效".localized,
                        isOn: $settings.templateSoundEffects
                    )
                    CardDivider()
                    ToggleRow(
                        title: "自动打开文件".localized,
                        description: "新建后自动在对应应用中打开".localized,
                        isOn: $settings.templateAutoOpen
                    )
                }
            }
        }
    }
}

// MARK: - 模板行

private struct TemplateRow: View {
    let tpl: FileTemplate
    let mgr: NewFileTemplateManager

    @State private var isHovered = false
    @State private var isEditingName = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { tpl.isEnabled },
                set: { _ in mgr.toggleEnabled(id: tpl.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconColor(for: tpl.ext).opacity(0.12))
                Image(systemName: iconName(for: tpl.ext))
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor(for: tpl.ext))
            }
            .frame(width: 28, height: 28)

            nameColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(".\(tpl.ext)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 6) {
                if !tpl.isBuiltin {
                    Button { mgr.remove(id: tpl.id) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(isHovered ? Color.red : Color.red.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("内置".localized)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.customSecondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DT.tabBg)
                        )
                }
            }
            .frame(width: 72, alignment: .center)
        }
        .padding(.horizontal, DT.rowPadH)
        .padding(.vertical, 8)
        .background(isHovered ? DT.rowHoverBg : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    @ViewBuilder
    private var nameColumn: some View {
        if isEditingName {
            TextField("", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DT.accent.opacity(0.6), lineWidth: 1)
                        )
                )
                .focused($nameFieldFocused)
                .onAppear {
                    draftName = tpl.name
                    nameFieldFocused = true
                }
                .onSubmit(commitEdit)
                .onExitCommand { cancelEdit() }
                .onChange(of: nameFieldFocused) { focused in
                    if !focused { commitEdit() }
                }
        } else {
            HStack(spacing: 4) {
                Text(tpl.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tpl.isEnabled
                                     ? .customPrimaryText
                                     : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { beginEdit() }
                if isHovered {
                    Button(action: beginEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isHovered ? DT.accent : .secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(isHovered
                                          ? DT.accent.opacity(0.12)
                                          : Color.clear)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑名称".localized)
                }
            }
        }
    }

    private func beginEdit() {
        draftName = tpl.name
        isEditingName = true
    }

    private func commitEdit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != tpl.name {
            mgr.rename(id: tpl.id, newName: trimmed)
        }
        isEditingName = false
    }

    private func cancelEdit() {
        isEditingName = false
    }

    private func iconName(for ext: String) -> String {
        switch ext.lowercased() {
        case "txt":                return "doc.text.fill"
        case "md":                 return "text.badge.checkmark"
        case "html", "htm":        return "globe"
        case "css":                return "paintbrush.fill"
        case "js", "ts":           return "bolt.fill"
        case "py":                 return "terminal.fill"
        case "sh", "bash", "zsh":  return "dollarsign.square.fill"
        case "json", "yaml", "yml":return "curlybraces"
        case "docx", "doc":        return "doc.richtext.fill"
        case "xlsx", "xls":        return "tablecells.fill"
        case "pptx", "ppt":        return "chart.pie.fill"
        default:                   return "doc.fill"
        }
    }

    private func iconColor(for ext: String) -> Color {
        switch ext.lowercased() {
        case "txt":                return .gray
        case "md":                 return .purple
        case "html", "htm":        return .orange
        case "css":                return .blue
        case "js", "ts":           return .yellow
        case "py":                 return .green
        case "sh", "bash", "zsh":  return .black
        case "json", "yaml", "yml":return .pink
        case "docx", "doc":        return .blue
        case "xlsx", "xls":        return .green
        case "pptx", "ppt":        return .red
        default:                   return .blue
        }
    }
}

// MARK: - 添加模板弹出框

private struct AddTemplatePopover: View {
    @Binding var name: String
    @Binding var ext: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加自定义模板".localized)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("模板名称".localized)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("如：Vue 组件", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("文件扩展名".localized)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("如：vue", text: $ext)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("取消".localized, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button("添加".localized, action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DT.accent)
                    .disabled(name.isEmpty || ext.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - 开发者工具

private struct DevToolsSection: View {

    /// 终端类工具（用于「在终端中打开」菜单）
    private let terminalTools: [(name: String, bundleID: String, icon: String, subtitle: String)] = [
        ("Terminal",     "com.apple.Terminal",    "terminal.fill", "macOS 内置"),
        ("iTerm2",       "com.googlecode.iterm2", "terminal",      "iterm2.com"),
    ]

    /// 编辑器 / IDE 类工具（用于「用…打开」菜单）
    private let editorTools: [(name: String, bundleID: String, icon: String, subtitle: String)] = [
        ("VS Code",      "com.microsoft.VSCode",  "chevron.left.forwardslash.chevron.right", "code.visualstudio.com"),
        ("Xcode",        "com.apple.dt.Xcode",    "hammer.fill",                            "developer.apple.com"),
        ("Sublime Text", "com.sublimetext.4",      "square.and.pencil",                      "sublimetext.com"),
        ("TextEdit",     "com.apple.TextEdit",     "doc.text",                               "macOS 内置"),
    ]

    private var allTools: [(name: String, bundleID: String, icon: String, subtitle: String)] {
        terminalTools + editorTools
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 说明
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DT.accent)
                Text("已安装的工具会自动显示在「用…打开」子菜单中，无需手动配置。".localized)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DT.infoBannerBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DT.infoBannerBorder, lineWidth: 0.75)
                    )
            )

            // 工具列表
            DesignCard {
                VStack(spacing: 0) {
                    // 表头
                    HStack {
                        Text("应用".localized)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("状态".localized)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.customSecondaryText)
                    .padding(.horizontal, DT.rowPadH)
                    .padding(.vertical, 8)
                    .background(DT.rowHoverBg)

                    Divider().opacity(0.5)

                    ForEach(allTools, id: \.bundleID) { tool in
                        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.bundleID) != nil
                        DevToolRow(tool: tool, installed: installed)
                        if tool.bundleID != allTools.last?.bundleID {
                            Divider().padding(.horizontal, DT.rowPadH).opacity(0.4)
                        }
                    }
                }
            }
        }
        .onAppear {
            syncInstalledToolsToSharedStore()
        }
    }

    /// 将已安装的工具写入 SharedStore，供 FinderExtension 的 MenuBuilder 读取
    private func syncInstalledToolsToSharedStore() {
        let store = AppGroup.defaults

        // 终端类：写入 cachedInstalledTerminals
        let installedTerminals = terminalTools
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
            .map { ["name": $0.name, "bundleID": $0.bundleID] }
        if let data = try? JSONEncoder().encode(installedTerminals) {
            store.set(data, forKey: "cachedInstalledTerminals")
        }

        // 编辑器/IDE 类：写入 cachedInstalledDevTools
        let installedEditors = editorTools
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
            .map { ["name": $0.name, "bundleID": $0.bundleID] }
        if let data = try? JSONEncoder().encode(installedEditors) {
            store.set(data, forKey: "cachedInstalledDevTools")
        }
    }
}

// MARK: - 开发者工具行

private struct DevToolRow: View {
    let tool: (name: String, bundleID: String, icon: String, subtitle: String)
    let installed: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            // 应用图标
            Group {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DT.tabBg)
                            .frame(width: 28, height: 28)
                        Image(systemName: tool.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(installed
                                    ? .customPrimaryText
                                    : Color.secondary)
                Text(tool.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.customSecondaryText)
            }

            Spacer()

            if installed {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.successGreen)
                    Text("已安装".localized)
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
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("未安装".localized)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, DT.rowPadH)
        .padding(.vertical, DT.rowPadV)
        .opacity(installed ? 1.0 : 0.55)
        .background(isHovered && installed ? DT.rowHoverBg : Color.clear)
        .onHover { if installed { isHovered = $0 } }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - 预览

#Preview {
    RightClickSettingsView()
        .frame(width: 600, height: 500)
}
