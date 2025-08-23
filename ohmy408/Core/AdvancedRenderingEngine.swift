//
//  AdvancedRenderingEngine.swift
//  ohmy408
//
//  高级渲染引擎 - 专门为大文件和复杂内容优化设计
//  支持流式渲染、内存压力管理、智能分块等高级特性

import Foundation
import WebKit
import os.log

/// 渲染性能配置
struct PerformanceConfig {
    // 文件大小阈值
    static let smallFile: Int = 100_000      // 100KB - 直接渲染
    static let mediumFile: Int = 1_000_000   // 1MB - 标准分块
    static let largeFile: Int = 10_000_000   // 10MB - 流式渲染
    static let hugeFile: Int = 50_000_000    // 50MB - 超大文件限制
    
    // 分块配置
    static let maxChunkSize: Int = 50_000    // 最大块大小
    static let minChunkSize: Int = 10_000    // 最小块大小
    static let optimalChunkCount: Int = 20   // 最优分块数量
    
    // 性能参数
    static let renderingDelay: TimeInterval = 0.016  // 60FPS = 16ms
    static let memoryWarningThreshold: Int = 100_000_000  // 100MB
}

/// 渲染引擎状态
enum RenderingEngineState {
    case idle
    case preprocessing
    case rendering(progress: Float)
    case paused
    case completed
    case cancelled
    case error(Error)
}

/// 流式渲染引擎 - 支持超大文件处理
@MainActor
class AdvancedRenderingEngine: ObservableObject {
    
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.ohmy408.rendering", category: "AdvancedEngine")
    
    @Published var state: RenderingEngineState = .idle
    @Published var progress: Float = 0.0
    @Published var currentChunk: Int = 0
    @Published var totalChunks: Int = 0
    
    private var renderingTask: Task<Void, Error>?
    private var memoryMonitor: MemoryPressureMonitor?
    private let cacheService = AdvancedCacheService.shared
    
    // MARK: - Public Methods
    
    /// 渲染大文件内容 - 主入口
    func renderLargeContent(_ content: String, 
                           with webView: WKWebView,
                           progressHandler: @escaping (Float, String) -> Void = { _, _ in }) async throws {
        
        // 取消之前的渲染任务
        cancelCurrentRendering()
        
        guard !content.isEmpty else {
            throw RenderingError.emptyContent
        }
        
        let contentSize = content.count
        logger.info("🚀 开始渲染大文件，大小: \(contentSize) 字符")
        
        // 根据文件大小选择最优策略
        let strategy = try determineOptimalStrategy(for: contentSize)
        logger.info("📊 使用策略: \(strategy.description)")
        
        // 开始渲染任务
        renderingTask = Task {
            try await performRendering(
                content: content,
                webView: webView,
                strategy: strategy,
                progressHandler: progressHandler
            )
        }
        
        try await renderingTask?.value
    }
    
    /// 取消当前渲染
    func cancelCurrentRendering() {
        renderingTask?.cancel()
        renderingTask = nil
        state = .cancelled
    }
    
    // MARK: - Private Methods
    
    /// 确定最优渲染策略
    private func determineOptimalStrategy(for size: Int) throws -> RenderingStrategy {
        switch size {
        case ..<PerformanceConfig.smallFile:
            return .direct
            
        case PerformanceConfig.smallFile..<PerformanceConfig.mediumFile:
            return .standardChunking(chunkSize: PerformanceConfig.maxChunkSize)
            
        case PerformanceConfig.mediumFile..<PerformanceConfig.largeFile:
            let optimalChunkSize = max(
                PerformanceConfig.minChunkSize,
                min(PerformanceConfig.maxChunkSize, size / PerformanceConfig.optimalChunkCount)
            )
            return .adaptiveChunking(chunkSize: optimalChunkSize)
            
        case PerformanceConfig.largeFile..<PerformanceConfig.hugeFile:
            return .streaming(bufferSize: PerformanceConfig.maxChunkSize)
            
        default:
            throw RenderingError.fileTooLarge(size)
        }
    }
    
    /// 执行渲染
    private func performRendering(
        content: String,
        webView: WKWebView,
        strategy: RenderingStrategy,
        progressHandler: @escaping (Float, String) -> Void
    ) async throws {
        
        state = .preprocessing
        progressHandler(0.0, "预处理中...")
        
        // 启动内存监控
        startMemoryMonitoring()
        
        defer {
            stopMemoryMonitoring()
        }
        
        // 检查缓存
        let contentHash = await generateHash(for: content)
        if let cachedResult = await cacheService.getCachedRender(for: contentHash) {
            try await loadCachedContent(cachedResult, into: webView)
            return
        }
        
        // 根据策略执行渲染
        switch strategy {
        case .direct:
            try await renderDirect(content, webView: webView, progressHandler: progressHandler)
            
        case .standardChunking(let chunkSize):
            try await renderWithChunking(content, chunkSize: chunkSize, webView: webView, progressHandler: progressHandler)
            
        case .adaptiveChunking(let chunkSize):
            try await renderWithAdaptiveChunking(content, chunkSize: chunkSize, webView: webView, progressHandler: progressHandler)
            
        case .streaming(let bufferSize):
            try await renderWithStreaming(content, bufferSize: bufferSize, webView: webView, progressHandler: progressHandler)
        }
        
        // 缓存渲染结果
        await cacheRenderingResult(contentHash: contentHash, webView: webView)
    }
    
    /// 直接渲染（小文件）
    private func renderDirect(
        _ content: String,
        webView: WKWebView,
        progressHandler: @escaping (Float, String) -> Void
    ) async throws {
        
        state = .rendering(progress: 0.0)
        progressHandler(0.1, "渲染中...")
        
        // 异步预处理
        let processedContent = await Task.detached {
            return AdvancedPreprocessor.process(content)
        }.value
        
        progressHandler(0.5, "生成HTML...")
        
        // 渲染HTML
        try await webView.evaluateJavaScript(
            "renderMarkdownOptimized('\(processedContent.escapedForJS)')"
        )
        
        state = .completed
        progress = 1.0
        progressHandler(1.0, "渲染完成")
    }
    
    /// 标准分块渲染
    private func renderWithChunking(
        _ content: String,
        chunkSize: Int,
        webView: WKWebView,
        progressHandler: @escaping (Float, String) -> Void
    ) async throws {
        
        state = .rendering(progress: 0.0)
        
        // 智能分块
        let chunks = await SmartChunker.chunk(content, targetSize: chunkSize)
        self.totalChunks = chunks.count
        
        logger.info("分块完成，总计: \(self.totalChunks) 块")
        
        // 初始化渲染容器
        try await webView.evaluateJavaScript("initAdvancedChunkRendering()")
        
        // 逐块渲染
        for (index, chunk) in chunks.enumerated() {
            // 检查是否被取消
            try Task.checkCancellation()
            
            self.currentChunk = index + 1
            let chunkProgress = Float(index) / Float(chunks.count)
            
            state = .rendering(progress: chunkProgress)
            progressHandler(chunkProgress, "渲染第 \(index + 1)/\(chunks.count) 块")
            
            // 渲染当前块
            let processedChunk = await AdvancedPreprocessor.processChunk(chunk)
            try await webView.evaluateJavaScript(
                "appendOptimizedChunk('\(processedChunk.escapedForJS)', \(index))"
            )
            
            // 内存压力检查
            if await shouldPauseForMemoryPressure() {
                await pauseForMemoryRelief()
            }
            
            // 控制渲染频率，保持60FPS
            try await Task.sleep(nanoseconds: UInt64(PerformanceConfig.renderingDelay * 1_000_000_000))
        }
        
        // 完成渲染
        try await webView.evaluateJavaScript("finalizeChunkRendering()")
        
        state = .completed
        progress = 1.0
        progressHandler(1.0, "渲染完成")
    }
    
    /// 自适应分块渲染
    private func renderWithAdaptiveChunking(
        _ content: String,
        chunkSize: Int,
        webView: WKWebView,
        progressHandler: @escaping (Float, String) -> Void
    ) async throws {
        
        // 分析内容复杂度
        let complexity = await ContentComplexityAnalyzer.analyze(content)
        let adaptiveChunkSize = complexity.adjustedChunkSize(base: chunkSize)
        
        logger.info("🧠 内容复杂度: \(complexity.score)，调整块大小: \(adaptiveChunkSize)")
        
        // 使用调整后的块大小进行渲染
        try await renderWithChunking(
            content,
            chunkSize: adaptiveChunkSize,
            webView: webView,
            progressHandler: progressHandler
        )
    }
    
    /// 流式渲染（超大文件）
    private func renderWithStreaming(
        _ content: String,
        bufferSize: Int,
        webView: WKWebView,
        progressHandler: @escaping (Float, String) -> Void
    ) async throws {
        
        logger.info("🌊 启动流式渲染，缓冲区大小: \(bufferSize)")
        
        state = .rendering(progress: 0.0)
        
        // 初始化流式渲染
        try await webView.evaluateJavaScript("initStreamingRenderer()")
        
        // 创建内容流
        let stream = ContentStream(content: content, bufferSize: bufferSize)
        let totalBuffers = stream.bufferCount
        
        for (index, buffer) in stream.enumerated() {
            try Task.checkCancellation()
            
            let streamProgress = Float(index) / Float(totalBuffers)
            state = .rendering(progress: streamProgress)
            progressHandler(streamProgress, "流式处理 \(index + 1)/\(totalBuffers)")
            
            // 异步处理缓冲区
            let processedBuffer = await AdvancedPreprocessor.processStreamBuffer(buffer)
            
            // 发送到WebView
            try await webView.evaluateJavaScript(
                "streamRenderBuffer('\(processedBuffer.escapedForJS)', \(index))"
            )
            
            // 内存和性能控制
            if await shouldPauseForMemoryPressure() {
                await pauseForMemoryRelief()
            }
            
            // 保持流畅性能
            try await Task.sleep(nanoseconds: UInt64(PerformanceConfig.renderingDelay * 500_000_000))
        }
        
        // 完成流式渲染
        try await webView.evaluateJavaScript("finalizeStreamingRender()")
        
        state = .completed
        progress = 1.0
        progressHandler(1.0, "流式渲染完成")
    }
    
    // MARK: - Memory Management
    
    private func startMemoryMonitoring() {
        memoryMonitor = MemoryPressureMonitor { [weak self] pressure in
            Task { @MainActor in
                await self?.handleMemoryPressure(pressure)
            }
        }
        memoryMonitor?.start()
    }
    
    private func stopMemoryMonitoring() {
        memoryMonitor?.stop()
        memoryMonitor = nil
    }
    
    private func shouldPauseForMemoryPressure() async -> Bool {
        let memoryUsage = await SystemMemoryMonitor.currentUsage()
        return memoryUsage > PerformanceConfig.memoryWarningThreshold
    }
    
    private func pauseForMemoryRelief() async {
        logger.warning("内存压力过高，暂停渲染以释放内存")
        
        state = .paused
        
        // 强制垃圾回收
        await forceMemoryCleanup()
        
        // 等待内存释放
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        logger.info("内存释放完成，继续渲染")
    }
    
    private func handleMemoryPressure(_ pressure: MemoryPressureLevel) async {
        switch pressure {
        case .normal:
            break
        case .warning:
            logger.warning("内存警告")
            await cacheService.clearMemoryCache()
        case .critical:
            logger.error("内存严重不足，中止渲染")
            cancelCurrentRendering()
        }
    }
    
    // MARK: - Utility Methods
    
    private func loadCachedContent(_ cachedResult: CachedRenderResult, into webView: WKWebView) async throws {
        state = .rendering(progress: 0.5)
        try await webView.loadHTMLString(cachedResult.html, baseURL: nil)
        state = .completed
        progress = 1.0
    }
    
    private func cacheRenderingResult(contentHash: String, webView: WKWebView) async {
        do {
            let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
            if let htmlString = html {
                await cacheService.cacheRenderResult(html: htmlString, for: contentHash)
            }
        } catch {
            logger.error("缓存渲染结果失败: \(error.localizedDescription)")
        }
    }
    
    private func generateHash(for content: String) async -> String {
        return await Task.detached {
            return content.sha256Hash
        }.value
    }
    
    private func forceMemoryCleanup() async {
        // 清理缓存
        await cacheService.clearMemoryCache()
        
        // 请求系统垃圾回收
        if #available(iOS 13.0, *) {
            let _ = autoreleasepool {
                // 强制释放自动释放池
                return ()
            }
        }
    }
}

// MARK: - Supporting Types

enum RenderingStrategy {
    case direct
    case standardChunking(chunkSize: Int)
    case adaptiveChunking(chunkSize: Int)
    case streaming(bufferSize: Int)
    
    var description: String {
        switch self {
        case .direct: return "直接渲染"
        case .standardChunking(let size): return "标准分块(\(size))"
        case .adaptiveChunking(let size): return "自适应分块(\(size))"
        case .streaming(let size): return "流式渲染(\(size))"
        }
    }
}

enum RenderingError: LocalizedError {
    case emptyContent
    case fileTooLarge(Int)
    case renderingFailed(Error)
    case memoryPressure
    
    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "内容为空"
        case .fileTooLarge(let size):
            return "文件过大: \(size) 字符"
        case .renderingFailed(let error):
            return "渲染失败: \(error.localizedDescription)"
        case .memoryPressure:
            return "内存不足"
        }
    }
}

enum MemoryPressureLevel {
    case normal, warning, critical
}

// MARK: - Extensions

extension String {
    var escapedForJS: String {
        return self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    var sha256Hash: String {
        // 简化的哈希实现
        return "\(self.hashValue)_\(self.count)"
    }
}
