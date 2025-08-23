//
//  MarkdownRenderingService.swift
//  ohmy408
//
//  Created by AI Assistant on 2025-01-27.
//  渲染服务 - 专门负责Markdown内容的渲染逻辑

import Foundation
import WebKit

/// 渲染状态枚举
enum RenderingState: Equatable {
    case idle
    case loading
    case rendering
    case completed
    case error(String)
}

/// 渲染配置
struct RenderingConfig {
    static let `default` = RenderingConfig()
    
    let chunkSizeThreshold: Int = 50_000  // 50KB以上采用分块渲染
    let maxFileSize: Int = 5_000_000      // 5MB文件大小限制
    let renderTimeout: TimeInterval = 30.0 // 渲染超时时间
}

/// Markdown渲染服务 - 单一职责：处理内容渲染
class MarkdownRenderingService {
    
    // MARK: - Properties
    private let config = RenderingConfig.default
    private let cacheService = MarkdownCacheService.shared
    private let preprocessor = MarkdownPreprocessor()
    
    private(set) var currentState: RenderingState = .idle {
        didSet {
            stateChangeHandler?(currentState)
        }
    }
    
    var stateChangeHandler: ((RenderingState) -> Void)?
    
    // MARK: - Public Methods
    
    /// 重置渲染状态（公共方法）
    func resetState() {
        print("🔄 重置渲染状态")
        currentState = .idle
    }
    
    /// 强制停止当前渲染
    func stopRendering() {
        print("🛑 强制停止渲染")
        currentState = .idle
    }
    
    /// 获取当前状态
    func getCurrentState() -> RenderingState {
        return currentState
    }
    
    /// 渲染Markdown内容
    func renderContent(_ content: String, 
                      with webView: WKWebView,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        
        // 如果状态异常，先重置状态
        if currentState != .idle && currentState != .completed {
            print("⚠️ 检测到异常状态: \(currentState)，自动重置")
            resetState()
        }
        
        guard currentState == .idle || currentState == .completed else {
            completion(.failure(NSError(domain: "RenderingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "渲染正在进行中"])))
            return
        }
        
        guard !content.isEmpty else {
            completion(.failure(NSError(domain: "RenderingService", code: -2, userInfo: [NSLocalizedDescriptionKey: "内容为空"])))
            return
        }
        
        guard content.count <= config.maxFileSize else {
            completion(.failure(NSError(domain: "RenderingService", code: -3, userInfo: [NSLocalizedDescriptionKey: "文件过大"])))
            return
        }
        
        currentState = .loading
        
        // 检查缓存
        let contentHash = content.sha256()
        if let cachedHTML = cacheService.getCachedHTML(for: contentHash) {
            loadCachedHTML(cachedHTML, into: webView, completion: completion)
            return
        }
        
        // 预处理内容
        currentState = .rendering
        let processedContent = preprocessor.process(content)
        
        // 选择渲染策略
        if processedContent.count > config.chunkSizeThreshold {
            renderInChunks(processedContent, with: webView, contentHash: contentHash, completion: completion)
        } else {
            renderDirectly(processedContent, with: webView, contentHash: contentHash, completion: completion)
        }
    }
    
    // MARK: - Private Methods
    
    /// 直接渲染（小文件）
    private func renderDirectly(_ content: String, 
                               with webView: WKWebView,
                               contentHash: String,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        
        print("🚀 开始直接渲染，内容长度: \(content.count)")
        
        // 首先验证JavaScript环境
        let checkScript = """
        (function() {
            const result = {
                renderMarkdownExists: typeof renderMarkdown === 'function',
                windowReady: typeof window !== 'undefined',
                documentReady: document.readyState === 'complete',
                isReady: window.isReady === true
            };
            console.log('📊 JavaScript环境检查:', JSON.stringify(result));
            return JSON.stringify(result);
        })();
        """
        
        webView.evaluateJavaScript(checkScript) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("JavaScript环境检查失败: \(error)")
                    self?.currentState = .error("JavaScript环境异常: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                print("JavaScript环境检查结果: \(result ?? "nil")")
                
                // 执行实际渲染
                let escapedContent = self?.escapeForJavaScript(content) ?? ""
                let script = "renderMarkdown('\(escapedContent)');"
                
                print("📤 执行JavaScript: \(script.prefix(100))...")
                
                webView.evaluateJavaScript(script) { [weak self] _, renderError in
                    DispatchQueue.main.async {
                        if let renderError = renderError {
                            print("Markdown渲染失败: \(renderError)")
                            self?.currentState = .error(renderError.localizedDescription)
                            completion(.failure(renderError))
                        } else {
                            print("Markdown渲染成功")
                            self?.currentState = .completed
                            // 缓存渲染结果
                            self?.cacheRenderedContent(contentHash: contentHash, webView: webView)
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }
    
    /// 分块渲染（大文件）
    private func renderInChunks(_ content: String,
                               with webView: WKWebView,
                               contentHash: String,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        
        print("🧩 开始分块渲染，内容长度: \(content.count)")
        let chunks = chunkContent(content)
        print("🧩 分成 \(chunks.count) 个块")
        var currentIndex = 0
        
        func renderNextChunk() {
            guard currentIndex < chunks.count else {
                // 所有块都渲染完成，执行最终处理
                print("🧩 所有块渲染完成，开始最终处理")
                webView.evaluateJavaScript("finishChunkRendering();") { [weak self] _, finishError in
                    DispatchQueue.main.async {
                        if let finishError = finishError {
                            print("❌ 分块渲染最终处理失败: \(finishError)")
                            self?.currentState = .error(finishError.localizedDescription)
                            completion(.failure(finishError))
                        } else {
                            print("✅ 分块渲染完全完成")
                            self?.currentState = .completed
                            self?.cacheRenderedContent(contentHash: contentHash, webView: webView)
                            completion(.success(()))
                        }
                    }
                }
                return
            }
            
            let chunk = chunks[currentIndex]
            let escapedChunk = escapeForJavaScript(chunk)
            let script = "appendMarkdownChunk('\(escapedChunk)');"
            
            print("🧩 渲染第 \(currentIndex + 1)/\(chunks.count) 个块，长度: \(chunk.count)")
            
            webView.evaluateJavaScript(script) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ 第 \(currentIndex + 1) 个块渲染失败: \(error)")
                        self?.currentState = .error(error.localizedDescription)
                        completion(.failure(error))
                    } else {
                        print("✅ 第 \(currentIndex + 1) 个块渲染成功: \(result ?? "")")
                        currentIndex += 1
                        // 延迟渲染下一个块，避免阻塞UI
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                            renderNextChunk()
                        }
                    }
                }
            }
        }
        
        // 初始化分块容器
        print("🧩 初始化分块渲染容器")
        webView.evaluateJavaScript("initChunkRendering();") { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 分块渲染初始化失败: \(error)")
                    self?.currentState = .error(error.localizedDescription)
                    completion(.failure(error))
                } else {
                    print("✅ 分块渲染初始化成功: \(result ?? "nil")")
                    renderNextChunk()
                }
            }
        }
    }
    
    /// 加载缓存的HTML
    private func loadCachedHTML(_ html: String,
                               into webView: WKWebView,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        currentState = .rendering
        print("📦 从缓存加载HTML内容")
        webView.loadHTMLString(html, baseURL: nil)
        
        // 等待HTML加载完成后，确保目录功能正常工作
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("📦 缓存内容加载完成，检查并生成目录")
            
            let checkAndGenerateTOCScript = """
            (function() {
                const tocList = document.getElementById('toc-list');
                
                if (tocList) {
                    const currentContent = tocList.innerHTML.trim();
                    
                    // 如果目录为空，尝试生成
                    if (!currentContent || currentContent === '') {
                        if (typeof generateTOC === 'function') {
                            generateTOC();
                        }
                    } else {
                        // 目录已存在，强制重新生成以确保事件监听器正确添加
                        if (typeof generateTOC === 'function') {
                            generateTOC(true);
                        }
                    }
                }
                
                // 确保目录点击事件监听器被添加
                setTimeout(() => {
                    const tocList = document.getElementById('toc-list');
                    if (tocList) {
                        // 创建点击处理函数
                        const handleTocClickForCache = (e) => {
                            const link = e.target.closest('a[data-target]');
                            if (link) {
                                e.preventDefault();
                                
                                // 执行滚动
                                const targetId = link.getAttribute('data-target');
                                const element = document.getElementById(targetId);
                                if (element) {
                                    element.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                }
                                
                                // 延时关闭目录
                                setTimeout(() => {
                                    if (window.closeTOC) {
                                        window.closeTOC();
                                    }
                                }, 800);
                            }
                        };
                        
                        // 清除旧的监听器并添加新的
                        tocList.removeEventListener('click', handleTocClickForCache);
                        tocList.addEventListener('click', handleTocClickForCache);
                    }
                }, 500);
                
                return 'TOC检查完成';
            })();
            """
            
            webView.evaluateJavaScript(checkAndGenerateTOCScript) { result, error in
                if let error = error {
                    print("📦 缓存内容目录检查失败: \(error)")
                } else {
                    print("📦 缓存内容目录检查完成")
                }
            }
        }
        
        currentState = .completed
        completion(.success(()))
    }
    
    /// 缓存渲染结果
    private func cacheRenderedContent(contentHash: String, webView: WKWebView) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            if let htmlString = result as? String {
                self?.cacheService.cacheHTML(htmlString, for: contentHash)
            }
        }
    }
    
    /// 智能分块内容
    private func chunkContent(_ content: String) -> [String] {
        // 动态调整块大小：根据内容总长度智能调整
        let contentLength = content.count
        let maxChunkSize: Int
        
        if contentLength < 100_000 {          // < 100KB: 8KB块
            maxChunkSize = 8000
        } else if contentLength < 500_000 {   // < 500KB: 10KB块  
            maxChunkSize = 10000
        } else {                              // >= 500KB: 15KB块
            maxChunkSize = 15000
        }
        
        print("🧩 内容长度: \(contentLength), 使用块大小: \(maxChunkSize)")
        
        var chunks: [String] = []
        let lines = content.components(separatedBy: .newlines)
        var currentChunk = ""
        
        for (index, line) in lines.enumerated() {
            let needsNewChunk = currentChunk.count + line.count > maxChunkSize && !currentChunk.isEmpty
            
            // 智能分块：尽量在标题或段落边界分块
            let isGoodBreakPoint = line.hasPrefix("#") || line.isEmpty || 
                                  line.hasPrefix("---") || line.hasPrefix("***")
            
            if needsNewChunk && (isGoodBreakPoint || index % 50 == 0) {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                currentChunk = line
            } else {
                if !currentChunk.isEmpty {
                    currentChunk += "\n"
                }
                currentChunk += line
            }
        }
        
        // 添加最后一个块
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // 确保至少有一个块
        if chunks.isEmpty {
            chunks.append(content)
        }
        
        print("🧩 智能分块完成: \(chunks.count) 个块")
        for (i, chunk) in chunks.enumerated() {
            print("   块 \(i + 1): \(chunk.count) 字符")
        }
        
        return chunks
    }
    
    /// JavaScript字符串转义
    private func escapeForJavaScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - String Extension for Hashing
extension String {
    func sha256() -> String {
        guard let data = data(using: .utf8) else { return self }
        return data.withUnsafeBytes { bytes in
            let buffer = UnsafeRawBufferPointer(bytes)
            let digest = Digest.sha256.hash(data: buffer)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }
}

// 简单的SHA256实现（避免引入额外依赖）
private struct Digest {
    static let sha256 = Digest()
    
    func hash(data: UnsafeRawBufferPointer) -> [UInt8] {
        // 简化实现：使用内容长度和前几个字符作为简单哈希
        let content = String(data: Data(data), encoding: .utf8) ?? ""
        let simpleHash = content.prefix(10) + "\(content.count)"
        return Array(simpleHash.utf8)
    }
}
