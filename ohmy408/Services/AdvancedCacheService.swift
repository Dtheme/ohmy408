//
//  AdvancedCacheService.swift
//  ohmy408
//
//  高级缓存服务 - 为大文件渲染优化的缓存系统
//  支持分层缓存、智能清理、性能监控

import Foundation
import UIKit
import os.log

/// 缓存渲染结果
class CachedRenderResult {
    let html: String
    let metadata: CacheMetadata
    let creationDate: Date
    let accessCount: Int
    let lastAccessDate: Date
    
    init(html: String, metadata: CacheMetadata, creationDate: Date = Date(), accessCount: Int = 0, lastAccessDate: Date = Date()) {
        self.html = html
        self.metadata = metadata
        self.creationDate = creationDate
        self.accessCount = accessCount
        self.lastAccessDate = lastAccessDate
    }
    
    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let html = try container.decode(String.self, forKey: .html)
        let metadata = try container.decode(CacheMetadata.self, forKey: .metadata)
        let creationDate = try container.decode(Date.self, forKey: .creationDate)
        let accessCount = try container.decode(Int.self, forKey: .accessCount)
        let lastAccessDate = try container.decode(Date.self, forKey: .lastAccessDate)
        
        self.init(html: html, metadata: metadata, creationDate: creationDate, accessCount: accessCount, lastAccessDate: lastAccessDate)
    }
    
    private enum CodingKeys: String, CodingKey {
        case html, metadata, creationDate, accessCount, lastAccessDate
    }
}

/// 缓存元数据
struct CacheMetadata {
    let contentHash: String
    let originalSize: Int
    let renderingDuration: TimeInterval
    let complexityScore: Float
    let renderingStrategy: String
}

/// 高级缓存服务
@MainActor
class AdvancedCacheService: ObservableObject {
    
    static let shared = AdvancedCacheService()
    
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.ohmy408.cache", category: "AdvancedCache")
    
    // 多级缓存
    private let l1Cache = NSCache<NSString, CachedRenderResult>() // 内存缓存
    private let l2CacheDirectory: URL // 磁盘缓存
    private let l3CacheDirectory: URL // 压缩缓存
    
    // 缓存配置
    private struct CacheConfig {
        static let l1MaxItems = 30
        static let l1MaxMemory = 100 * 1024 * 1024  // 100MB
        static let l2MaxSize = 500 * 1024 * 1024    // 500MB
        static let l3MaxSize = 1024 * 1024 * 1024   // 1GB
        static let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7天
        static let compressionThreshold = 100 * 1024 // 100KB以上启用压缩
    }
    
    // 统计信息
    @Published var cacheStats = CacheStatistics()
    private var accessLog: [String: CacheAccessInfo] = [:]
    
    // MARK: - Initialization
    private init() {
        // 设置缓存目录
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        l2CacheDirectory = cachesURL.appendingPathComponent("AdvancedRenderCache")
        l3CacheDirectory = cachesURL.appendingPathComponent("CompressedRenderCache")
        
        setupCacheDirectories()
        configureMemoryCache()
        setupMemoryPressureHandler()
        
        logger.info("🚀 高级缓存服务初始化完成")
    }
    
    // MARK: - Public Methods
    
    /// 获取缓存的渲染结果
    func getCachedRender(for contentHash: String) async -> CachedRenderResult? {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            updateCacheStats(operation: .read, duration: duration)
        }
        
        // L1 缓存查找
        if let result = getCachedFromL1(contentHash) {
            logger.debug("L1缓存命中: \(contentHash)")
            await updateAccessLog(contentHash, cacheLevel: .l1)
            return result
        }
        
        // L2 缓存查找
        if let result = await getCachedFromL2(contentHash) {
            logger.debug("L2缓存命中: \(contentHash)")
            // 提升到L1缓存
            setCachedToL1(result, for: contentHash)
            await updateAccessLog(contentHash, cacheLevel: .l2)
            return result
        }
        
        // L3 缓存查找（压缩缓存）
        if let result = await getCachedFromL3(contentHash) {
            logger.debug("L3缓存命中: \(contentHash)")
            // 提升到L2和L1缓存
            await setCachedToL2(result, for: contentHash)
            setCachedToL1(result, for: contentHash)
            await updateAccessLog(contentHash, cacheLevel: .l3)
            return result
        }
        
        logger.debug("缓存未命中: \(contentHash)")
        cacheStats.missCount += 1
        return nil
    }
    
    /// 缓存渲染结果
    func cacheRenderResult(html: String, for contentHash: String) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            updateCacheStats(operation: .write, duration: duration)
        }
        
        let metadata = CacheMetadata(
            contentHash: contentHash,
            originalSize: html.count,
            renderingDuration: 0, // 可以从外部传入
            complexityScore: 0,   // 可以从外部传入
            renderingStrategy: "unknown"
        )
        
        let cachedResult = CachedRenderResult(
            html: html,
            metadata: metadata,
            creationDate: Date(),
            accessCount: 1,
            lastAccessDate: Date()
        )
        
        // 同时写入多级缓存
        setCachedToL1(cachedResult, for: contentHash)
        await setCachedToL2(cachedResult, for: contentHash)
        
        // 大文件写入压缩缓存
        if html.count > CacheConfig.compressionThreshold {
            await setCachedToL3(cachedResult, for: contentHash)
        }
        
        logger.debug("💾 缓存已保存: \(contentHash), 大小: \(html.count) 字符")
    }
    
    /// 清理内存缓存
    func clearMemoryCache() async {
        l1Cache.removeAllObjects()
        cacheStats.memoryEvictionCount += 1
        logger.info("🧹 内存缓存已清理")
    }
    
    /// 清理过期缓存
    func cleanupExpiredCache() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 清理L2缓存
        await cleanupL2Cache()
        
        // 清理L3缓存
        await cleanupL3Cache()
        
        // 清理访问日志
        await cleanupAccessLog()
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("🧹 缓存清理完成，耗时: \(String(format: "%.2f", duration))秒")
    }
    
    /// 获取缓存统计信息
    func updateCacheStatistics() async {
        let l2Size = await calculateL2CacheSize()
        let l3Size = await calculateL3CacheSize()
        
        await MainActor.run {
            cacheStats.l2CacheSize = l2Size
            cacheStats.l3CacheSize = l3Size
            cacheStats.totalSize = l2Size + l3Size
        }
    }
    
    // MARK: - L1 Cache (Memory)
    
    private func getCachedFromL1(_ key: String) -> CachedRenderResult? {
        return l1Cache.object(forKey: NSString(string: key))
    }
    
    private func setCachedToL1(_ result: CachedRenderResult, for key: String) {
        let cost = result.html.count
        l1Cache.setObject(result, forKey: NSString(string: key), cost: cost)
        cacheStats.l1CacheCount = l1Cache.countLimit
    }
    
    // MARK: - L2 Cache (Disk)
    
    private func getCachedFromL2(_ key: String) async -> CachedRenderResult? {
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return nil }
            
            let cacheFile = self.l2CacheDirectory.appendingPathComponent("\(key).cache")
            
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                return nil
            }
            
            // 检查是否过期
            if await self.isCacheExpired(cacheFile) {
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }
            
            do {
                let data = try Data(contentsOf: cacheFile)
                let decoder = JSONDecoder()
                return try decoder.decode(CachedRenderResult.self, from: data)
            } catch {
                // 缓存文件损坏，删除它
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }
        }.value
    }
    
    private func setCachedToL2(_ result: CachedRenderResult, for key: String) async {
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            let cacheFile = self.l2CacheDirectory.appendingPathComponent("\(key).cache")
            
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(result)
                try data.write(to: cacheFile)
            } catch {
                self.logger.error("L2缓存写入失败: \(error.localizedDescription)")
            }
        }.value
    }
    
    // MARK: - L3 Cache (Compressed)
    
    private func getCachedFromL3(_ key: String) async -> CachedRenderResult? {
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return nil }
            
            let cacheFile = self.l3CacheDirectory.appendingPathComponent("\(key).cache.gz")
            
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                return nil
            }
            
            // 检查是否过期
            if await self.isCacheExpired(cacheFile) {
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }
            
            do {
                let compressedData = try Data(contentsOf: cacheFile)
                let data = try compressedData.decompressed()
                let decoder = JSONDecoder()
                return try decoder.decode(CachedRenderResult.self, from: data)
            } catch {
                // 缓存文件损坏，删除它
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }
        }.value
    }
    
    private func setCachedToL3(_ result: CachedRenderResult, for key: String) async {
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            let cacheFile = self.l3CacheDirectory.appendingPathComponent("\(key).cache.gz")
            
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(result)
                let compressedData = try data.compressed()
                try compressedData.write(to: cacheFile)
            } catch {
                self.logger.error("L3缓存写入失败: \(error.localizedDescription)")
            }
        }.value
    }
    
    // MARK: - Cache Management
    
    private func setupCacheDirectories() {
        for directory in [l2CacheDirectory, l3CacheDirectory] {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
    
    private func configureMemoryCache() {
        l1Cache.countLimit = CacheConfig.l1MaxItems
        l1Cache.totalCostLimit = CacheConfig.l1MaxMemory
        
        // 设置清理策略
        l1Cache.evictsObjectsWithDiscardedContent = true
    }
    
    private func setupMemoryPressureHandler() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.clearMemoryCache()
            }
        }
    }
    
    private func isCacheExpired(_ fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return true
        }
        
        return Date().timeIntervalSince(modificationDate) > CacheConfig.maxAge
    }
    
    private func updateCacheStats(operation: CacheOperation, duration: TimeInterval) {
        switch operation {
        case .read:
            cacheStats.readOperations += 1
            cacheStats.totalReadTime += duration
        case .write:
            cacheStats.writeOperations += 1
            cacheStats.totalWriteTime += duration
        }
    }
    
    private func updateAccessLog(_ key: String, cacheLevel: CacheLevel) async {
        if var info = accessLog[key] {
            info.accessCount += 1
            info.lastAccess = Date()
            info.hitLevel = cacheLevel
            accessLog[key] = info
        } else {
            accessLog[key] = CacheAccessInfo(
                key: key,
                accessCount: 1,
                firstAccess: Date(),
                lastAccess: Date(),
                hitLevel: cacheLevel
            )
        }
        
        cacheStats.hitCount += 1
    }
    
    // MARK: - Cache Cleanup
    
    private func cleanupL2Cache() async {
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(at: self.l2CacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
                
                var totalSize: Int64 = 0
                var filesToDelete: [URL] = []
                
                for file in files {
                    if await self.isCacheExpired(file) {
                        filesToDelete.append(file)
                    } else {
                        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += Int64(size)
                        }
                    }
                }
                
                // 如果超过大小限制，删除最旧的文件
                if totalSize > CacheConfig.l2MaxSize {
                    let sortedFiles = files.sorted { file1, file2 in
                        let date1 = (try? file1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        let date2 = (try? file2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        return date1 < date2
                    }
                    
                    var currentSize = totalSize
                    for file in sortedFiles {
                        if currentSize <= Int64(CacheConfig.l2MaxSize * 3 / 4) {
                            break
                        }
                        
                        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            currentSize -= Int64(size)
                            filesToDelete.append(file)
                        }
                    }
                }
                
                // 删除文件
                for file in filesToDelete {
                    try? FileManager.default.removeItem(at: file)
                }
                
                self.logger.info("🧹 L2缓存清理完成，删除 \(filesToDelete.count) 个文件")
            } catch {
                self.logger.error("L2缓存清理失败: \(error.localizedDescription)")
            }
        }.value
    }
    
    private func cleanupL3Cache() async {
        // 类似L2缓存清理逻辑
        await cleanupL2Cache()
    }
    
    private func cleanupAccessLog() async {
        let cutoffDate = Date().addingTimeInterval(-CacheConfig.maxAge)
        accessLog = accessLog.filter { $0.value.lastAccess > cutoffDate }
    }
    
    // MARK: - Utility Methods
    
    private func calculateL2CacheSize() async -> Int64 {
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return 0 }
            return await self.calculateDirectorySize(self.l2CacheDirectory)
        }.value
    }
    
    private func calculateL3CacheSize() async -> Int64 {
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return 0 }
            return await self.calculateDirectorySize(self.l3CacheDirectory)
        }.value
    }
    
    private func calculateDirectorySize(_ directory: URL) -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        } catch {
            logger.error("计算目录大小失败: \(error.localizedDescription)")
        }
        
        return totalSize
    }
}

// MARK: - Supporting Types

struct CacheStatistics {
    var hitCount: Int = 0
    var missCount: Int = 0
    var l1CacheCount: Int = 0
    var l2CacheSize: Int64 = 0
    var l3CacheSize: Int64 = 0
    var totalSize: Int64 = 0
    var readOperations: Int = 0
    var writeOperations: Int = 0
    var totalReadTime: TimeInterval = 0
    var totalWriteTime: TimeInterval = 0
    var memoryEvictionCount: Int = 0
    
    var hitRate: Float {
        let total = hitCount + missCount
        return total > 0 ? Float(hitCount) / Float(total) : 0
    }
}

struct CacheAccessInfo {
    let key: String
    var accessCount: Int
    let firstAccess: Date
    var lastAccess: Date
    var hitLevel: CacheLevel
}

enum CacheLevel {
    case l1, l2, l3
}

enum CacheOperation {
    case read, write
}

// MARK: - Extensions

extension Data {
    func compressed() throws -> Data {
        return try (self as NSData).compressed(using: .zlib) as Data
    }
    
    func decompressed() throws -> Data {
        return try (self as NSData).decompressed(using: .zlib) as Data
    }
}

// MARK: - Codable Support

extension CachedRenderResult: Codable {    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(html, forKey: .html)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(accessCount, forKey: .accessCount)
        try container.encode(lastAccessDate, forKey: .lastAccessDate)
    }
}
extension CacheMetadata: Codable {}
