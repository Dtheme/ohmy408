//
//  RenderingServiceIntegrator.swift
//  ohmy408
//
//  服务集成器 - 统一管理所有渲染相关服务
//  提供简化的API接口供UI层调用

import Foundation
import WebKit
import os.log

/// 服务集成器 - 统一渲染服务入口
@MainActor
class RenderingServiceIntegrator: ObservableObject {
    
    // MARK: - 单例
    static let shared = RenderingServiceIntegrator()
    
    // MARK: - Services
    private let renderingEngine = AdvancedRenderingEngine()
    private let cacheService = AdvancedCacheService.shared
    private let memoryManager = SmartMemoryManager()
    private let statisticsManager = StatisticsManager.shared
    
    // MARK: - State
    @Published var isRendering = false
    @Published var renderingProgress: Float = 0.0
    @Published var renderingStatus = "准备就绪"
    @Published var memoryPressure: MemoryPressureLevel = .normal
    
    private let logger = Logger(subsystem: "com.ohmy408.integration", category: "ServiceIntegrator")
    
    // MARK: - Initialization
    private init() {
        setupServices()
    }
    
    // MARK: - Public API
    
    /// 渲染Markdown内容 - 统一入口
    func renderMarkdown(
        content: String,
        webView: WKWebView,
        progressHandler: @escaping (Float, String) -> Void = { _, _ in }
    ) async throws {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let memoryBefore = await SystemMemoryMonitor.currentUsage()
        
        logger.info("🚀 开始渲染，内容大小: \(content.count) 字符")
        
        isRendering = true
        renderingProgress = 0.0
        renderingStatus = "开始渲染..."
        
        var success = false
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            Task {
                let memoryAfter = await SystemMemoryMonitor.currentUsage()
                let memoryDelta = memoryAfter - memoryBefore
                
                await MainActor.run {
                    statisticsManager.recordRender(
                        duration: duration,
                        success: success,
                        memoryUsage: memoryAfter
                    )
                    
                    isRendering = false
                    renderingStatus = success ? "渲染完成" : "渲染失败"
                    
                    logger.info("渲染完成，耗时: \(String(format: "%.2f", duration))秒，内存变化: \(memoryDelta)")
                }
            }
        }
        
        do {
            try await renderingEngine.renderLargeContent(
                content,
                with: webView
            ) { [weak self] progress, status in
                Task { @MainActor in
                    self?.renderingProgress = progress
                    self?.renderingStatus = status
                    progressHandler(progress, status)
                }
            }
            success = true
        } catch {
            logger.error("渲染失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 取消当前渲染
    func cancelRendering() {
        renderingEngine.cancelCurrentRendering()
        isRendering = false
        renderingStatus = "已取消"
        logger.info("🛑 渲染已取消")
    }
    
    /// 清理缓存
    func clearCache() async {
        await cacheService.clearMemoryCache()
        logger.info("🧹 缓存已清理")
    }
    
    /// 获取缓存统计
    func getCacheStatistics() async -> (memoryCount: Int, diskSize: Int64) {
        await cacheService.updateCacheStatistics()
        return (
            memoryCount: cacheService.cacheStats.l1CacheCount,
            diskSize: cacheService.cacheStats.totalSize
        )
    }
    
    /// 获取渲染统计
    func getRenderingStatistics() -> String {
        return statisticsManager.generateReport()
    }
    
    /// 强制内存清理
    func forceMemoryCleanup() async {
        await memoryManager.forceMemoryCleanup()
        logger.info("🧹 强制内存清理完成")
    }
    
    /// 获取系统内存信息
    func getSystemMemoryInfo() -> String {
        return SystemMemoryMonitor.getDetailedMemoryStats()
    }
    
    /// 检查是否支持大文件
    func canHandleLargeFile(size: Int) -> (canHandle: Bool, strategy: String) {
        switch size {
        case ..<RenderingConfiguration.FileProcessing.smallFileThreshold:
            return (true, "直接渲染")
        case RenderingConfiguration.FileProcessing.smallFileThreshold..<RenderingConfiguration.FileProcessing.mediumFileThreshold:
            return (true, "标准分块")
        case RenderingConfiguration.FileProcessing.mediumFileThreshold..<RenderingConfiguration.FileProcessing.largeFileThreshold:
            return (true, "自适应分块")
        case RenderingConfiguration.FileProcessing.largeFileThreshold..<RenderingConfiguration.FileProcessing.maxFileSize:
            return (true, "流式渲染")
        default:
            return (false, "文件过大")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupServices() {
        // 设置内存管理器
        memoryManager.registerCleanupHandler { [weak self] in
            await self?.cacheService.clearMemoryCache()
        }
        
        logger.info("服务集成器初始化完成")
    }
}

// MARK: - 简化的API扩展

extension RenderingServiceIntegrator {
    
    /// 简化的渲染方法 - 适用于大多数场景
    func simpleRender(
        content: String,
        webView: WKWebView,
        onProgress: ((String) -> Void)? = nil,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        Task {
            do {
                try await renderMarkdown(content: content, webView: webView) { _, status in
                    onProgress?(status)
                }
                onComplete?(true)
            } catch {
                logger.error("渲染失败: \(error.localizedDescription)")
                onComplete?(false)
            }
        }
    }
    
    /// 获取推荐的渲染配置
    func getRecommendedConfiguration(for contentSize: Int) -> String {
        let config = RenderingConfiguration.systemOptimizedConfiguration()
        let (canHandle, strategy) = canHandleLargeFile(size: contentSize)
        
        return """
        推荐配置
        文件大小: \(formatBytes(contentSize))
        是否支持: \(canHandle ? "支持" : "不支持")
        渲染策略: \(strategy)
        预计耗时: \(estimateRenderTime(size: contentSize))
        """
    }
    
    /// 格式化字节数
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    /// 估算渲染时间
    private func estimateRenderTime(size: Int) -> String {
        let baseTimePerKB: TimeInterval = 0.01 // 10ms per KB
        let estimatedTime = Double(size) / 1024.0 * baseTimePerKB
        
        if estimatedTime < 1.0 {
            return String(format: "%.0fms", estimatedTime * 1000)
        } else {
            return String(format: "%.1fs", estimatedTime)
        }
    }
}


