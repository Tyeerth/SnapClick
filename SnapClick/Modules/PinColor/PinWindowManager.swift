// PinWindowManager.swift
// SnapClick - 贴图取色模块
// 管理所有贴图窗口的单例：创建、显示/隐藏、历史记录持久化

import AppKit
import SwiftUI

// MARK: - 历史记录条目

struct PinHistoryItem: Codable, Identifiable {
    let id: UUID
    /// 图片保存到临时目录的文件路径
    let imagePath: String
    let createdAt: Date

    /// 从磁盘加载 NSImage
    var nsImage: NSImage? {
        NSImage(contentsOfFile: imagePath)
    }
}

// MARK: - 贴图窗口管理器

@MainActor
final class PinWindowManager: ObservableObject {

    // MARK: - 单例
    static let shared = PinWindowManager()

    // MARK: - 发布属性
    /// 当前屏幕上所有活跃的贴图窗口
    @Published var pinnedWindows: [PinWindowController] = []
    /// 最近 50 张贴图历史（持久化到本地）
    @Published var pinHistory: [PinHistoryItem] = []

    // MARK: - 私有属性
    private let historyKey = "SnapClick.PinHistory"
    private let maxHistory = 50
    private var historyDirectory: URL {
        let dir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("SnapClick/PinHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 初始化
    private init() {
        loadHistory()
    }

    // MARK: - 公开方法

    /// 将图片钉在屏幕上（创建新的贴图窗口）
    func pin(image: NSImage, at frame: CGRect? = nil) {
        let controller = PinWindowController(image: image, screenFrame: frame)
        pinnedWindows.append(controller)
        controller.show()
    }

    /// 显示所有贴图窗口
    func showAll() {
        pinnedWindows.forEach { $0.show() }
    }

    /// 隐藏所有贴图窗口（不销毁）
    func hideAll() {
        pinnedWindows.forEach { $0.hide() }
    }

    /// 关闭并销毁所有贴图窗口
    func closeAll() {
        // 先复制数组，close() 会触发 remove()
        let all = pinnedWindows
        all.forEach { $0.close() }
    }

    /// 从历史记录重新钉上指定图片
    func pinFromHistory(_ item: PinHistoryItem) {
        guard let img = item.nsImage else { return }
        pin(image: img, at: nil)
    }

    /// 将图片存储到历史库（不创建窗口）
    func saveToHistory(_ image: NSImage) {
        let fileName = UUID().uuidString + ".png"
        let fileURL = historyDirectory.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

        do {
            try pngData.write(to: fileURL)
            let item = PinHistoryItem(
                id: UUID(),
                imagePath: fileURL.path,
                createdAt: Date()
            )
            pinHistory.insert(item, at: 0)
            if pinHistory.count > maxHistory {
                // 超出上限时删除旧文件
                let removed = pinHistory.removeLast()
                try? FileManager.default.removeItem(atPath: removed.imagePath)
            }
            saveHistory()
        } catch {
            print("[PinWindowManager] 保存历史图片失败：\(error)")
        }
    }

    /// 从历史库中移除指定条目
    func removeHistory(_ item: PinHistoryItem) {
        pinHistory.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(atPath: item.imagePath)
        saveHistory()
    }

    /// 清空全部历史
    func clearHistory() {
        pinHistory.forEach { try? FileManager.default.removeItem(atPath: $0.imagePath) }
        pinHistory.removeAll()
        saveHistory()
    }

    // MARK: - 内部方法（供 PinWindowController 调用）

    /// 从活跃列表中移除窗口（窗口关闭时调用）
    func remove(_ controller: PinWindowController) {
        pinnedWindows.removeAll { $0 === controller }
    }

    // MARK: - 历史持久化

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(pinHistory) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([PinHistoryItem].self, from: data) else { return }
        // 过滤掉文件已被删除的条目
        pinHistory = items.filter { FileManager.default.fileExists(atPath: $0.imagePath) }
    }
}
