//
//  MarkdownReaderViewController.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import UIKit
import WebKit
import SnapKit
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
        
        print("🔧 配置WebView...")
        
        // 使用现代化的JavaScript配置
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        print("✅ JavaScript已启用")
        
        // 优化性能配置
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false
        
        // 禁用不必要的功能以提升性能
        config.allowsAirPlayForMediaPlayback = false
        config.allowsPictureInPictureMediaPlayback = false
        
        // 配置网络相关设置
        if #available(iOS 14.0, *) {
            config.limitsNavigationsToAppBoundDomains = false
            print("✅ 允许访问外部域名")
        }
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        
        // 隐藏所有滚动指示器以获得更清洁的视觉效果
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        
        // 优化滚动性能
        webView.scrollView.decelerationRate = UIScrollView.DecelerationRate.normal
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        
        // 移除WebView的边框和其他可能的视觉元素
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        // 强制移除所有可能的边框和边距
        webView.layer.borderWidth = 0
        webView.layer.borderColor = UIColor.clear.cgColor
        webView.clipsToBounds = false
        webView.layer.masksToBounds = false
        
        // 设置ScrollView的边距为零
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.clipsToBounds = false
        webView.scrollView.layer.masksToBounds = false
        
        // 隐藏WKBackdropView以消除边框线条
        DispatchQueue.main.async {
            self.hideWKBackdropView(in: webView)
        }
        
        print("✅ WebView配置完成")
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
        stackView.snp.makeConstraints { make in
            make.center.equalTo(view)
            make.leading.greaterThanOrEqualTo(view).offset(32)
            make.trailing.lessThanOrEqualTo(view).offset(-32)
        }
        
        imageView.snp.makeConstraints { make in
            make.size.equalTo(50)
        }
        
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
    private var themeInitRetryCount: Int = 0
    private let maxThemeInitRetryCount: Int = 3
    
    // MARK: - WebView辅助方法
    private func hideWKBackdropView(in webView: WKWebView) {
        // 递归遍历WebView的子视图，彻底清理所有可能的边框和背景
        func cleanupWebViewLayers(in view: UIView, level: Int = 0) {
            let className = NSStringFromClass(type(of: view))
            let indent = String(repeating: "  ", count: level)
            print("🔍 \(indent)检查视图: \(className)")
            
            // 针对所有WebKit内部视图进行处理
            if className.contains("WK") {
                // 设置透明背景
                view.backgroundColor = UIColor.clear
                view.isOpaque = false
                
                // 移除边框
                view.layer.borderWidth = 0
                view.layer.borderColor = UIColor.clear.cgColor
                
                // 移除阴影
                view.layer.shadowOpacity = 0
                view.layer.shadowRadius = 0
                
                // 特殊处理不同类型的WebKit视图
                if className.contains("WKBackdrop") {
                    view.isHidden = true
                    view.alpha = 0
                    print("🔧 \(indent)已隐藏WKBackdropView: \(className)")
                }
                else if className.contains("WKContentView") {
                    // WKContentView特殊处理
                    view.clipsToBounds = false
                    view.layer.masksToBounds = false
                    
                    // 移除可能的边距
                    if let scrollView = view.superview as? UIScrollView {
                        scrollView.contentInset = .zero
                        scrollView.scrollIndicatorInsets = .zero
                        scrollView.contentOffset = .zero
                    }
                    
                    print("🔧 \(indent)已处理WKContentView: \(className)")
                }
                else if className.contains("WKScrollView") {
                    // WKScrollView特殊处理
                    if let scrollView = view as? UIScrollView {
                        scrollView.contentInset = .zero
                        scrollView.scrollIndicatorInsets = .zero
                        scrollView.contentInsetAdjustmentBehavior = .never
                    }
                    print("🔧 \(indent)已处理WKScrollView: \(className)")
                }
                
                print("🔧 \(indent)已清理WebKit视图: \(className)")
            }
            
            // 递归处理子视图
            for subview in view.subviews {
                cleanupWebViewLayers(in: subview, level: level + 1)
            }
        }
        
        print("🔧 开始清理WebView层次结构...")
        cleanupWebViewLayers(in: webView)
        
        // 额外的WebView设置
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.clipsToBounds = false
        webView.clipsToBounds = false
        
        // 添加持续监听，防止动态添加的视图
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔧 延迟清理WebView层次结构...")
            cleanupWebViewLayers(in: webView)
        }
        
        // 再次延迟处理，确保完全清理
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔧 最终清理WebView层次结构...")
            cleanupWebViewLayers(in: webView)
        }
    }
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNetworkMonitoring()
        updateTitle()
        
        // 设置主题管理器
        setupThemeManager()
        
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
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 移除通知观察者
        NotificationCenter.default.removeObserver(self, name: ThemeManager.themeDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("UpdateThemeButtonNotification"), object: nil)
    }
    
    deinit {
        networkMonitor?.cancel()
        
        // 确保移除所有通知观察者
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI设置
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        
        // 设置导航栏
        navigationItem.largeTitleDisplayMode = .never
        
        // 隐藏导航栏底部分隔线
        navigationController?.navigationBar.shadowImage = UIImage()
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        
        // iOS 13+ 的导航栏外观设置
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.shadowColor = .clear // 移除底部阴影线
            appearance.shadowImage = UIImage() // 移除底部分隔线
            navigationController?.navigationBar.standardAppearance = appearance
            navigationController?.navigationBar.scrollEdgeAppearance = appearance
        }
        
        // 添加右侧分享按钮
        setupNavigationButtons()
        
        // 创建WebView容器来裁剪可能的边框
        let webViewContainer = UIView()
        webViewContainer.backgroundColor = UIColor.clear
        webViewContainer.clipsToBounds = true // 关键：裁剪超出边界的内容
        view.addSubview(webViewContainer)
        
        webViewContainer.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalTo(view)
        }
        
        // 设置WebView - 扩展一点点来隐藏可能的边框
        webViewContainer.addSubview(webView)
        webView.snp.makeConstraints { make in
            make.top.equalTo(webViewContainer)
            make.leading.equalTo(webViewContainer).offset(-2)
            make.trailing.equalTo(webViewContainer).offset(2)
            make.bottom.equalTo(webViewContainer).offset(2) 
        }
        
        // 设置加载指示器和相关组件
        view.addSubview(loadingIndicator)
        view.addSubview(loadingLabel)
        view.addSubview(progressView)
        
        loadingIndicator.snp.makeConstraints { make in
            make.centerX.equalTo(webViewContainer)
            make.centerY.equalTo(webViewContainer).offset(-30)
        }
        
        loadingLabel.snp.makeConstraints { make in
            make.centerX.equalTo(webViewContainer)
            make.top.equalTo(loadingIndicator.snp.bottom).offset(16)
        }
        
        progressView.snp.makeConstraints { make in
            make.centerX.equalTo(webViewContainer)
            make.top.equalTo(loadingLabel.snp.bottom).offset(16)
            make.width.equalTo(200)
        }
        
        // 设置错误视图
        view.addSubview(errorView)
        errorView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalTo(view)
        }
    }
    
    private func setupNavigationButtons() {
        // 创建返回按钮
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )
        backButton.tintColor = .systemOrange
        
        // 隐藏系统默认的返回按钮
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = backButton
        
        // 创建主题切换按钮
        let themeButton = ThemeManager.shared.createThemeToggleButton()
        
        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareContent)
        )
        shareButton.tintColor = .systemOrange
        
        let refreshButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshButtonTapped)
        )
        refreshButton.tintColor = .systemOrange
        
        // 主题按钮放在最左边
        navigationItem.rightBarButtonItems = [themeButton, shareButton, refreshButton]
    }
    
    private func setupThemeManager() {
        // 设置WebView引用到主题管理器
        ThemeManager.shared.setWebView(webView)
        
        // 监听主题变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.themeDidChangeNotification,
            object: nil
        )
        
        // 监听主题按钮更新通知
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UpdateThemeButtonNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThemeButton()
        }
        
        print("🎨 主题管理器已设置")
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
        themeInitRetryCount = 0 // 重置主题初始化重试计数器
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
        print("🎨 开始统一分块渲染")
        
        // 所有文件都使用分块渲染，根据文件大小调整分块策略
        renderMarkdownInChunks()
    }
    
    private func renderMarkdownInChunks() {
        guard !markdownContent.isEmpty else {
            print("⚠️ Markdown内容为空，跳过分块渲染")
            hideLoadingState()
            return
        }
        
        let contentSize = markdownContent.count
        print("🔄 开始统一分块渲染，文件大小: \(contentSize) 字符")
        
        // 根据文件大小智能调整分块策略
        let (chunkSize, delayInterval, progressMessage) = getChunkStrategy(for: contentSize)
        
        // 按行分割内容
        let lines = markdownContent.components(separatedBy: .newlines)
        let totalLines = lines.count
        
        showLoadingState(message: progressMessage, progress: 0.8)
        
        // 初始化渲染环境
        let initScript = """
            try {
                // 清空内容容器
                document.getElementById('rendered-content').innerHTML = '';
                
                // 创建分块渲染容器
                var chunkContainer = document.createElement('div');
                chunkContainer.id = 'chunk-container';
                chunkContainer.style.cssText = 'width: 100%; min-height: 100vh;';
                document.getElementById('rendered-content').appendChild(chunkContainer);
                
                // 初始化分块渲染状态
                window.chunkRenderState = {
                    container: chunkContainer,
                    totalChunks: Math.ceil(\(totalLines) / \(chunkSize)),
                    renderedChunks: 0,
                    isRendering: false,
                    chunkSize: \(chunkSize),
                    delayInterval: \(delayInterval)
                };
                
                console.log('✅ 统一分块渲染环境初始化完成');
                console.log('📊 文件大小: \(contentSize) 字符, 总行数: \(totalLines), 块大小: \(chunkSize) 行, 总块数: ' + window.chunkRenderState.totalChunks);
                'init_success';
            } catch(e) {
                console.error('❌ 分块渲染初始化失败:', e);
                'init_failed';
            }
        """
        
        webView.evaluateJavaScript(initScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ 分块渲染初始化失败: \(error)")
                self?.performCompleteMarkdownRender()
                return
            }
            
            if let resultString = result as? String, resultString == "init_success" {
                print("✅ 分块渲染环境初始化成功")
                self?.renderNextChunk(lines: lines, chunkSize: chunkSize, currentIndex: 0, delayInterval: delayInterval)
            } else {
                print("❌ 分块渲染初始化失败，回退到完整渲染")
                self?.performCompleteMarkdownRender()
            }
        }
    }
    
    /// 根据文件大小获取最佳分块策略
    private func getChunkStrategy(for contentSize: Int) -> (chunkSize: Int, delayInterval: TimeInterval, progressMessage: String) {
        if contentSize < 10000 { // 小于10KB
            return (chunkSize: 200, delayInterval: 0.05, progressMessage: "快速渲染中...")
        } else if contentSize < 50000 { // 10KB - 50KB
            return (chunkSize: 100, delayInterval: 0.08, progressMessage: "优化渲染中...")
        } else if contentSize < 100000 { // 50KB - 100KB
            return (chunkSize: 75, delayInterval: 0.1, progressMessage: "分块渲染中...")
        } else { // 大于100KB
            return (chunkSize: 50, delayInterval: 0.12, progressMessage: "深度优化渲染中...")
        }
    }
    
    private func renderNextChunk(lines: [String], chunkSize: Int, currentIndex: Int, delayInterval: TimeInterval) {
        guard currentIndex < lines.count else {
            print("✅ 所有分块渲染完成")
            finalizeChunkRendering()
            return
        }
        
        let endIndex = min(currentIndex + chunkSize, lines.count)
        let chunkLines = Array(lines[currentIndex..<endIndex])
        let chunkContent = chunkLines.joined(separator: "\n")
        let chunkNumber = (currentIndex / chunkSize) + 1
        let totalChunks = (lines.count + chunkSize - 1) / chunkSize
        
        // 更新进度
        let progress = 0.8 + (0.2 * Double(currentIndex) / Double(lines.count))
        showLoadingState(message: "渲染中... (\(chunkNumber)/\(totalChunks))", progress: progress)
        
        print("📄 渲染第\(chunkNumber)块 (行\(currentIndex+1)-\(endIndex))")
        
        let escapedContent = escapeForJavaScript(chunkContent)
        
        let renderScript = """
            try {
                if (!window.chunkRenderState || window.chunkRenderState.isRendering) {
                    console.log('⏳ 等待上一块渲染完成...');
                    'chunk_busy';
                } else {
                    window.chunkRenderState.isRendering = true;
                    
                    // 渲染当前块
                    var chunkHtml = marked.parse('\(escapedContent)');
                    
                    // 创建块容器
                    var chunkDiv = document.createElement('div');
                    chunkDiv.className = 'markdown-chunk';
                    chunkDiv.setAttribute('data-chunk', '\(chunkNumber)');
                    chunkDiv.style.cssText = 'margin-bottom: 10px; opacity: 0; transition: opacity 0.3s ease;';
                    chunkDiv.innerHTML = chunkHtml;
                    
                    // 添加到容器
                    window.chunkRenderState.container.appendChild(chunkDiv);
                    
                    // 淡入效果
                    setTimeout(function() {
                        chunkDiv.style.opacity = '1';
                    }, 50);
                    
                    window.chunkRenderState.renderedChunks++;
                    window.chunkRenderState.isRendering = false;
                    
                    console.log('✅ 第\(chunkNumber)块渲染完成');
                    'chunk_rendered';
                }
            } catch(e) {
                console.error('❌ 分块渲染失败:', e);
                window.chunkRenderState.isRendering = false;
                'chunk_failed';
            }
        """
        
        webView.evaluateJavaScript(renderScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ 第\(chunkNumber)块渲染失败: \(error)")
                self?.performCompleteMarkdownRender()
                return
            }
            
            if let resultString = result as? String {
                switch resultString {
                case "chunk_rendered":
                    // 延迟一点再渲染下一块，避免GPU过载
                    DispatchQueue.main.asyncAfter(deadline: .now() + delayInterval) {
                        self?.renderNextChunk(lines: lines, chunkSize: chunkSize, currentIndex: endIndex, delayInterval: delayInterval)
                    }
                case "chunk_busy":
                    // 等待一下再重试
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self?.renderNextChunk(lines: lines, chunkSize: chunkSize, currentIndex: currentIndex, delayInterval: delayInterval)
                    }
                case "chunk_failed":
                    print("❌ 分块渲染失败，回退到完整渲染")
                    self?.performCompleteMarkdownRender()
                default:
                    print("⚠️ 未知的渲染结果: \(resultString)")
                    self?.performCompleteMarkdownRender()
                }
            }
        }
    }
    
    private func finalizeChunkRendering() {
        print("🎨 完成分块渲染，开始后处理...")
        
        let finalizeScript = """
            try {
                // 处理所有渲染增强功能
                var container = document.getElementById('rendered-content');
                if (container) {
                    console.log('🔗 处理链接功能');
                    processLinks(container);
                    
                    console.log('🖼️ 处理图片功能');
                    addImageZoomFunction(container);
                    
                    console.log('📋 处理代码复制功能');
                    addCodeCopyButtons(container);
                    
                    console.log('☑️ 处理任务列表功能');
                    enhanceTaskLists(container);
                    
                    console.log('🎨 处理Mermaid图表');
                    renderMermaidDiagrams(container);
                    
                    console.log('📱 优化移动端表格');
                    optimizeTablesForMobile(container);
                    
                    console.log('🏷️ 优化HTML元素');
                    enhanceHTMLElements(container);
                    
                    console.log('📑 生成目录');
                    generateTOC();
                    
                    console.log('✅ 所有增强功能处理完成');
                }
                
                // 清理分块渲染状态
                delete window.chunkRenderState;
                
                'finalize_success';
            } catch(e) {
                console.error('❌ 后处理失败:', e);
                'finalize_failed';
            }
        """
        
        webView.evaluateJavaScript(finalizeScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ 后处理失败: \(error)")
            }
            
            // 延迟渲染LaTeX公式
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.renderMathJax()
            }
            
            // 隐藏加载状态
            self?.hideLoadingState()
        }
    }
    
    private func renderMathJax() {
        print("🧮 开始渲染LaTeX公式")
        
        let mathScript = """
            try {
                if (typeof MathJax !== 'undefined' && MathJax.typesetPromise) {
                    var container = document.getElementById('rendered-content');
                    if (container) {
                        MathJax.typesetPromise([container]).then(function() {
                            console.log('✅ LaTeX渲染完成');
                        }).catch(function(err) {
                            console.error('❌ LaTeX渲染错误:', err);
                        });
                    }
                } else {
                    console.warn('⚠️ MathJax未加载或不支持typesetPromise');
                }
                'math_started';
            } catch(e) {
                console.error('❌ LaTeX渲染启动失败:', e);
                'math_failed';
            }
        """
        
        webView.evaluateJavaScript(mathScript) { (result, error) in
            if let error = error {
                print("❌ LaTeX渲染启动失败: \(error)")
            } else {
                print("✅ LaTeX渲染已启动")
            }
        }
    }
    
    private func performCompleteMarkdownRender() {
        print("🔄 执行完整渲染作为回退方案")
        
        // 对于超大文件，进行预处理以减少渲染负担
        let processedContent = preprocessContentForRendering(markdownContent)
        let escapedContent = escapeForJavaScript(processedContent)
        
        showLoadingState(message: "正在处理内容...", progress: 0.9)
        
        let script = """
            try {
                // 清空之前的内容
                document.getElementById('rendered-content').innerHTML = '';
                
                // 显示加载提示
                document.getElementById('rendered-content').innerHTML = '<div style="text-align: center; padding: 20px; color: #666;">正在渲染内容，请稍候...</div>';
                
                // 分步骤渲染以减少GPU负载
                setTimeout(function() {
                    try {
                        // 清空加载提示
                        document.getElementById('rendered-content').innerHTML = '';
                        
                        // 渲染内容
                        renderMarkdown('\(escapedContent)');
                        console.log('✅ 完整渲染完成');
                        
                        // 在渲染完成后，启动内存清理
                        if (typeof gc !== 'undefined') {
                            gc();
                        }
                        
                    } catch(e) {
                        console.error('❌ 渲染过程中出错:', e);
                        document.getElementById('rendered-content').innerHTML = '<div style="text-align: center; padding: 20px; color: #f00;">渲染失败: ' + e.message + '</div>';
                    }
                }, 200);
                
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
                    print("✅ 完整渲染已启动")
                    // 延迟隐藏加载状态，给渲染时间
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self?.hideLoadingState()
                    }
                } else {
                    print("❌ 渲染启动失败")
                    self?.showError(message: "渲染启动失败")
                }
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
    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func shareContent() {
        guard let file = markdownFile else { return }
        
        let activityVC = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        
        // iPad支持 - 现在是第二个按钮（分享按钮）
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?[1]
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
        themeInitRetryCount = 0 // 重置主题初始化重试计数器
        
        // 保存当前内容作为待渲染内容
        if !markdownContent.isEmpty {
            pendingMarkdownContent = markdownContent
            print("📄 保存当前Markdown内容，等待HTML模板重新加载")
        }
        
        showLoadingState(message: "正在刷新...", progress: 0.0)
        loadHTMLTemplate()
    }
    
    // MARK: - 主题管理事件
    @objc private func themeDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let theme = userInfo["theme"] as? UIUserInterfaceStyle else {
            return
        }
        
        print("🎨 主题已变化为: \(theme == .dark ? "深色" : "浅色")")
        
        // 处理主题变化后的额外逻辑
        updateUIForTheme(theme)
        
        // 同步主题到WebView（如果不是从WebView发起的变化）
        syncThemeToWebView(theme)
    }
    
    private func syncThemeToWebView(_ theme: UIUserInterfaceStyle) {
        guard isHTMLTemplateLoaded else {
            print("⚠️ WebView未加载完成，跳过主题同步")
            return
        }
        
        let themeString = (theme == .dark) ? "dark" : "light"
        
        // 使用handleNativeThemeChange函数，这个函数不会反向通知原生应用
        let syncScript = """
            (function() {
                try {
                    console.log('🔄 原生->WebView主题同步: \(themeString)');
                    if (window.handleNativeThemeChange && typeof window.handleNativeThemeChange === 'function') {
                        window.handleNativeThemeChange('\(themeString)');
                        console.log('✅ WebView主题同步成功');
                        return true;
                    } else {
                        console.warn('⚠️ WebView handleNativeThemeChange函数未准备好');
                        return false;
                    }
                } catch(e) {
                    console.error('❌ WebView主题同步失败:', e.message);
                    return false;
                }
            })();
        """
        
        webView.evaluateJavaScript(syncScript) { result, error in
            if let error = error {
                print("❌ WebView主题同步失败: \(error)")
            } else if let success = result as? Bool, success {
                print("✅ WebView主题已同步: \(themeString)")
            } else {
                print("⚠️ WebView主题同步结果未知")
            }
        }
    }
    
    private func updateUIForTheme(_ theme: UIUserInterfaceStyle) {
        // 更新视图控制器的UI以匹配主题
        // 大部分UI会自动适配，这里处理特殊情况
        
        // 更新加载指示器颜色
        loadingIndicator.color = UIColor.systemBlue
        
        // 更新WebView背景色
        webView.backgroundColor = UIColor.systemBackground
        
        print("✅ UI已更新以匹配主题: \(theme == .dark ? "深色" : "浅色")")
    }
    
    private func updateThemeButton() {
        guard let rightBarButtonItems = navigationItem.rightBarButtonItems,
              let themeButton = rightBarButtonItems.first else {
            return
        }
        
        let currentTheme = ThemeManager.shared.getCurrentTheme()
        let imageName = (currentTheme == .dark) ? "sun.max" : "moon"
        themeButton.image = UIImage(systemName: imageName)
        
        print("🔄 主题按钮图标已更新: \(imageName)")
    }
    
    private func syncInitialThemeToWebView() {
        // 检查重试次数
        guard themeInitRetryCount < maxThemeInitRetryCount else {
            print("❌ WebView主题同步重试次数已达上限，停止重试")
            return
        }
        
        // 获取当前原生应用的主题状态
        let currentTheme = ThemeManager.shared.getCurrentTheme()
        let themeString = (currentTheme == .dark) ? "dark" : "light"
        
        print("🎨 尝试同步WebView主题 (\(themeInitRetryCount + 1)/\(maxThemeInitRetryCount)): \(themeString)")
        
        // 立即同步到WebView，不触发原生通知（避免循环）
        let syncScript = """
            (function() {
                try {
                    console.log('🎨 WebView初始化主题同步: \(themeString)');
                    if (window.handleNativeThemeChange && typeof window.handleNativeThemeChange === 'function') {
                        window.handleNativeThemeChange('\(themeString)');
                        console.log('✅ WebView主题已同步到: \(themeString)');
                        return true;
                    } else {
                        console.warn('⚠️ WebView handleNativeThemeChange函数未准备好');
                        return false;
                    }
                } catch(e) {
                    console.error('❌ WebView主题同步失败:', e.message);
                    return false;
                }
            })();
        """
        
        themeInitRetryCount += 1
        
        webView.evaluateJavaScript(syncScript) { [weak self] result, error in
            if let error = error {
                print("❌ WebView初始主题同步失败: \(error)")
                // 如果同步失败且未达到重试上限，短暂延迟后重试
                if let self = self, self.themeInitRetryCount < self.maxThemeInitRetryCount {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.syncInitialThemeToWebView()
                    }
                }
            } else if let success = result as? Bool, success {
                print("✅ WebView初始主题已同步: \(themeString)")
                self?.themeInitRetryCount = 0 // 重置重试计数器
            } else {
                print("⚠️ WebView主题同步结果未知")
                // 如果结果未知且未达到重试上限，短暂延迟后重试
                if let self = self, self.themeInitRetryCount < self.maxThemeInitRetryCount {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.syncInitialThemeToWebView()
                    }
                }
            }
        }
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
    
    /// 预处理内容以减少渲染负担
    private func preprocessContentForRendering(_ content: String) -> String {
        let contentSize = content.count
        
        // 对于超大文件，进行一些优化
        if contentSize > 200000 { // 大于200KB
            print("🔧 预处理超大文件以减少渲染负担")
            
            // 简化一些复杂的内容
            var processedContent = content
            
            // 1. 限制连续空行数量
            processedContent = processedContent.replacingOccurrences(
                of: "\n\n\n+",
                with: "\n\n",
                options: .regularExpression
            )
            
            // 2. 简化过长的代码块
            processedContent = simplifyLongCodeBlocks(processedContent)
            
            // 3. 压缩连续的相似列表项
            processedContent = compressSimilarListItems(processedContent)
            
            print("🔧 预处理完成，大小从\(contentSize)减少到\(processedContent.count)")
            return processedContent
        }
        
        return content
    }
    
    /// 简化过长的代码块
    private func simplifyLongCodeBlocks(_ content: String) -> String {
        let pattern = "```([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return content
        }
        
        let range = NSRange(location: 0, length: content.count)
        let matches = regex.matches(in: content, options: [], range: range)
        
        var processedContent = content
        var offset = 0
        
        for match in matches {
            let matchRange = NSRange(location: match.range.location + offset, length: match.range.length)
            guard let stringRange = Range(matchRange, in: processedContent) else { continue }
            
            let matchedText = String(processedContent[stringRange])
            
            // 如果代码块太长，进行截断
            if matchedText.count > 5000 {
                let truncated = String(matchedText.prefix(5000))
                let replacement = truncated + "\n\n// ... 代码块已截断以优化渲染性能 ...\n```"
                
                processedContent.replaceSubrange(stringRange, with: replacement)
                offset += replacement.count - matchedText.count
            }
        }
        
        return processedContent
    }
    
    /// 压缩相似的列表项
    private func compressSimilarListItems(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var consecutiveListItems = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
                consecutiveListItems += 1
                
                // 如果连续的列表项太多，进行压缩
                if consecutiveListItems > 50 && consecutiveListItems % 10 == 0 {
                    processedLines.append("- ... (已压缩部分列表项以优化渲染)")
                    continue
                }
            } else {
                consecutiveListItems = 0
            }
            
            processedLines.append(line)
        }
        
        return processedLines.joined(separator: "\n")
    }
}



// MARK: - WKNavigationDelegate
extension MarkdownReaderViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 获取请求的URL
        guard let url = navigationAction.request.url else {
            print("⚠️ 导航请求无URL")
            decisionHandler(.allow)
            return
        }
        
        let urlString = url.absoluteString
        print("🔍 WebView导航请求: \(urlString)")
        
        // 检查是否是初始页面加载（本地HTML文件）
        if urlString.contains("markdown_viewer.html") {
            print("📄 允许加载本地HTML文件")
            decisionHandler(.allow)
            return
        }
        
        // 处理不同类型的链接
        if urlString.starts(with: "mailto:") {
            // 邮件链接
            print("📧 检测到邮件链接")
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url) { success in
                    if success {
                        print("✅ 成功打开邮件链接: \(urlString)")
                    } else {
                        print("❌ 邮件链接打开失败: \(urlString)")
                    }
                }
            } else {
                print("❌ 无法打开邮件链接（系统不支持）: \(urlString)")
            }
            decisionHandler(.cancel)
            return
        }
        
        if urlString.starts(with: "tel:") {
            // 电话链接
            print("📞 检测到电话链接")
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url) { success in
                    if success {
                        print("✅ 成功打开电话链接: \(urlString)")
                    } else {
                        print("❌ 电话链接打开失败: \(urlString)")
                    }
                }
            } else {
                print("❌ 无法打开电话链接（系统不支持）: \(urlString)")
            }
            decisionHandler(.cancel)
            return
        }
        
        if urlString.starts(with: "http://") || urlString.starts(with: "https://") {
            // 外链 - 在外部浏览器中打开
            print("🌐 检测到外链，将在外部浏览器打开")
            UIApplication.shared.open(url) { success in
                if success {
                    print("✅ 成功打开外链: \(urlString)")
                } else {
                    print("❌ 无法打开外链: \(urlString)")
                }
            }
            decisionHandler(.cancel)
            return
        }
        
        if urlString.starts(with: "#") {
            // 锚点链接 - 允许在当前页面处理
            print("🔗 检测到锚点链接，允许页面内处理")
            decisionHandler(.allow)
            return
        }
        
        // 其他链接类型 - 默认允许
        print("🤔 未知链接类型，默认允许: \(urlString)")
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ WebView导航完成")
        isHTMLTemplateLoaded = true
        isTemplateLoading = false
        showLoadingState(message: "渲染器加载完成", progress: 0.5)
        
        // 确保完全隐藏WKBackdropView
        hideWKBackdropView(in: webView)
        
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
                    // DOM已准备好，首先同步当前主题到WebView
                    self?.syncInitialThemeToWebView()
                    
                    // 然后检查是否有待渲染的内容
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

