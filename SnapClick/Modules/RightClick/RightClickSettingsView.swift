import SwiftUI
import AppKit

// MARK: - 主设置页

/// 右键菜单增强设置页（精简布局重构版）
struct RightClickSettingsView: View {

    // MARK: - 状态
    @StateObject private var favMgr = FavoriteDirectoriesManager.shared
    @StateObject private var tplMgr = NewFileTemplateManager.shared

    /// 当前选中的 Tab
    @State private var selectedTab: SettingsTab = .directories

    var body: some View {
        VStack(spacing: 0) {
            
            // ── 顶部 Tab 导航栏 ──────────────────────────────────────────
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        }) {
                            Text(tab.title.localized)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 6)
                                .background(
                                    ZStack {
                                        if selectedTab == tab {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color(nsColor: .controlBackgroundColor))
                                                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                                        }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                Spacer()
            }
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // ── 内容工作区 ──────────────────────────────────────────────
            VStack(spacing: 0) {
                switch selectedTab {
                case .directories:
                    FavoriteDirectoriesSection(mgr: favMgr)
                case .templates:
                    NewFileTemplatesSection(mgr: tplMgr)
                case .devTools:
                    DevToolsSection()
                }
            }
        }
    }

    // MARK: - Tab 标签枚举
    enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
        case directories = "directories"
        case templates   = "templates"
        case devTools    = "devTools"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .directories: return "常用目录"
            case .templates:   return "新建文件模板"
            case .devTools:    return "开发者工具"
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

// MARK: - 常用目录设置区

private struct FavoriteDirectoriesSection: View {
    @ObservedObject var mgr: FavoriteDirectoriesManager

    /// 正在编辑的条目 ID
    @State private var editingID: String?
    @State private var editName:  String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 标题与操作区
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("常用目录 (Common Directories)".localized)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("从右键菜单快速访问常用文件夹。".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("恢复默认".localized) {
                        mgr.favorites.removeAll()
                        ["桌面":"Desktop","文稿":"Documents","下载":"Downloads",
                         "图片":"Pictures"].forEach { name, folder in
                            mgr.add(name: name.localized, path: "\(NSHomeDirectory())/\(folder)")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    
                    Button(action: {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories   = true
                        panel.canChooseFiles          = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "选择目录".localized
                        if panel.runModal() == .OK, let url = panel.url {
                            mgr.add(name: url.lastPathComponent, path: url.path)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("添加目录".localized)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // 目录列表表格卡片
            VStack(spacing: 0) {
                // 表头
                HStack(spacing: 16) {
                    Text("名称".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 140, alignment: .leading)
                    
                    Text("路径".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("") // 占位给操作按钮
                        .frame(width: 60)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                
                Divider()
                
                // 表身 (展开模式，不包含内部滚动条，随页面滚动)
                VStack(spacing: 0) {
                    if mgr.favorites.isEmpty {
                        HStack {
                            Spacer()
                            Text("暂无常用目录，请点击上方按钮添加".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 32)
                            Spacer()
                        }
                    } else {
                        ForEach(mgr.favorites) { fav in
                            HStack(spacing: 16) {
                                // 图标与名称
                                HStack(spacing: 8) {
                                    Image(systemName: iconForFolder(fav.name))
                                        .font(.system(size: 13))
                                        .foregroundColor(.blue)
                                        .frame(width: 18)
                                    
                                    if editingID == fav.id {
                                        TextField("目录名称", text: $editName)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12))
                                            .onSubmit {
                                                mgr.rename(id: fav.id, newName: editName)
                                                editingID = nil
                                            }
                                    } else {
                                        Text(fav.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                }
                                .frame(width: 140, alignment: .leading)
                                
                                // 路径
                                Text(fav.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // 操作
                                HStack(spacing: 10) {
                                    if editingID == fav.id {
                                        Button(action: {
                                            mgr.rename(id: fav.id, newName: editName)
                                            editingID = nil
                                        }) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.green)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button(action: {
                                            editingID = nil
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Button(action: {
                                            editingID = fav.id
                                            editName = fav.name
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button(action: {
                                            mgr.remove(id: fav.id)
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            
                            Divider()
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func iconForFolder(_ name: String) -> String {
        let lowercase = name.lowercased()
        if lowercase.contains("desktop") || lowercase.contains("桌面") {
            return "desktopcomputer"
        } else if lowercase.contains("document") || lowercase.contains("文稿") {
            return "doc.text.fill"
        } else if lowercase.contains("download") || lowercase.contains("下载") {
            return "arrow.down.circle.fill"
        } else if lowercase.contains("picture") || lowercase.contains("图片") {
            return "photo.fill"
        } else {
            return "folder.fill"
        }
    }
}

// MARK: - 新建文件模板设置区

private struct NewFileTemplatesSection: View {
    @ObservedObject var mgr: NewFileTemplateManager
    @ObservedObject private var settings = AppSettings.shared

    @State private var isAddingCustom = false
    @State private var customName     = ""
    @State private var customExt      = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 标题与操作区
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新建常用文件 (New File Templates)".localized)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("新建常用文件，这些文件将显示在右键菜单中。".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: {
                        isAddingCustom = true
                    }) {
                        Label("添加".localized, systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
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
                    
                    Button(action: {
                        mgr.presentImportPanel()
                    }) {
                        Label("导入".localized, systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // 表格容器 (展开模式，随页面滚动)
            VStack(spacing: 0) {
                // 表格头部
                HStack(spacing: 12) {
                    Text("") // 占位Checkbox
                        .frame(width: 24)
                    Text("图标".localized)
                        .frame(width: 32, alignment: .center)
                    Text("显示名称".localized)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("后缀".localized)
                        .frame(width: 80, alignment: .leading)
                    Text("主菜单".localized)
                        .frame(width: 60, alignment: .center)
                    Text("操作".localized)
                        .frame(width: 40, alignment: .center)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                
                Divider()
                
                // 表格内容
                VStack(spacing: 0) {
                    ForEach(mgr.templates) { tpl in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(get: { tpl.isEnabled }, set: { _ in mgr.toggleEnabled(id: tpl.id) }))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .frame(width: 24)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(iconBackgroundColor(for: tpl.ext).opacity(0.15))
                                Image(systemName: iconName(for: tpl.ext))
                                    .font(.system(size: 12))
                                    .foregroundColor(iconBackgroundColor(for: tpl.ext))
                            }
                            .frame(width: 28, height: 28)
                            .padding(.horizontal, 2)
                            
                            Text(tpl.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(".\(tpl.ext)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            
                            Toggle("", isOn: Binding(get: { tpl.inMainMenu ?? false }, set: { _ in mgr.toggleMainMenu(id: tpl.id) }))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .frame(width: 60, alignment: .center)
                            
                            if !tpl.isBuiltin {
                                Button(action: {
                                    mgr.remove(id: tpl.id)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .frame(width: 40, alignment: .center)
                            } else {
                                Text("内置".localized)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .center)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            
            // 底部控制选项与提示
            HStack(spacing: 24) {
                Toggle("显示图标".localized, isOn: $settings.templateShowIcons)
                Toggle("开启提示音".localized, isOn: $settings.templateSoundEffects)
                Toggle("自动打开".localized, isOn: $settings.templateAutoOpen)
                Spacer()
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            // Pro Tip
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Pro Tip:".localized).fontWeight(.bold)
                Text("在 Finder 中按住 Option (⌥) 键右击，可查看系统原生右键菜单。".localized)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.all, 10)
            .background(Color.yellow.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func iconName(for ext: String) -> String {
        switch ext.lowercased() {
        case "txt":              return "doc.text.fill"
        case "md":               return "text.badge.checkmark"
        case "html", "htm":      return "globe"
        case "css":              return "paintbrush.fill"
        case "js", "ts":         return "bolt.fill"
        case "py":               return "terminal.fill"
        case "sh", "bash", "zsh": return "dollarsign.square.fill"
        case "json", "yaml","yml": return "curlybraces"
        case "docx", "doc":      return "doc.richtext.fill"
        case "xlsx", "xls":      return "tablecells.fill"
        case "pptx", "ppt":      return "chart.pie.fill"
        default:                 return "doc.fill"
        }
    }
    
    private func iconBackgroundColor(for ext: String) -> Color {
        switch ext.lowercased() {
        case "txt":              return .gray
        case "md":               return .purple
        case "html", "htm":      return .orange
        case "css":              return .blue
        case "js", "ts":         return .yellow
        case "py":               return .green
        case "sh", "bash", "zsh": return .black
        case "json", "yaml","yml": return .pink
        case "docx", "doc":      return .blue
        case "xlsx", "xls":      return .green
        case "pptx", "ppt":      return .red
        default:                 return .blue
        }
    }
}

private struct AddTemplatePopover: View {
    @Binding var name: String
    @Binding var ext:  String
    let onAdd:    () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加自定义模板".localized)
                .font(.headline)
            TextField("模板名称（如 Vue 组件）".localized, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            TextField("扩展名（如 vue）".localized, text: $ext)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            HStack {
                Spacer()
                Button("取消".localized, action: onCancel)
                Button("添加".localized, action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || ext.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - 开发者工具设置区

private struct DevToolsSection: View {

    /// 候选工具列表
    private let tools: [(name: String, bundleID: String, icon: String)] = [
        ("Terminal",     "com.apple.Terminal",        "terminal.fill"),
        ("iTerm2",       "com.googlecode.iterm2",     "terminal"),
        ("VS Code",      "com.microsoft.VSCode",      "chevron.left.forwardslash.chevron.right"),
        ("Xcode",        "com.apple.dt.Xcode",        "hammer.fill"),
        ("Sublime Text", "com.sublimetext.4",         "square.and.pencil"),
        ("TextEdit",     "com.apple.TextEdit",        "doc.text"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 标题
            VStack(alignment: .leading, spacing: 4) {
                Text("开发者工具".localized)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("已安装的工具会自动显示在\"用…打开\"子菜单中，无需手动配置。".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // 工具列表 (展开模式，随页面滚动)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(tools, id: \.bundleID) { tool in
                        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.bundleID) != nil
                        
                        HStack(spacing: 12) {
                            // 应用图标
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.bundleID) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 14))
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.name).fontWeight(.medium)
                                    .font(.system(size: 13))
                                Text(tool.bundleID)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if installed {
                                Label("已安装".localized, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 12, weight: .semibold))
                            } else {
                                Label("未安装".localized, systemImage: "xmark.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .opacity(installed ? 1.0 : 0.5)
                        
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // 说明
            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("如需添加更多工具，请确保对应应用已通过 App Store 或官网安装。".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - 预览

#Preview {
    RightClickSettingsView()
}
