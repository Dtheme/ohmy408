//
//  MarkdownReaderViewController.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import UIKit
import WebKit
import Network

/// Markdown阅读器视图控制器 - 负责渲染和显示Markdown内容
class MarkdownReaderViewController: UIViewController {
    
    // MARK: - 属性
    var markdownFile: MarkdownFile? {
        didSet {
            updateTitle()
            loadMarkdownContent()
        }
    }
    
    // MARK: - UI组件
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        
        // 使用现代化的JavaScript配置
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        
        // 优化性能配置
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false
        
        // 禁用不必要的功能以提升性能
        config.allowsAirPlayForMediaPlayback = false
        config.allowsPictureInPictureMediaPlayback = false
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        // 优化滚动性能
        webView.scrollView.decelerationRate = UIScrollView.DecelerationRate.normal
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        
        return webView
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = UIColor.systemBlue
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private lazy var loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "正在加载..."
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = UIColor.secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()
    
    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = UIColor.systemBlue
        progress.trackTintColor = UIColor.systemGray5
        progress.isHidden = true
        return progress
    }()
    
    private lazy var errorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.isHidden = true
        
        let imageView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        imageView.tintColor = UIColor.systemOrange
        imageView.contentMode = .scaleAspectFit
        
        let titleLabel = UILabel()
        titleLabel.text = "加载失败"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textColor = UIColor.label
        titleLabel.textAlignment = .center
        
        let messageLabel = UILabel()
        messageLabel.text = "无法加载Markdown文件内容"
        messageLabel.font = UIFont.systemFont(ofSize: 14)
        messageLabel.textColor = UIColor.secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        
        let retryButton = UIButton(type: .system)
        
        // 使用现代化的按钮配置
        var config = UIButton.Configuration.filled()
        config.title = "重新加载"
        config.baseBackgroundColor = UIColor.systemBlue
        config.baseForegroundColor = UIColor.white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        
        retryButton.configuration = config
        retryButton.addTarget(self, action: #selector(retryLoadContent), for: .touchUpInside)
        
        let stackView = UIStackView(arrangedSubviews: [imageView, titleLabel, messageLabel, retryButton])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            imageView.widthAnchor.constraint(equalToConstant: 50),
            imageView.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        return view
    }()
    
    private var markdownContent: String = ""
    private var networkMonitor: NWPathMonitor?
    private var hasNetworkPermission: Bool = false
    private var needsRefreshAfterPermission: Bool = false
    private var isHTMLTemplateLoaded: Bool = false
    private var retryCount: Int = 0
    private let maxRetryCount: Int = 10
    private var pendingMarkdownContent: String?
    private var isTemplateLoading: Bool = false
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNetworkMonitoring()
        updateTitle()
        
        // 延迟加载HTML模板，确保UI完全设置完成
        DispatchQueue.main.async {
            self.loadHTMLTemplateIfNeeded()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 检查是否需要在权限授权后刷新
        if needsRefreshAfterPermission && hasNetworkPermission {
            print("🔄 网络权限已授权，刷新WebView")
            needsRefreshAfterPermission = false
            refreshWebView()
        }
    }
    
    deinit {
        networkMonitor?.cancel()
    }
    
    // MARK: - UI设置
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        
        // 设置导航栏
        navigationItem.largeTitleDisplayMode = .never
        
        // 添加右侧分享按钮
        setupNavigationButtons()
        
        // 设置WebView
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // 设置加载指示器和相关组件
        view.addSubview(loadingIndicator)
        view.addSubview(loadingLabel)
        view.addSubview(progressView)
        
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 16),
            
            progressView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressView.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 16),
            progressView.widthAnchor.constraint(equalToConstant: 200)
        ])
        
        // 设置错误视图
        view.addSubview(errorView)
        errorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigationButtons() {
        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareContent)
        )
        
        let refreshButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshButtonTapped)
        )
        
        navigationItem.rightBarButtonItems = [shareButton, refreshButton]
    }
    
    private func updateTitle() {
        title = markdownFile?.displayName ?? "Markdown阅读器"
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasConnected = self?.hasNetworkPermission ?? false
                self?.hasNetworkPermission = path.status == .satisfied
                
                // 如果从无网络变为有网络，且之前加载失败，则自动刷新
                if !wasConnected && self?.hasNetworkPermission == true && self?.needsRefreshAfterPermission == true {
                    print("🌐 网络连接已恢复，自动刷新WebView")
                    self?.needsRefreshAfterPermission = false
                    self?.refreshWebView()
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
    
    // MARK: - 内容加载
    private func loadHTMLTemplateIfNeeded() {
        // 避免重复加载
        guard !isHTMLTemplateLoaded && !isTemplateLoading else {
            print("📄 HTML模板已加载或正在加载中，跳过")
            return
        }
        
        guard let htmlURL = Bundle.main.url(forResource: "markdown_viewer", withExtension: "html") else {
            showError(message: "无法找到Markdown模板文件")
            return
        }
        
        print("🔄 开始加载HTML模板")
        isTemplateLoading = true
        showLoadingState(message: "正在加载渲染器...", progress: 0.1)
        
        let request = URLRequest(url: htmlURL)
        webView.load(request)
    }
    
    private func loadHTMLTemplate() {
        loadHTMLTemplateIfNeeded()
    }
    
    private func loadMarkdownContent() {
        guard let file = markdownFile else { return }
        
        // 确保HTML模板已开始加载
        loadHTMLTemplateIfNeeded()
        
        showLoadingState(message: "正在读取文件...", progress: 0.3)
        
        // 异步读取文件内容以避免阻塞UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try String(contentsOf: file.url, encoding: .utf8)
                
                DispatchQueue.main.async {
                    self?.markdownContent = content
                    self?.pendingMarkdownContent = content
                    print("📄 Markdown内容已读取，等待HTML模板加载完成")
                    
                    // 如果HTML模板已加载完成，立即渲染
                    if self?.isHTMLTemplateLoaded == true {
                        self?.renderMarkdownContent()
                    } else {
                        self?.showLoadingState(message: "等待渲染器加载...", progress: 0.6)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError(message: "无法读取文件内容: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func renderMarkdownContent() {
        guard !markdownContent.isEmpty else { 
            print("⚠️ Markdown内容为空，跳过渲染")
            return 
        }
        
        // 检查HTML模板是否已加载
        if !isHTMLTemplateLoaded {
            print("⏳ HTML模板未加载完成，将内容标记为待渲染")
            pendingMarkdownContent = markdownContent
            return
        }
        
        print("🎨 开始渲染Markdown内容")
        hideError()
        showLoadingState(message: "正在渲染内容...", progress: 0.8)
        retryCount = 0 // 重置重试计数
        renderOptimizedMarkdown()
    }
    
    private func renderOptimizedMarkdown() {
        // 检查内容大小，对大文件进行优化渲染
        let contentSize = markdownContent.count
        
        if contentSize > 100000 { // 大于100KB的文件使用延迟渲染
            renderLargeMarkdownWithDelay()
        } else {
            renderImmediateMarkdown()
        }
    }
    
    private func renderLargeMarkdownWithDelay() {
        showLoadingState(message: "正在渲染大文件...", progress: 0.8)
        
        print("📄 检测到大文件(\(markdownContent.count)字符)，使用延迟渲染策略")
        
        // 对于大文件，我们不分块内容，而是分步骤渲染
        // 1. 先渲染基础结构
        // 2. 然后渲染完整内容
        renderLargeFileInSteps()
    }
    
    private func renderLargeFileInSteps() {
        // 检查重试次数
        guard retryCount < maxRetryCount else {
            print("❌ 大文件渲染重试次数超限，直接渲染")
            performCompleteMarkdownRender()
            return
        }
        
        // 先检查DOM是否准备好
        let checkDOMScript = """
            (function() {
                try {
                    var element = document.getElementById('rendered-content');
                    return element !== null && typeof renderMarkdown === 'function';
                } catch(e) {
                    return false;
                }
            })();
        """
        
        webView.evaluateJavaScript(checkDOMScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ 大文件DOM检查脚本执行错误: \(error)")
                self?.retryCount += 1
                self?.retryLargeFileRender()
                return
            }
            
            if let isReady = result as? Bool, isReady {
                // DOM已准备好，开始渲染
                print("✅ DOM已准备好，开始大文件渲染")
                self?.performCompleteMarkdownRender()
            } else {
                // DOM未准备好，延迟重试
                self?.retryCount += 1
                print("⏳ DOM未准备好，延迟重试大文件渲染... (第\(self?.retryCount ?? 0)次)")
                self?.retryLargeFileRender()
            }
        }
    }
    
    private func retryLargeFileRender() {
        guard retryCount < maxRetryCount else {
            print("❌ 大文件渲染重试次数超限，强制渲染")
            performCompleteMarkdownRender()
            return
        }
        
        let delay = min(0.3 * Double(retryCount), 3.0) // 递增延迟，最大3秒
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.renderLargeFileInSteps()
        }
    }
    
    private func performCompleteMarkdownRender() {
        // 渲染完整的Markdown内容，不分块
        let escapedContent = escapeForJavaScript(markdownContent)
        
        showLoadingState(message: "正在处理内容...", progress: 0.9)
        
        let script = """
            try {
                // 清空之前的内容
                document.getElementById('rendered-content').innerHTML = '';
                
                // 显示加载提示
                document.getElementById('rendered-content').innerHTML = '<div style="text-align: center; padding: 20px; color: #666;">正在渲染内容，请稍候...</div>';
                
                // 延迟渲染，避免阻塞UI
                setTimeout(function() {
                    try {
                        // 清空加载提示并渲染实际内容
                        document.getElementById('rendered-content').innerHTML = '';
                        renderMarkdown('\(escapedContent)');
                        console.log('✅ 大文件渲染完成');
                    } catch(e) {
                        console.error('❌ 渲染过程中出错:', e);
                        document.getElementById('rendered-content').innerHTML = '<div style="text-align: center; padding: 20px; color: #f00;">渲染失败: ' + e.message + '</div>';
                    }
                }, 100);
                
                'rendering_started';
            } catch(e) {
                console.error('❌ 渲染启动失败:', e);
                'rendering_failed';
            }
        """
        
        webView.evaluateJavaScript(script) { [weak self] (result, error) in
            if let error = error {
                print("❌ JavaScript执行错误: \(error)")
                self?.showError(message: "渲染失败: \(error.localizedDescription)")
            } else if let resultString = result as? String {
                if resultString == "rendering_started" {
                    print("✅ 大文件渲染已启动")
                    // 延迟隐藏加载状态，给渲染时间
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.hideLoadingState()
                    }
                } else {
                    print("❌ 渲染启动失败")
                    self?.showError(message: "渲染启动失败")
                }
            }
        }
    }
    
    private func renderImmediateMarkdown() {
        // 检查重试次数
        guard retryCount < maxRetryCount else {
            print("❌ DOM检查重试次数超限，直接尝试渲染")
            performMarkdownRender()
            return
        }
        
        // 先检查DOM是否已经准备好
        let checkDOMScript = """
            (function() {
                try {
                    var element = document.getElementById('rendered-content');
                    return element !== null && typeof renderMarkdown === 'function';
                } catch(e) {
                    return false;
                }
            })();
        """
        
        webView.evaluateJavaScript(checkDOMScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ DOM检查脚本执行错误: \(error)")
                self?.retryCount += 1
                self?.retryDOMCheck()
                return
            }
            
            if let isReady = result as? Bool, isReady {
                // DOM已准备好，开始渲染
                print("✅ DOM已准备好，开始渲染")
                self?.performMarkdownRender()
            } else {
                // DOM未准备好，延迟重试
                self?.retryCount += 1
                print("⏳ DOM未准备好，延迟重试... (第\(self?.retryCount ?? 0)次)")
                self?.retryDOMCheck()
            }
        }
    }
    
    private func retryDOMCheck() {
        guard retryCount < maxRetryCount else {
            print("❌ DOM检查重试次数超限，强制渲染")
            performMarkdownRender()
            return
        }
        
        let delay = min(0.2 * Double(retryCount), 2.0) // 递增延迟，最大2秒
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.renderImmediateMarkdown()
        }
    }
    
    private func performMarkdownRender() {
        // 直接渲染整个Markdown内容
        let escapedContent = escapeForJavaScript(markdownContent)
        let script = """
            document.getElementById('rendered-content').innerHTML = '';
            text = '';
            renderMarkdown('\(escapedContent)');
        """
        
        webView.evaluateJavaScript(script) { [weak self] (result, error) in
            if let error = error {
                print("❌ JavaScript执行错误: \(error)")
                self?.showError(message: "渲染失败: \(error.localizedDescription)")
            } else {
                print("✅ Markdown内容渲染完成")
                self?.hideLoadingState()
            }
        }
    }
    
    // MARK: - 状态管理
    private func showLoadingState(message: String, progress: Double) {
        loadingIndicator.startAnimating()
        loadingLabel.text = message
        loadingLabel.isHidden = false
        progressView.isHidden = false
        progressView.setProgress(Float(progress), animated: true)
        
        hideError()
    }
    
    private func hideLoadingState() {
        loadingIndicator.stopAnimating()
        loadingLabel.isHidden = true
        progressView.isHidden = true
        progressView.setProgress(0, animated: false)
    }
    
    // MARK: - 错误处理
    private func showError(message: String) {
        hideLoadingState()
        errorView.isHidden = false
        webView.isHidden = true
        
        if let messageLabel = errorView.subviews.first?.subviews.compactMap({ $0 as? UIStackView }).first?.arrangedSubviews[2] as? UILabel {
            messageLabel.text = message
        }
    }
    
    private func hideError() {
        errorView.isHidden = true
        webView.isHidden = false
    }
    
    // MARK: - 按钮事件
    @objc private func shareContent() {
        guard let file = markdownFile else { return }
        
        let activityVC = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        
        // iPad支持
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func refreshButtonTapped() {
        print("🔄 用户手动刷新")
        refreshWebView()
    }
    
    @objc private func retryLoadContent() {
        refreshWebView()
    }
    
    private func refreshWebView() {
        print("🔄 刷新WebView内容")
        hideError()
        
        // 重置状态
        isHTMLTemplateLoaded = false
        isTemplateLoading = false
        retryCount = 0
        
        // 保存当前内容作为待渲染内容
        if !markdownContent.isEmpty {
            pendingMarkdownContent = markdownContent
            print("📄 保存当前Markdown内容，等待HTML模板重新加载")
        }
        
        showLoadingState(message: "正在刷新...", progress: 0.0)
        loadHTMLTemplate()
    }
    
    // MARK: - 工具方法
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



// MARK: - WKNavigationDelegate
extension MarkdownReaderViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ WebView导航完成")
        isHTMLTemplateLoaded = true
        isTemplateLoading = false
        showLoadingState(message: "渲染器加载完成", progress: 0.5)
        
        // 验证DOM是否真正准备好
        let verifyDOMScript = """
            (function() {
                try {
                    var element = document.getElementById('rendered-content');
                    var hasRenderFunction = typeof renderMarkdown === 'function';
                    console.log('DOM验证: element=' + (element !== null) + ', renderFunction=' + hasRenderFunction);
                    return element !== null && hasRenderFunction;
                } catch(e) {
                    console.log('DOM验证错误: ' + e.message);
                    return false;
                }
            })();
        """
        
        webView.evaluateJavaScript(verifyDOMScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ DOM验证脚本执行错误: \(error)")
                self?.isTemplateLoading = false
            } else if let isReady = result as? Bool {
                print("🔍 DOM验证结果: \(isReady)")
                if isReady {
                    // DOM已准备好，检查是否有待渲染的内容
                    if let pendingContent = self?.pendingMarkdownContent, !pendingContent.isEmpty {
                        print("📄 发现待渲染内容，开始渲染")
                        self?.markdownContent = pendingContent
                        self?.pendingMarkdownContent = nil
                        self?.renderMarkdownContent()
                    } else if !(self?.markdownContent.isEmpty ?? true) {
                        print("📄 渲染当前Markdown内容")
                        self?.renderMarkdownContent()
                    } else {
                        print("📄 无内容需要渲染")
                        self?.hideLoadingState()
                    }
                } else {
                    print("⚠️ DOM未完全准备好，等待后续检查")
                    self?.hideLoadingState()
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView加载失败: \(error.localizedDescription)")
        
        // 重置加载状态
        isHTMLTemplateLoaded = false
        isTemplateLoading = false
        
        // 检查是否是网络权限问题
        if error.localizedDescription.contains("网络") || error.localizedDescription.contains("network") {
            needsRefreshAfterPermission = true
            showError(message: "首次加载需要网络权限，授权后将自动刷新")
        } else {
            showError(message: "网页加载失败: \(error.localizedDescription)")
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView预加载失败: \(error.localizedDescription)")
        
        // 重置加载状态
        isHTMLTemplateLoaded = false
        isTemplateLoading = false
        
        // 检查是否是网络权限问题
        if error.localizedDescription.contains("网络") || error.localizedDescription.contains("network") {
            needsRefreshAfterPermission = true
            showError(message: "首次加载需要网络权限，授权后将自动刷新")
        } else {
            showError(message: "网页加载失败: \(error.localizedDescription)")
        }
    }
}
