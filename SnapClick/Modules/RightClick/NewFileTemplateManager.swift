import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - 数据模型

/// 单个文件模板记录
struct FileTemplate: Codable, Identifiable, Hashable {
    var id: String
    var name: String           // 显示名称，如 "Markdown"
    var ext: String            // 扩展名，如 "md"
    var isEnabled: Bool        // 是否在菜单中显示
    var isBuiltin: Bool        // 是否为内置模板
    var defaultContent: String // 新建时写入的默认内容
    var inMainMenu: Bool?      // 是否在主菜单显示

    init(name: String, ext: String, isBuiltin: Bool = false, content: String = "", inMainMenu: Bool = false) {
        self.id             = UUID().uuidString
        self.name           = name
        self.ext            = ext
        self.isEnabled      = true
        self.isBuiltin      = isBuiltin
        self.defaultContent = content
        self.inMainMenu     = inMainMenu
    }
}

// MARK: - 管理器

/// 新建文件模板管理器，负责内置模板与自定义模板的持久化
final class NewFileTemplateManager: ObservableObject {

    // MARK: - 单例
    static let shared = NewFileTemplateManager()

    // MARK: - 常量
    private let appGroupID = "group.com.snapclick.shared"
    private let storageKey = "fileTemplates"
    private let customKey  = "customTemplates"   // 供 FinderExtension MenuBuilder 读取

    // MARK: - 已发布属性
    @Published var templates: [FileTemplate] = []

    // MARK: - 内部属性
    private var userDefaults: UserDefaults?

    // MARK: - 初始化
    private init() {
        userDefaults = UserDefaults(suiteName: appGroupID)
        load()
    }

    // MARK: - 公共接口 — 查询

    /// 已启用的模板（菜单中显示的）
    var enabledTemplates: [FileTemplate] {
        templates.filter { $0.isEnabled }
    }

    // MARK: - 公共接口 — 修改

    /// 切换模板的启用状态
    func toggleEnabled(id: String) {
        guard let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[idx].isEnabled.toggle()
        save()
    }

    /// 切换模板的主菜单显示状态
    func toggleMainMenu(id: String) {
        guard let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        let current = templates[idx].inMainMenu ?? false
        templates[idx].inMainMenu = !current
        save()
    }

    /// 删除自定义模板（内置模板不可删除）
    func remove(id: String) {
        guard let tpl = templates.first(where: { $0.id == id }), !tpl.isBuiltin else { return }
        templates.removeAll { $0.id == id }
        save()
    }

    /// 按 IndexSet 删除（仅删除自定义模板）
    func remove(at offsets: IndexSet) {
        let toRemove = offsets.compactMap { idx -> String? in
            let tpl = templates[idx]
            return tpl.isBuiltin ? nil : tpl.id
        }
        templates.removeAll { toRemove.contains($0.id) }
        save()
    }

    /// 重命名模板
    func rename(id: String, newName: String) {
        guard let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[idx].name = newName
        save()
    }

    /// 添加自定义模板（手动输入名称和扩展名）
    func addCustom(name: String, ext: String, content: String = "") {
        let tpl = FileTemplate(name: name, ext: ext, isBuiltin: false, content: content)
        templates.append(tpl)
        save()
    }

    /// 从文件导入自定义模板（选择一个文件，读取其内容作为模板）
    func importFromFile(url: URL) {
        let ext  = url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // 二进制文件无法作为文本模板，记录空内容
            content = ""
        }
        let tpl = FileTemplate(name: name, ext: ext, isBuiltin: false, content: content)
        templates.append(tpl)
        save()
    }

    /// 打开文件选择面板并导入
    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles      = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "选择模板文件"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { importFromFile(url: $0) }
    }

    // MARK: - 私有方法

    private func load() {
        guard let ud = userDefaults,
              let data = ud.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FileTemplate].self, from: data) else {
            // 首次启动写入内置模板
            templates = Self.builtinTemplates()
            save()
            return
        }
        templates = decoded
    }

    private func save() {
        guard let ud = userDefaults,
              let encoded = try? JSONEncoder().encode(templates) else { return }
        ud.set(encoded, forKey: storageKey)

        // 同步自定义模板的精简格式，供 FinderExtension MenuBuilder 读取
        let customs = templates
            .filter { !$0.isBuiltin && $0.isEnabled }
            .map { ["name": $0.name, "ext": $0.ext, "content": $0.defaultContent] }
        ud.set(customs, forKey: customKey)
        ud.synchronize()
    }

    /// 内置模板列表
    private static func builtinTemplates() -> [FileTemplate] {
        [
            FileTemplate(name: "文本文档",       ext: "txt",  isBuiltin: true, content: ""),
            FileTemplate(name: "Markdown",       ext: "md",   isBuiltin: true, content: "# 新建文档\n\n"),
            FileTemplate(name: "Word 文档",       ext: "docx", isBuiltin: true, content: ""),
            FileTemplate(name: "Excel 表格",      ext: "xlsx", isBuiltin: true, content: ""),
            FileTemplate(name: "PPT 演示",        ext: "pptx", isBuiltin: true, content: ""),
            FileTemplate(name: "HTML 文件",       ext: "html", isBuiltin: true, content: """
            <!DOCTYPE html>
            <html lang="zh-CN">
            <head>
                <meta charset="UTF-8">
                <title>新建页面</title>
            </head>
            <body>
            </body>
            </html>
            """),
            FileTemplate(name: "CSS 文件",        ext: "css",  isBuiltin: true, content: "/* 样式表 */\n"),
            FileTemplate(name: "JavaScript",      ext: "js",   isBuiltin: true, content: "// JavaScript\n'use strict';\n"),
            FileTemplate(name: "Python 文件",     ext: "py",   isBuiltin: true, content: "# -*- coding: utf-8 -*-\n\n"),
            FileTemplate(name: "Shell 脚本",      ext: "sh",   isBuiltin: true, content: "#!/bin/bash\n\nset -e\n"),
            FileTemplate(name: "JSON 文件",       ext: "json", isBuiltin: true, content: "{\n  \n}\n"),
            FileTemplate(name: "YAML 配置",       ext: "yaml", isBuiltin: true, content: "# YAML 配置\n\n"),
        ]
    }
}
