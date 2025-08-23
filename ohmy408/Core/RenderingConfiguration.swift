//
//  RenderingConfiguration.swift
//  ohmy408
//
//  渲染配置中心 - 统一管理所有渲染相关配置
//  支持运行时调整和性能优化

import Foundation
import UIKit

/// 全局渲染配置
struct RenderingConfiguration {
    
    // MARK: - 单例
    static let shared = RenderingConfiguration()
    
    // MARK: - 文件处理配置
    struct FileProcessing {
        static let maxFileSize: Int = 50_000_000        // 50MB 最大文件
        static let smallFileThreshold: Int = 100_000    // 100KB 小文件阈值
        static let mediumFileThreshold: Int = 1_000_000 // 1MB 中等文件阈值
        static let largeFileThreshold: Int = 10_000_000 // 10MB 大文件阈值
    }
    
    // MARK: - 渲染策略配置
    struct RenderingStrategy {
        static let directRenderMaxSize: Int = 100_000           // 直接渲染上限
        static let standardChunkSize: Int = 50_000              // 标准分块大小
        static let adaptiveChunkMinSize: Int = 10_000           // 自适应最小块
        static let streamingBufferSize: Int = 50_000            // 流式缓冲区
        static let renderingDelay: TimeInterval = 0.016         // 渲染延迟 (60FPS)
        static let streamingDelay: TimeInterval = 0.008         // 流式延迟 (120FPS)
    }
    
    // MARK: - 缓存配置
    struct Cache {
        static let l1MemoryLimit: Int = 100 * 1024 * 1024      // L1内存 100MB
        static let l1ItemLimit: Int = 30                        // L1条目限制
        static let l2DiskLimit: Int = 500 * 1024 * 1024         // L2磁盘 500MB
        static let l3CompressedLimit: Int = 1024 * 1024 * 1024  // L3压缩 1GB
        static let maxAge: TimeInterval = 7 * 24 * 60 * 60      // 7天过期
        static let compressionThreshold: Int = 100 * 1024       // 100KB压缩阈值
    }
    
    // MARK: - 内存管理配置
    struct Memory {
        static let normalThreshold: Float = 0.7     // 正常阈值 70%
        static let warningThreshold: Float = 0.85   // 警告阈值 85%
        static let criticalThreshold: Float = 0.95  // 严重阈值 95%
        static let monitoringInterval: TimeInterval = 1.0  // 监控间隔 1秒
        static let cleanupDelay: TimeInterval = 1.0        // 清理延迟 1秒
    }
    
    // MARK: - 复杂度分析配置
    struct ComplexityAnalysis {
        static let mathFormulaWeight: Float = 10.0      // 数学公式权重
        static let codeBlockWeight: Float = 8.0         // 代码块权重
        static let tableWeight: Float = 5.0             // 表格权重
        static let mediaWeight: Float = 3.0             // 媒体权重
        static let structureWeight: Float = 2.0         // 结构权重
        static let contentDensityWeight: Float = 0.4    // 内容密度权重
    }
    
    // MARK: - UI配置
    struct UserInterface {
        static let loadingUpdateInterval: TimeInterval = 0.1   // 加载状态更新间隔
        static let progressAnimationDuration: TimeInterval = 0.25  // 进度动画时长
        static let errorRetryDelay: TimeInterval = 2.0         // 错误重试延迟
        static let maxRetryCount: Int = 3                       // 最大重试次数
    }
    
    // MARK: - 调试配置
    struct Debug {
        static let enableDetailedLogging: Bool = true          // 启用详细日志
        static let enablePerformanceMonitoring: Bool = true    // 启用性能监控
        static let enableMemoryTracking: Bool = true           // 启用内存跟踪
        static let logRenderingSteps: Bool = false              // 记录渲染步骤
    }
    
    // MARK: - 动态配置方法
    
    /// 根据设备性能调整配置
    func adjustForDevice() -> RenderingConfiguration {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let deviceScale = UIScreen.main.scale
        
        // 根据设备内存调整缓存限制
        var config = self
        if totalMemory < 2 * 1024 * 1024 * 1024 { // < 2GB
            // 低内存设备配置
        } else if totalMemory < 4 * 1024 * 1024 * 1024 { // < 4GB
            // 中等内存设备配置
        } else {
            // 高内存设备配置
        }
        
        return config
    }
    
    /// 根据内容复杂度调整渲染参数
    func adjustForComplexity(_ complexity: Float) -> (chunkSize: Int, delay: TimeInterval) {
        let baseChunkSize = RenderingStrategy.standardChunkSize
        let baseDelay = RenderingStrategy.renderingDelay
        
        switch complexity {
        case 0..<50:
            return (Int(Float(baseChunkSize) * 1.5), baseDelay * 0.8)
        case 50..<150:
            return (baseChunkSize, baseDelay)
        case 150..<300:
            return (Int(Float(baseChunkSize) * 0.7), baseDelay * 1.2)
        default:
            return (Int(Float(baseChunkSize) * 0.5), baseDelay * 1.5)
        }
    }
    
    /// 获取当前系统推荐配置
    static func systemOptimizedConfiguration() -> RenderingConfiguration {
        return shared.adjustForDevice()
    }
}

/// 渲染统计信息
struct RenderingStatistics {
    var totalRenderCount: Int = 0
    var successfulRenderCount: Int = 0
    var failedRenderCount: Int = 0
    var averageRenderTime: TimeInterval = 0
    var totalRenderTime: TimeInterval = 0
    var memoryPeakUsage: Int = 0
    var cacheHitCount: Int = 0
    var cacheMissCount: Int = 0
    
    var successRate: Float {
        guard totalRenderCount > 0 else { return 0 }
        return Float(successfulRenderCount) / Float(totalRenderCount)
    }
    
    var cacheHitRate: Float {
        let totalCacheAttempts = cacheHitCount + cacheMissCount
        guard totalCacheAttempts > 0 else { return 0 }
        return Float(cacheHitCount) / Float(totalCacheAttempts)
    }
    
    mutating func recordRender(duration: TimeInterval, success: Bool, memoryUsage: Int) {
        totalRenderCount += 1
        totalRenderTime += duration
        averageRenderTime = totalRenderTime / Double(totalRenderCount)
        memoryPeakUsage = max(memoryPeakUsage, memoryUsage)
        
        if success {
            successfulRenderCount += 1
        } else {
            failedRenderCount += 1
        }
    }
    
    mutating func recordCacheAccess(hit: Bool) {
        if hit {
            cacheHitCount += 1
        } else {
            cacheMissCount += 1
        }
    }
}

/// 全局统计管理器
@MainActor
class StatisticsManager: ObservableObject {
    static let shared = StatisticsManager()
    
    @Published var statistics = RenderingStatistics()
    
    private init() {}
    
    func recordRender(duration: TimeInterval, success: Bool, memoryUsage: Int) {
        statistics.recordRender(duration: duration, success: success, memoryUsage: memoryUsage)
    }
    
    func recordCacheAccess(hit: Bool) {
        statistics.recordCacheAccess(hit: hit)
    }
    
    func generateReport() -> String {
        return """
        📊 渲染统计报告
        ================
        总渲染次数: \(statistics.totalRenderCount)
        成功率: \(String(format: "%.1f", statistics.successRate * 100))%
        平均渲染时间: \(String(format: "%.2f", statistics.averageRenderTime))秒
        内存峰值: \(formatBytes(statistics.memoryPeakUsage))
        缓存命中率: \(String(format: "%.1f", statistics.cacheHitRate * 100))%
        """
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
