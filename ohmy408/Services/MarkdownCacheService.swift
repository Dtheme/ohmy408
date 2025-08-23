//
//  MarkdownCacheService.swift
//  ohmy408
//
//  Created by AI Assistant on 2025-01-27.
//  缓存服务 - 专门负责Markdown渲染结果的缓存管理

import Foundation
import UIKit

/// Markdown缓存服务 - 提供内存和磁盘双重缓存
class MarkdownCacheService {
    
    static let shared = MarkdownCacheService()
    
    // MARK: - Properties
    private let memoryCache = NSCache<NSString, NSString>()
    private let cacheDirectory: URL
    private let maxCacheSize: Int = 100 * 1024 * 1024 // 100MB
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7天
    
    // MARK: - Initialization
    private init() {
        // 设置内存缓存限制
        memoryCache.countLimit = 50 // 最多缓存50个文件
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB内存限制
        
        // 设置磁盘缓存目录
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cacheURL.appendingPathComponent("MarkdownCache")
        
        createCacheDirectoryIfNeeded()
        setupMemoryWarningHandler()
    }
    
    // MARK: - Public Methods
    
    /// 获取缓存的HTML内容
    func getCachedHTML(for contentHash: String) -> String? {
        let cacheKey = NSString(string: contentHash)
        
        // 1. 首先检查内存缓存
        if let cachedHTML = memoryCache.object(forKey: cacheKey) as String? {
            return cachedHTML
        }
        
        // 2. 检查磁盘缓存
        let cacheFile = cacheDirectory.appendingPathComponent("\(contentHash).html")
        
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            return nil
        }
        
        // 检查缓存是否过期
        if isCacheExpired(cacheFile) {
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
        
        // 读取磁盘缓存并加载到内存
        guard let htmlContent = try? String(contentsOf: cacheFile, encoding: .utf8) else {
            return nil
        }
        
        // 将磁盘缓存的内容加载到内存缓存
        let cost = htmlContent.utf8.count
        memoryCache.setObject(NSString(string: htmlContent), forKey: cacheKey, cost: cost)
        
        return htmlContent
    }
    
    /// 缓存HTML内容
    func cacheHTML(_ html: String, for contentHash: String) {
        let cacheKey = NSString(string: contentHash)
        
        // 1. 保存到内存缓存
        let cost = html.utf8.count
        memoryCache.setObject(NSString(string: html), forKey: cacheKey, cost: cost)
        
        // 2. 异步保存到磁盘缓存
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveToDisk(html: html, contentHash: contentHash)
        }
    }
    
    /// 清理过期缓存
    func cleanExpiredCache() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performCacheCleanup()
        }
    }
    
    /// 清空所有缓存
    func clearAllCache() {
        // 清空内存缓存
        memoryCache.removeAllObjects()
        
        // 异步清空磁盘缓存
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.cacheDirectory)
            self.createCacheDirectoryIfNeeded()
        }
    }
    
    /// 获取缓存统计信息
    func getCacheStats() -> (memoryCount: Int, diskSize: Int64) {
        let memoryCount = memoryCache.countLimit
        
        let diskSize = calculateDiskCacheSize()
        
        return (memoryCount: memoryCount, diskSize: diskSize)
    }
    
    // MARK: - Private Methods
    
    private func createCacheDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func setupMemoryWarningHandler() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }
    
    private func saveToDisk(html: String, contentHash: String) {
        let cacheFile = cacheDirectory.appendingPathComponent("\(contentHash).html")
        
        do {
            try html.write(to: cacheFile, atomically: true, encoding: .utf8)
        } catch {
            print("保存缓存失败: \(error.localizedDescription)")
        }
    }
    
    private func isCacheExpired(_ fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return true
        }
        
        return Date().timeIntervalSince(modificationDate) > maxCacheAge
    }
    
    private func performCacheCleanup() {
        guard let cacheFiles = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return
        }
        
        var totalSize: Int64 = 0
        var filesToDelete: [URL] = []
        
        for file in cacheFiles {
            // 检查是否过期
            if isCacheExpired(file) {
                filesToDelete.append(file)
                continue
            }
            
            // 计算总大小
            if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        // 如果缓存超过限制，删除最旧的文件
        if totalSize > maxCacheSize {
            let sortedFiles = cacheFiles.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 < date2
            }
            
            var currentSize = totalSize
            for file in sortedFiles {
                if currentSize <= Int64(maxCacheSize * 3 / 4) { // 清理到75%
                    break
                }
                
                if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    currentSize -= Int64(fileSize)
                    filesToDelete.append(file)
                }
            }
        }
        
        // 删除文件
        for file in filesToDelete {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    private func calculateDiskCacheSize() -> Int64 {
        guard let cacheFiles = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for file in cacheFiles {
            if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
