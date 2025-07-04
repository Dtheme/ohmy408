//
//  RecentFileManager.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import Foundation

/// 最近访问文件管理器 - 负责管理文档访问记录
class RecentFileManager {
    
    static let shared = RecentFileManager()
    
    private let userDefaults = UserDefaults.standard
    private let recentFilesKey = "RecentFiles"
    private let maxRecentFiles = 5
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 添加文件到最近访问记录
    /// - Parameter file: 要添加的文件
    func addRecentFile(_ file: MarkdownFile) {
        var recentFiles = getRecentFiles()
        
        // 移除已存在的相同文件（避免重复）
        recentFiles.removeAll { $0.relativePath == file.relativePath }
        
        // 添加到开头
        recentFiles.insert(file, at: 0)
        
        // 限制最大数量
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        
        // 保存到UserDefaults
        saveRecentFiles(recentFiles)
        
        print("添加最近访问文件: \(file.displayName)")
    }
    
    /// 获取最近访问的文件列表
    /// - Returns: 最近访问的文件数组，按访问时间倒序排列
    func getRecentFiles() -> [MarkdownFile] {
        guard let data = userDefaults.data(forKey: recentFilesKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let recentFileData = try decoder.decode([RecentFileData].self, from: data)
            
            // 转换为MarkdownFile对象，并验证文件是否仍然存在
            let fileManager = MarkdownFileManager.shared
            let allFiles = fileManager.getAllMarkdownFiles()
            
            let validRecentFiles = recentFileData.compactMap { recentData -> MarkdownFile? in
                return allFiles.first { $0.relativePath == recentData.relativePath }
            }
            
            // 如果有文件被删除，更新记录
            if validRecentFiles.count != recentFileData.count {
                saveRecentFiles(validRecentFiles)
            }
            
            return validRecentFiles
            
        } catch {
            print("读取最近访问文件失败: \(error)")
            return []
        }
    }
    
    /// 清除所有最近访问记录
    func clearRecentFiles() {
        userDefaults.removeObject(forKey: recentFilesKey)
        print("已清除所有最近访问记录")
    }
    
    /// 移除指定文件的访问记录
    /// - Parameter file: 要移除的文件
    func removeRecentFile(_ file: MarkdownFile) {
        var recentFiles = getRecentFiles()
        recentFiles.removeAll { $0.relativePath == file.relativePath }
        saveRecentFiles(recentFiles)
        print("移除最近访问文件: \(file.displayName)")
    }
    
    /// 检查是否有最近访问记录
    /// - Returns: 是否有记录
    func hasRecentFiles() -> Bool {
        return !getRecentFiles().isEmpty
    }
    
    // MARK: - 私有方法
    
    /// 保存最近访问文件到UserDefaults
    /// - Parameter files: 要保存的文件数组
    private func saveRecentFiles(_ files: [MarkdownFile]) {
        let recentFileData = files.map { file in
            RecentFileData(
                relativePath: file.relativePath,
                accessTime: Date()
            )
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(recentFileData)
            userDefaults.set(data, forKey: recentFilesKey)
        } catch {
            print("保存最近访问文件失败: \(error)")
        }
    }
}

// MARK: - 数据模型

/// 最近访问文件数据模型
private struct RecentFileData: Codable {
    let relativePath: String
    let accessTime: Date
} 
