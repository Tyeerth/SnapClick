import Foundation
import AppKit

/// 沙盒环境下的文件访问管理器
/// 负责通过 Security-Scoped Bookmarks 持久化访问用户选择的目录
final class SandboxManager {
    static let shared = SandboxManager()
    
    private init() {}
    
    // MARK: - Bookmark 存储
    
    private let bookmarkDefaults = UserDefaults.standard
    
    private func bookmarkKey(for path: String) -> String {
        return "sandbox_bookmark_\(path.hash)"
    }
    
    /// 保存目录的 Security-Scoped Bookmark
    func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarkDefaults.set(bookmarkData, forKey: bookmarkKey(for: url.path))
            bookmarkDefaults.set(url.path, forKey: "last_sandbox_path_\(url.path.hash)")
        } catch {
            print("[SandboxManager] 保存 bookmark 失败: \(error)")
        }
    }
    
    /// 通过 Bookmark 获取目录访问权限
    func accessDirectory(at path: String) -> URL? {
        let key = bookmarkKey(for: path)
        guard let bookmarkData = bookmarkDefaults.data(forKey: key) else {
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // Bookmark 过期，重新创建
                saveBookmark(for: url)
            }
            
            if url.startAccessingSecurityScopedResource() {
                return url
            }
            return nil
        } catch {
            print("[SandboxManager] 解析 bookmark 失败: \(error)")
            return nil
        }
    }
    
    /// 停止访问安全域资源
    func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
    
    // MARK: - 便捷方法：获取可写入的目录 URL
    
    /// 将路径字符串解析为可写入的 URL（处理沙盒权限）
    /// - Parameter path: 保存路径（可能是 ~/Desktop 或绝对路径）
    /// - Returns: 可写入的 URL，如果沙盒权限不足则返回 App 容器内的路径
    func writableURL(for path: String) -> URL {
        let expandedPath = path.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let targetURL = URL(fileURLWithPath: expandedPath)
        
        // 尝试通过 bookmark 访问
        if let accessibleURL = accessDirectory(at: expandedPath) {
            return accessibleURL
        }
        
        // 如果无法访问用户目录，回退到 App 容器的 Documents 目录
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return containerURL
    }
    
    /// 检查路径是否可写，如果不可写则弹出目录选择器
    /// - Parameter path: 原始保存路径
    /// - Returns: 可写入的 URL
    func ensureWritableURL(for path: String) async -> URL? {
        let expandedPath = path.replacingOccurrences(of: "~", with: NSHomeDirectory())
        
        // 先尝试通过已有 bookmark 访问
        if let accessibleURL = accessDirectory(at: expandedPath) {
            return accessibleURL
        }
        
        // 尝试直接写入（可能用户已通过其他方式授权）
        let testURL = URL(fileURLWithPath: expandedPath)
        if FileManager.default.isWritableFile(atPath: expandedPath) {
            return testURL
        }
        
        // 无法写入，弹出目录选择器让用户重新选择
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "SnapClick 需要访问保存目录，请选择一个文件夹：".localized
                
                if panel.runModal() == .OK, let url = panel.url {
                    self.saveBookmark(for: url)
                    if url.startAccessingSecurityScopedResource() {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    // 用户取消，回退到 App 容器
                    let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    continuation.resume(returning: containerURL)
                }
            }
        }
    }
}
