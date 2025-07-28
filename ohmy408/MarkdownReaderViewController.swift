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
    
    // MARK: - 通知观察者管理
    private var notificationObservers: [NSObjectProtocol] = []
    
    // MARK: - 异步操作状态管理
    private var isProcessingAsyncOperation: Bool = false
    
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
        
        // 配置JavaScript消息处理器
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "nativePrint")
        config.userContentController = userContentController
        
        // 配置网络相关设置 - 优化沙盒兼容性
        if #available(iOS 14.0, *) {
            config.limitsNavigationsToAppBoundDomains = true // 限制为应用域名，减少沙盒冲突
            print("✅ 限制访问域名以提高沙盒兼容性")
        }
        
        // 禁用数据检测器以减少系统资源访问
        config.dataDetectorTypes = []
        
        // 设置进程池以提高隔离性
        config.processPool = WKProcessPool()
        
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
    private var isFirstTimeInstall: Bool = false
    private var sandboxInitialized: Bool = false

    
    // MARK: - 加载状态管理
    
    /// 加载步骤枚举
    private enum LoadingStep: CaseIterable {
        case initializing       // 初始化
        case loadingTemplate    // 加载模板
        case readingFile        // 读取文件
        case preparingRenderer  // 准备渲染器
        case analyzing          // 分析内容
        case chunking          // 智能分块
        case rendering         // 渲染内容
        case enhancing         // 增强功能
        case finalizing        // 完成处理
        
        var title: String {
            switch self {
            case .initializing: return "初始化"
            case .loadingTemplate: return "加载渲染引擎"
            case .readingFile: return "读取文件内容"
            case .preparingRenderer: return "准备渲染环境"
            case .analyzing: return "分析文档结构"
            case .chunking: return "智能分块处理"
            case .rendering: return "渲染Markdown"
            case .enhancing: return "处理增强功能"
            case .finalizing: return "完成渲染"
            }
        }
        
        var subtitle: String {
            switch self {
            case .initializing: return "准备加载文档..."
            case .loadingTemplate: return "加载HTML模板和JavaScript引擎..."
            case .readingFile: return "从存储中读取文档内容..."
            case .preparingRenderer: return "初始化Markdown渲染器..."
            case .analyzing: return "检测代码块、表格、图表等结构..."
            case .chunking: return "为大文档进行智能分块..."
            case .rendering: return "将Markdown转换为HTML..."
            case .enhancing: return "处理LaTeX公式、Mermaid图表..."
            case .finalizing: return "优化显示效果..."
            }
        }
        
        var baseProgress: Double {
            let allSteps = LoadingStep.allCases
            let currentIndex = allSteps.firstIndex(of: self) ?? 0
            return Double(currentIndex) / Double(allSteps.count - 1)
        }
        
        var progressWeight: Double {
            switch self {
            case .initializing: return 0.05   // 5%
            case .loadingTemplate: return 0.15  // 15%
            case .readingFile: return 0.08     // 8%
            case .preparingRenderer: return 0.07  // 7%
            case .analyzing: return 0.08       // 8%
            case .chunking: return 0.07        // 7%
            case .rendering: return 0.35       // 35%
            case .enhancing: return 0.12       // 12%
            case .finalizing: return 0.03      // 3%
            }
        }
    }
    
    /// 当前加载状态
    private struct LoadingState {
        var currentStep: LoadingStep = .initializing
        var stepProgress: Double = 0.0  // 当前步骤内的进度 (0.0-1.0)
        var totalProgress: Double {
            let previousStepsProgress = LoadingStep.allCases
                .prefix(upTo: LoadingStep.allCases.firstIndex(of: currentStep) ?? 0)
                .reduce(0.0) { $0 + $1.progressWeight }
            let currentStepProgress = previousStepsProgress + (currentStep.progressWeight * stepProgress)
            // 确保总进度不超过100%
            return min(currentStepProgress, 1.0)
        }
        var startTime: Date = Date()
        var estimatedTimeRemaining: TimeInterval? {
            guard totalProgress > 0.1 else { return nil }
            let elapsed = Date().timeIntervalSince(startTime)
            let estimatedTotal = elapsed / totalProgress
            return max(0, estimatedTotal - elapsed)
        }
    }
    
    private var loadingState = LoadingState()
    
    /// 详细的加载标签
    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = UIColor.tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.isHidden = true
        return label
    }()
    
    /// 时间估算标签
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor.quaternaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()
    
    /// 步骤指示器
    private lazy var stepIndicator: UIView = {
        let container = UIView()
        container.isHidden = true
        return container
    }()
    
    /// 更新加载状态
    private func updateLoadingState(step: LoadingStep, progress: Double = 0.0, detail: String? = nil) {
        loadingState.currentStep = step
        loadingState.stepProgress = max(0.0, min(1.0, progress))
        
        let percentage = Int(loadingState.totalProgress * 100)
        let mainMessage = "\(step.title) (\(percentage)%)"
        let detailMessage = detail ?? step.subtitle
        
        loadingIndicator.startAnimating()
        loadingLabel.text = mainMessage
        loadingLabel.isHidden = false
        
        detailLabel.text = detailMessage
        detailLabel.isHidden = false
        
        progressView.isHidden = false
        progressView.setProgress(Float(loadingState.totalProgress), animated: true)
        
        // 更新时间估算
        updateTimeEstimate()
        
        // 更新步骤指示器
        updateStepIndicator()
        
        hideError()
        
        print("📊 加载进度: \(step.title) \(Int(loadingState.totalProgress * 100))% - \(detailMessage)")
    }
    
    /// 更新时间估算
    private func updateTimeEstimate() {
        if let remainingTime = loadingState.estimatedTimeRemaining {
            if remainingTime > 60 {
                let minutes = Int(remainingTime / 60)
                timeLabel.text = "预计还需 \(minutes) 分钟"
            } else if remainingTime > 5 {
                let seconds = Int(remainingTime)
                timeLabel.text = "预计还需 \(seconds) 秒"
            } else {
                timeLabel.text = "即将完成..."
            }
            timeLabel.isHidden = false
        } else {
            timeLabel.isHidden = true
        }
    }
    
    /// 更新步骤指示器
    private func updateStepIndicator() {
        stepIndicator.subviews.forEach { $0.removeFromSuperview() }
        
        let allSteps = LoadingStep.allCases
        let currentStepIndex = allSteps.firstIndex(of: loadingState.currentStep) ?? 0
        
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.distribution = .fillEqually
        
        for (index, _) in allSteps.enumerated() {
            let dot = UIView()
            dot.layer.cornerRadius = 3
            dot.snp.makeConstraints { make in
                make.width.height.equalTo(6)
            }
            
            if index < currentStepIndex {
                // 已完成的步骤 - 绿色
                dot.backgroundColor = UIColor.systemGreen
            } else if index == currentStepIndex {
                // 当前步骤 - 蓝色
                dot.backgroundColor = UIColor.systemBlue
            } else {
                // 未来的步骤 - 灰色
                dot.backgroundColor = UIColor.systemGray4
            }
            
            stackView.addArrangedSubview(dot)
        }
        
        stepIndicator.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        stepIndicator.isHidden = false
    }
    
    /// 重置加载状态
    private func resetLoadingState() {
        loadingState = LoadingState()
        
        // 调试：验证权重分配
        #if DEBUG
        validateProgressWeights()
        #endif
    }
    
    /// 验证进度权重分配是否正确
    private func validateProgressWeights() {
        let totalWeight = LoadingStep.allCases.reduce(0.0) { $0 + $1.progressWeight }
        if abs(totalWeight - 1.0) > 0.001 { // 允许小数点精度误差
            print("⚠️ 警告: 进度权重总和为 \(totalWeight * 100)%，应该为100%")
        } else {
            print("✅ 进度权重分配验证通过: \(Int(totalWeight * 100))%")
        }
    }
    
    /// 显示详细的加载状态
    private func showDetailedLoadingState(step: LoadingStep, progress: Double = 0.0, detail: String? = nil) {
        updateLoadingState(step: step, progress: progress, detail: detail)
    }
    
    /// 隐藏加载状态
    private func hideLoadingState() {
        loadingIndicator.stopAnimating()
        loadingLabel.isHidden = true
        detailLabel.isHidden = true
        timeLabel.isHidden = true
        progressView.isHidden = true
        stepIndicator.isHidden = true
        progressView.setProgress(0, animated: false)
        
        print("✅ 加载完成，总耗时: \(Date().timeIntervalSince(loadingState.startTime))秒")
    }
    
    // MARK: - 原有的简单方法（保持兼容性）
    private func showLoadingState(message: String, progress: Double) {
        // 尝试从消息中推断当前步骤
        let step = inferStepFromMessage(message)
        // 确保进度在合理范围内
        let safeProgress = max(0.0, min(1.0, progress))
        updateLoadingState(step: step, progress: safeProgress, detail: message)
    }
    
    private func inferStepFromMessage(_ message: String) -> LoadingStep {
        if message.contains("渲染器") || message.contains("模板") {
            return .loadingTemplate
        } else if message.contains("读取") || message.contains("文件") {
            return .readingFile
        } else if message.contains("准备") || message.contains("环境") {
            return .preparingRenderer
        } else if message.contains("分块") || message.contains("分析") {
            return .analyzing
        } else if message.contains("渲染") {
            return .rendering
        } else if message.contains("处理") || message.contains("增强") {
            return .enhancing
        } else if message.contains("完成") || message.contains("最后") {
            return .finalizing
        } else {
            return .initializing
        }
    }
    
    // MARK: - WebView辅助方法
    private func hideWKBackdropView(in webView: WKWebView) {
        // 简化：只做必要的WebView优化
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.clipsToBounds = false
        webView.scrollView.clipsToBounds = false
    }
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNetworkMonitoring()
        updateTitle()
        
        // 设置主题管理器
        setupThemeManager()
        
        // 确保初始状态正确
        ensureInitialState()
        
        // 延迟加载HTML模板，确保UI完全设置完成
        DispatchQueue.main.async { [weak self] in
            self?.loadHTMLTemplateIfNeeded()
        }
    }
    
    /// 确保初始状态正确设置
    private func ensureInitialState() {
        print("🔧 确保初始状态正确设置")
        
        // 检测是否为首次安装
        detectFirstTimeInstall()
        
        // 重置所有状态标志到安全的初始状态
        isHTMLTemplateLoaded = false
        isTemplateLoading = false
        isProcessingAsyncOperation = false
        hasNetworkPermission = false
        needsRefreshAfterPermission = false
        retryCount = 0
        themeInitRetryCount = 0
        
        // 清理待处理内容，防止旧内容干扰
        pendingMarkdownContent = nil
        
        // 边界检查：确保UI状态正确
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideError()
            self.hideLoadingState()
        }
        
        // 检查沙盒状态
        checkSandboxStatus()
        
        // 重置加载状态
        resetLoadingState()
        
        print("✅ 初始状态已重置")
    }
    
    /// 检测是否为首次安装
    private func detectFirstTimeInstall() {
        let userDefaults = UserDefaults.standard
        let hasLaunchedBefore = userDefaults.bool(forKey: "HasLaunchedBefore")
        
        if !hasLaunchedBefore {
            isFirstTimeInstall = true
            print("🆕 检测到首次安装")
            
            // 标记为已启动过
            userDefaults.set(true, forKey: "HasLaunchedBefore")
            userDefaults.synchronize()
        } else {
            isFirstTimeInstall = false
            print("🔄 应用已启动过")
        }
    }
    
    /// 检查沙盒状态
    private func checkSandboxStatus() {
        // 检查应用Bundle资源的访问权限
        guard let bundlePath = Bundle.main.bundlePath as NSString? else {
            print("❌ 无法获取Bundle路径")
            sandboxInitialized = false
            return
        }
        
        let htmlPath = bundlePath.appendingPathComponent("markdown_viewer.html")
        sandboxInitialized = FileManager.default.isReadableFile(atPath: htmlPath)
        
        print("📂 沙盒状态检查: \(sandboxInitialized ? "已初始化" : "未初始化")")
        
        if isFirstTimeInstall && !sandboxInitialized {
            print("🔒 首次安装且沙盒未初始化，可能出现权限延迟")
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
        // 视图出现时重新设置通知观察者
        setupNotificationObservers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 视图消失时移除通知观察者，避免在后台时响应通知
        removeNotificationObservers()
    }
    

    
    deinit {
        networkMonitor?.cancel()
        
        // 清理WebView相关引用，防止内存泄漏
        webView.navigationDelegate = nil
        webView.stopLoading()
        
        // 清理JavaScript消息处理器
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nativePrint")
        
        // 统一移除所有通知观察者
        removeNotificationObservers()
        
        print("🗑️ MarkdownReaderViewController已释放")
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
        view.addSubview(detailLabel)
        view.addSubview(progressView)
        view.addSubview(timeLabel)
        view.addSubview(stepIndicator)
        
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
        
        // 统一管理通知观察者，防止重复注册和内存泄漏
        setupNotificationObservers()
    }
    
    /// 统一设置所有通知观察者
    private func setupNotificationObservers() {
        // 清理之前的观察者（防止重复注册）
        removeNotificationObservers()
        
        // 监听主题变化 - 使用闭包方式统一管理
        let themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.themeDidChange()
        }
        notificationObservers.append(themeObserver)
        
        // 监听主题按钮更新通知
        let buttonObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("UpdateThemeButtonNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThemeButton()
        }
        notificationObservers.append(buttonObserver)
        
        print("📡 通知观察者已设置，共 \(notificationObservers.count) 个")
    }
    
    /// 移除所有通知观察者
    private func removeNotificationObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        print("🗑️ 所有通知观察者已移除")
    }
    
    private func updateTitle() {
        title = markdownFile?.displayName ?? "Markdown阅读器"
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
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
        // 防止重复操作的状态检查
        if isHTMLTemplateLoaded {
            print("📄 HTML模板已加载完成，跳过")
            return
        }
        
        if isTemplateLoading {
            print("📄 HTML模板正在加载中，跳过重复加载")
            return
        }
        
        // 边界检查：确保WebView已初始化
        guard webView.window != nil || view.window != nil else {
            print("⚠️ WebView或View未准备好，延迟加载HTML模板")
            DispatchQueue.main.async { [weak self] in
                self?.loadHTMLTemplateIfNeeded()
            }
            return
        }
        
        // 验证HTML文件是否存在且可访问
        guard let htmlURL = Bundle.main.url(forResource: "markdown_viewer", withExtension: "html") else {
            print("❌ 无法找到markdown_viewer.html文件")
            showError(message: "无法找到Markdown模板文件，请检查应用资源")
            return
        }
        
        // 验证文件可读性，简化处理
        if !FileManager.default.isReadableFile(atPath: htmlURL.path) {
            print("❌ HTML文件不可读，可能存在权限问题: \(htmlURL.path)")
            showError(message: "无法访问HTML模板文件\n可能是首次安装权限问题\n请重启应用")
            return
        }
        
        print("🔄 开始加载HTML模板: \(htmlURL.path)")
        
        // 重置所有状态标志
        isHTMLTemplateLoaded = false
        isTemplateLoading = true
        themeInitRetryCount = 0
        retryCount = 0
        
        resetLoadingState()
        showDetailedLoadingState(step: .loadingTemplate, progress: 0.1, detail: "初始化HTML模板和JavaScript引擎...")
        
        // 简化：直接加载HTML文件
        let request = URLRequest(url: htmlURL)
        webView.load(request)
    }
    
    private func loadHTMLTemplate() {
        loadHTMLTemplateIfNeeded()
    }
    

    
    private func loadMarkdownContent() {
        // 边界检查：确保文件对象存在
        guard let file = markdownFile else { 
            print("⚠️ markdownFile为nil，无法加载内容")
            hideLoadingState()
            return 
        }
        
        // 边界检查：确保文件URL有效
        guard file.url.isFileURL else {
            print("❌ 文件URL无效: \(file.url)")
            showError(message: "文件路径无效")
            return
        }
        
        // 边界检查：确保文件存在
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            print("❌ 文件不存在: \(file.url.path)")
            showError(message: "文件不存在: \(file.displayName)")
            return
        }
        
        // 确保HTML模板已开始加载
        loadHTMLTemplateIfNeeded()
        
        showDetailedLoadingState(step: .readingFile, progress: 0.2, detail: "从存储设备读取\(file.displayName)...")
        
        // 异步读取文件内容以避免阻塞UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let content = try String(contentsOf: file.url, encoding: .utf8)
                let fileSize = content.count
                let fileSizeText = self?.formatFileSize(fileSize) ?? "\(fileSize) 字符"
                
                // 边界检查：验证内容合理性
                guard fileSize > 0 else {
                    DispatchQueue.main.async { [weak self] in
                        self?.showError(message: "文件内容为空")
                    }
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    self.markdownContent = content
                    self.pendingMarkdownContent = content
                    print("📄 Markdown内容已读取，文件大小: \(fileSize) 字符")
                    
                    // 如果HTML模板已加载完成，立即渲染
                    if self.isHTMLTemplateLoaded {
                        self.renderMarkdownContent()
                    } else {
                        self.showDetailedLoadingState(step: .preparingRenderer, progress: 0.8, detail: "等待渲染引擎就绪，文件大小: \(fileSizeText)")
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    print("❌ 文件读取失败: \(error)")
                    self?.showError(message: "无法读取文件内容: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 格式化文件大小 - 边界安全版本
    private func formatFileSize(_ size: Int) -> String {
        // 边界检查：防止负数或异常值
        guard size >= 0 else {
            return "0 字符"
        }
        
        if size < 1024 {
            return "\(size) 字符"
        } else if size < 1024 * 1024 {
            let kb = Double(size) / 1024.0
            return String(format: "%.1f KB", kb)
        } else if size < 1024 * 1024 * 1024 {
            let mb = Double(size) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        } else {
            let gb = Double(size) / (1024.0 * 1024.0 * 1024.0)
            return String(format: "%.1f GB", gb)
        }
    }
    
    private func renderMarkdownContent() {
        // 边界检查：确保内容不为空
        guard !markdownContent.isEmpty else { 
            print("⚠️ Markdown内容为空，跳过渲染")
            hideLoadingState()
            return 
        }
        
        // 边界检查：确保WebView已初始化
        guard webView.window != nil || view.window != nil else {
            print("⚠️ WebView未准备好，延迟渲染")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.renderMarkdownContent()
            }
            return
        }
        
        // 状态检查：HTML模板是否已加载
        if !isHTMLTemplateLoaded {
            print("⏳ HTML模板未加载完成，将内容标记为待渲染")
            pendingMarkdownContent = markdownContent
            return
        }
        
        // 防止并发渲染操作
        guard !isProcessingAsyncOperation else {
            print("⚠️ 已有异步操作在进行中，跳过渲染")
            return
        }
        
        // 边界检查：内容大小限制（防止超大文件导致问题）
        if markdownContent.count > 5_000_000 { // 5MB 限制
            print("⚠️ 文件过大(\(formatFileSize(markdownContent.count)))，可能影响性能")
            showError(message: "文件过大(\(formatFileSize(markdownContent.count)))\n建议使用较小的文件")
            return
        }
        
        isProcessingAsyncOperation = true
        
        print("🎨 开始渲染Markdown内容")
        hideError()
        showDetailedLoadingState(step: .analyzing, progress: 0.1, detail: "分析文档结构...")
        retryCount = 0 // 重置重试计数
        
        // 直接调用renderMarkdown函数
        renderMarkdownDirectly()
    }
    
    private func renderMarkdownDirectly() {
        // 边界检查：确保状态正确
        guard isHTMLTemplateLoaded else {
            print("❌ HTML模板未加载，无法渲染")
            showError(message: "HTML模板未准备好")
            return
        }
        
        guard !markdownContent.isEmpty else {
            print("❌ Markdown内容为空，无法渲染")
            showError(message: "内容为空")
            return
        }
        
        print("🎨 开始直接渲染Markdown")
        
        let contentSize = markdownContent.count
        let fileSizeText = formatFileSize(contentSize)
        
        showDetailedLoadingState(step: .rendering, progress: 0.2, detail: "渲染\(fileSizeText)的文档...")
        
        // 转义JavaScript字符串，确保安全
        let escapedContent = escapeForJavaScript(markdownContent)
        
        // 边界检查：避免过长的内容导致问题
        if escapedContent.count > markdownContent.count * 2 {
            print("⚠️ 转义后内容过长，可能包含大量特殊字符")
        }
        
        let renderScript = """
            try {
                console.log('🔧 准备调用renderMarkdown函数');
                if (typeof window.renderMarkdown === 'function') {
                    window.renderMarkdown('\(escapedContent)');
                    console.log('✅ renderMarkdown调用成功');
                    'render_success';
                } else {
                    console.error('❌ renderMarkdown函数不存在');
                    'render_function_missing';
                }
            } catch(e) {
                console.error('❌ renderMarkdown调用失败:', e);
                'render_failed';
            }
        """
        
        webView.evaluateJavaScript(renderScript) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ renderMarkdown调用失败: \(error)")
                self.showError(message: "渲染失败: \(error.localizedDescription)")
                return
            }
            
            if let resultString = result as? String {
                switch resultString {
                case "render_success":
                    print("✅ renderMarkdown调用成功")
                    // 进入增强功能处理阶段，而不是直接结束
                    self.processEnhancingFeatures()
                case "render_function_missing":
                    print("❌ renderMarkdown函数不存在")
                    self.showError(message: "渲染函数不存在，请检查HTML模板")
                case "render_failed":
                    print("❌ renderMarkdown调用失败")
                    self.showError(message: "渲染调用失败")
                default:
                    print("⚠️ 未知的渲染结果: \(resultString)")
                    self.showError(message: "渲染过程异常")
                }
            } else {
                print("⚠️ 渲染结果为空或类型错误")
                self.showError(message: "渲染结果异常")
            }
        }
    }
    
    /// 处理增强功能阶段
    private func processEnhancingFeatures() {
        print("🔧 开始处理增强功能")
        showDetailedLoadingState(step: .enhancing, progress: 0.1, detail: "处理LaTeX公式和Mermaid图表...")
        
        // 处理增强功能的JavaScript
        let enhanceScript = """
            try {
                var container = document.getElementById('rendered-content');
                if (container) {
                    console.log('🔗 处理链接功能');
                    if (typeof processLinks === 'function') processLinks(container);
                    
                    console.log('🖼️ 处理图片功能');
                    if (typeof addImageZoomFunction === 'function') addImageZoomFunction(container);
                    
                    console.log('📋 处理代码复制功能');
                    if (typeof addCodeCopyButtons === 'function') addCodeCopyButtons(container);
                    
                    console.log('☑️ 处理任务列表功能');
                    if (typeof enhanceTaskLists === 'function') enhanceTaskLists(container);
                    
                    console.log('🎨 处理Mermaid图表');
                    if (typeof renderMermaidDiagrams === 'function') renderMermaidDiagrams(container);
                    
                    console.log('📱 优化移动端表格');
                    if (typeof optimizeTablesForMobile === 'function') optimizeTablesForMobile(container);
                    
                    console.log('🏷️ 优化HTML元素');
                    if (typeof enhanceHTMLElements === 'function') enhanceHTMLElements(container);
                    
                    console.log('📑 生成目录');
                    if (typeof generateTOC === 'function') generateTOC();
                    
                    console.log('✅ 增强功能处理完成');
                }
                'enhance_success';
            } catch(e) {
                console.error('❌ 增强功能处理失败:', e);
                'enhance_failed';
            }
        """
        
        webView.evaluateJavaScript(enhanceScript) { [weak self] (result, error) in
            guard let self = self else { return }
            
            // 更新进度到增强功能的70%
            self.showDetailedLoadingState(step: .enhancing, progress: 0.7, detail: "渲染LaTeX数学公式...")
            
            if let error = error {
                print("❌ 增强功能处理失败: \(error)")
                // 即使增强功能失败，也继续到最终化阶段
                self.processMathJax()
            } else if let resultString = result as? String {
                if resultString == "enhance_success" {
                    print("✅ 增强功能处理成功")
                } else {
                    print("⚠️ 增强功能处理返回: \(resultString)")
                }
                // 继续处理MathJax
                self.processMathJax()
            } else {
                print("⚠️ 增强功能处理结果异常")
                self.processMathJax()
            }
        }
    }
    
    /// 处理MathJax数学公式渲染
    private func processMathJax() {
        print("🧮 开始渲染LaTeX公式")
        
        let mathScript = """
            try {
                if (typeof MathJax !== 'undefined' && MathJax.typesetPromise) {
                    var container = document.getElementById('rendered-content');
                    if (container) {
                        // 异步执行MathJax渲染
                        setTimeout(function() {
                            MathJax.typesetPromise([container])
                            .then(function() {
                                console.log('✅ LaTeX渲染完成');
                            })
                            .catch(function(err) {
                                console.error('❌ LaTeX渲染错误:', err);
                            });
                        }, 100);
                        
                        console.log('🧮 LaTeX渲染已启动');
                        'math_started';
                    } else {
                        'container_not_found';
                    }
                } else if (typeof MathJax !== 'undefined' && MathJax.typeset) {
                    // 降级到传统的typeset方法
                    var container = document.getElementById('rendered-content');
                    if (container) {
                        setTimeout(function() {
                            try {
                                MathJax.typeset([container]);
                                console.log('✅ LaTeX渲染完成 (传统模式)');
                            } catch (err) {
                                console.error('❌ LaTeX渲染错误 (传统模式):', err);
                            }
                        }, 100);
                        
                        console.log('🧮 LaTeX渲染已启动 (传统模式)');
                        'math_started_legacy';
                    } else {
                        'container_not_found';
                    }
                } else {
                    console.log('⚠️ MathJax未加载或不支持渲染方法');
                    'mathjax_not_available';
                }
            } catch(e) {
                console.error('❌ LaTeX渲染启动失败:', e);
                'math_failed';
            }
        """
        
        webView.evaluateJavaScript(mathScript) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ LaTeX渲染启动失败: \(error)")
                self.finalizeRendering(withMathJax: false)
            } else if let resultString = result as? String {
                switch resultString {
                case "math_started":
                    print("✅ LaTeX渲染已启动 (Promise模式)")
                    self.finalizeRendering(withMathJax: true)
                case "math_started_legacy":
                    print("✅ LaTeX渲染已启动 (传统模式)")
                    self.finalizeRendering(withMathJax: true)
                case "container_not_found":
                    print("⚠️ 未找到内容容器，跳过LaTeX渲染")
                    self.finalizeRendering(withMathJax: false)
                case "mathjax_not_available":
                    print("⚠️ MathJax不可用，跳过LaTeX渲染")
                    self.finalizeRendering(withMathJax: false)
                case "math_failed":
                    print("❌ LaTeX渲染启动失败")
                    self.finalizeRendering(withMathJax: false)
                default:
                    print("⚠️ LaTeX渲染返回未知结果: \(resultString)")
                    self.finalizeRendering(withMathJax: false)
                }
            } else {
                print("⚠️ LaTeX渲染结果为空")
                self.finalizeRendering(withMathJax: false)
            }
        }
    }
    
    /// 最终化渲染过程
    private func finalizeRendering(withMathJax: Bool) {
        print("🎯 开始最终化渲染")
        showDetailedLoadingState(step: .finalizing, progress: 0.3, detail: "最终优化中...")
        
        // 给MathJax时间完成渲染
        let mathJaxDelay = withMathJax ? 1.0 : 0.3
        
        DispatchQueue.main.asyncAfter(deadline: .now() + mathJaxDelay) { [weak self] in
            guard let self = self, self.isProcessingAsyncOperation else { return }
            
            self.showDetailedLoadingState(step: .finalizing, progress: 0.8, detail: "优化完成！")
            
            // 再等一会儿让用户看到完成状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.isProcessingAsyncOperation else { return }
                
                print("✅ 渲染流程全部完成")
                self.hideLoadingState()
                self.isProcessingAsyncOperation = false
            }
        }
    }
    
    private func renderMarkdownInChunks() {
        guard !markdownContent.isEmpty else {
            print("⚠️ Markdown内容为空，跳过分块渲染")
            hideLoadingState()
            return
        }
        
        let contentSize = markdownContent.count
        let fileSizeText = formatFileSize(contentSize)
        print("🔄 开始智能分块渲染，文件大小: \(contentSize) 字符")
        
        showDetailedLoadingState(step: .analyzing, progress: 0.3, detail: "分析\(fileSizeText)的文档结构...")
        
        // 异步进行分块分析，避免阻塞UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 根据文件大小智能调整分块策略
            let strategy = self.getIntelligentChunkStrategy(for: contentSize)
            
            DispatchQueue.main.async { [weak self] in
                self?.showDetailedLoadingState(step: .chunking, progress: 0.1, detail: "使用\(strategy.name)策略进行智能分块...")
            }
            
            // 使用智能分块算法，保持markdown结构完整
            let chunks = self.intelligentChunkContent(self.markdownContent, strategy: strategy)
            let totalChunks = chunks.count
            
            DispatchQueue.main.async { [weak self] in
                self?.showDetailedLoadingState(step: .rendering, progress: 0.0, detail: "准备渲染\(totalChunks)个文档块...")
                
                // 初始化渲染环境
                self?.initializeChunkRendering(chunks: chunks, strategy: strategy, contentSize: contentSize)
            }
        }
    }
    
    /// 初始化分块渲染环境
    private func initializeChunkRendering(chunks: [String], strategy: IntelligentChunkStrategy, contentSize: Int) {
        let totalChunks = chunks.count
        
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
                    totalChunks: \(totalChunks),
                    renderedChunks: 0,
                    isRendering: false,
                    delayInterval: \(strategy.delayInterval)
                };
                
                console.log('✅ 智能分块渲染环境初始化完成');
                console.log('📊 文件大小: \(contentSize) 字符, 总块数: \(totalChunks), 平均块大小: ' + Math.round(\(contentSize) / \(totalChunks)) + ' 字符');
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
                self?.showDetailedLoadingState(step: .rendering, progress: 0.1, detail: "开始渲染第1个文档块...")
                self?.renderIntelligentChunk(chunks: chunks, currentIndex: 0, strategy: strategy)
            } else {
                print("❌ 分块渲染初始化失败，回退到完整渲染")
                self?.performCompleteMarkdownRender()
            }
        }
    }
    
    /// 智能分块策略结构
    private struct IntelligentChunkStrategy {
        let name: String
        let maxChunkSize: Int          // 最大块大小（字符数）
        let delayInterval: TimeInterval // 渲染间隔
        let progressMessage: String
    }
    
    /// 根据文件大小获取智能分块策略
    private func getIntelligentChunkStrategy(for contentSize: Int) -> IntelligentChunkStrategy {
        if contentSize < 10000 { // 小于10KB
            return IntelligentChunkStrategy(
                name: "快速渲染",
                maxChunkSize: 8000,
                delayInterval: 0.05,
                progressMessage: "快速渲染中..."
            )
        } else if contentSize < 50000 { // 10KB - 50KB
            return IntelligentChunkStrategy(
                name: "优化渲染",
                maxChunkSize: 5000,
                delayInterval: 0.08,
                progressMessage: "优化渲染中..."
            )
        } else if contentSize < 100000 { // 50KB - 100KB
            return IntelligentChunkStrategy(
                name: "分块渲染",
                maxChunkSize: 3000,
                delayInterval: 0.1,
                progressMessage: "分块渲染中..."
            )
        } else { // 大于100KB
            return IntelligentChunkStrategy(
                name: "深度优化渲染",
                maxChunkSize: 2000,
                delayInterval: 0.12,
                progressMessage: "深度优化渲染中..."
            )
        }
    }
    
    /// 智能分块内容，保持markdown结构完整
    private func intelligentChunkContent(_ content: String, strategy: IntelligentChunkStrategy) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentChunkSize = 0
        var i = 0
        
        print("🧠 开始智能分块，总行数: \(lines.count)，最大块大小: \(strategy.maxChunkSize) 字符")
        
        while i < lines.count {
            let line = lines[i]
            let lineLength = line.count + 1 // +1 for newline
            
            // 检查是否遇到需要保持完整的markdown结构
            if let blockEnd = detectMarkdownBlock(lines: lines, startIndex: i) {
                // 发现完整的markdown块
                let blockLines = Array(lines[i...blockEnd])
                let blockContent = blockLines.joined(separator: "\n")
                let blockSize = blockContent.count
                
                print("📦 发现markdown结构块: \(blockLines.first?.prefix(50) ?? "")... (行\(i+1)-\(blockEnd+1), \(blockSize)字符)")
                
                // 如果当前块加上这个结构块会超过限制，先保存当前块
                if !currentChunk.isEmpty && currentChunkSize + blockSize > strategy.maxChunkSize {
                    // 在保存当前块前，检查并扩展到完整结构
                    let extendedChunk = extendChunkToCompleteStructure(
                        currentChunk: currentChunk, 
                        allLines: lines, 
                        chunkEndIndex: i - 1,
                        strategy: strategy
                    )
                    
                    chunks.append(extendedChunk.content)
                    print("💾 保存扩展块 \(chunks.count): \(extendedChunk.content.count) 字符 (扩展了\(extendedChunk.extensionSize)字符)")
                    currentChunk = []
                    currentChunkSize = 0
                }
                
                // 将整个结构块添加到当前块
                currentChunk.append(contentsOf: blockLines)
                currentChunkSize += blockSize
                
                // 如果结构块本身就很大，立即保存为独立块
                if blockSize > strategy.maxChunkSize / 2 {
                    let chunkContent = currentChunk.joined(separator: "\n")
                    chunks.append(chunkContent)
                    print("💾 保存大结构块 \(chunks.count): \(currentChunkSize) 字符")
                    currentChunk = []
                    currentChunkSize = 0
                }
                
                i = blockEnd + 1
                continue
            }
            
            // 普通行处理
            if currentChunkSize + lineLength > strategy.maxChunkSize && !currentChunk.isEmpty {
                // 当前块已满，但在切分前检查是否需要扩展到完整结构
                let extendedChunk = extendChunkToCompleteStructure(
                    currentChunk: currentChunk,
                    allLines: lines,
                    chunkEndIndex: i - 1,
                    strategy: strategy
                )
                
                chunks.append(extendedChunk.content)
                print("💾 保存智能扩展块 \(chunks.count): \(extendedChunk.content.count) 字符 (扩展了\(extendedChunk.extensionSize)字符)")
                currentChunk = []
                currentChunkSize = 0
            }
            
            currentChunk.append(line)
            currentChunkSize += lineLength
            i += 1
        }
        
        // 保存最后一个块（也需要检查扩展）
        if !currentChunk.isEmpty {
            let extendedChunk = extendChunkToCompleteStructure(
                currentChunk: currentChunk,
                allLines: lines,
                chunkEndIndex: lines.count - 1,
                strategy: strategy
            )
            
            chunks.append(extendedChunk.content)
            print("💾 保存最后块 \(chunks.count): \(extendedChunk.content.count) 字符 (扩展了\(extendedChunk.extensionSize)字符)")
        }
        
        print("🧠 智能分块完成，共 \(chunks.count) 个块")
        return chunks.isEmpty ? [content] : chunks
    }
    
    /// 扩展块到完整结构的结果
    private struct ChunkExtensionResult {
        let content: String
        let extensionSize: Int
    }
    
    /// 将块扩展到完整的markdown结构
    private func extendChunkToCompleteStructure(
        currentChunk: [String],
        allLines: [String],
        chunkEndIndex: Int,
        strategy: IntelligentChunkStrategy
    ) -> ChunkExtensionResult {
        
        let originalContent = currentChunk.joined(separator: "\n")
        let originalSize = originalContent.count
        
        // 检查块结尾是否处于不完整的结构中
        let structureExtension = detectIncompleteStructureAtEnd(
            chunkLines: currentChunk,
            allLines: allLines,
            chunkEndIndex: chunkEndIndex,
            maxExtensionSize: strategy.maxChunkSize / 4 // 最多扩展25%
        )
        
        if structureExtension.shouldExtend {
            let extendedLines = currentChunk + structureExtension.extensionLines
            let extendedContent = extendedLines.joined(separator: "\n")
            let extensionSize = extendedContent.count - originalSize
            
            print("🔧 结构扩展: \(structureExtension.reason) +\(structureExtension.extensionLines.count)行")
            
            return ChunkExtensionResult(
                content: extendedContent,
                extensionSize: extensionSize
            )
        }
        
        return ChunkExtensionResult(
            content: originalContent,
            extensionSize: 0
        )
    }
    
    /// 结构扩展信息
    private struct StructureExtension {
        let shouldExtend: Bool
        let extensionLines: [String]
        let reason: String
    }
    
    /// 检测块末尾的不完整结构
    private func detectIncompleteStructureAtEnd(
        chunkLines: [String],
        allLines: [String],
        chunkEndIndex: Int,
        maxExtensionSize: Int
    ) -> StructureExtension {
        
        guard chunkEndIndex < allLines.count - 1 else {
            return StructureExtension(shouldExtend: false, extensionLines: [], reason: "已到文件末尾")
        }
        
        // 1. 检查是否在代码块中间
        if let codeBlockExtension = detectIncompleteCodeBlock(
            chunkLines: chunkLines,
            allLines: allLines,
            chunkEndIndex: chunkEndIndex,
            maxExtensionSize: maxExtensionSize
        ) {
            return codeBlockExtension
        }
        
        // 2. 检查是否在表格中间  
        if let tableExtension = detectIncompleteTable(
            chunkLines: chunkLines,
            allLines: allLines,
            chunkEndIndex: chunkEndIndex,
            maxExtensionSize: maxExtensionSize
        ) {
            return tableExtension
        }
        
        // 3. 检查是否在列表中间
        if let listExtension = detectIncompleteList(
            chunkLines: chunkLines,
            allLines: allLines,
            chunkEndIndex: chunkEndIndex,
            maxExtensionSize: maxExtensionSize
        ) {
            return listExtension
        }
        
        // 4. 检查是否在HTML块中间
        if let htmlExtension = detectIncompleteHTMLBlock(
            chunkLines: chunkLines,
            allLines: allLines,
            chunkEndIndex: chunkEndIndex,
            maxExtensionSize: maxExtensionSize
        ) {
            return htmlExtension
        }
        
        // 5. 检查是否在引用块中间
        if let quoteExtension = detectIncompleteQuoteBlock(
            chunkLines: chunkLines,
            allLines: allLines,
            chunkEndIndex: chunkEndIndex,
            maxExtensionSize: maxExtensionSize
        ) {
            return quoteExtension
        }
        
        return StructureExtension(shouldExtend: false, extensionLines: [], reason: "无需扩展")
    }
    
    /// 检测不完整的代码块
    private func detectIncompleteCodeBlock(
        chunkLines: [String],
        allLines: [String],
        chunkEndIndex: Int,
        maxExtensionSize: Int
    ) -> StructureExtension? {
        
        // 检查块内是否有未闭合的代码块
        var codeBlockStartCount = 0
        var codeBlockEndCount = 0
        
        for line in chunkLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if codeBlockStartCount == codeBlockEndCount {
                    codeBlockStartCount += 1
                } else {
                    codeBlockEndCount += 1
                }
            }
        }
        
        // 如果有未闭合的代码块，查找结束标记
        if codeBlockStartCount > codeBlockEndCount {
            var extensionLines: [String] = []
            var extensionSize = 0
            
            for i in (chunkEndIndex + 1)..<allLines.count {
                let line = allLines[i]
                extensionLines.append(line)
                extensionSize += line.count + 1
                
                if extensionSize > maxExtensionSize {
                    break
                }
                
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    return StructureExtension(
                        shouldExtend: true,
                        extensionLines: extensionLines,
                        reason: "代码块未闭合"
                    )
                }
            }
        }
        
        return nil
    }
    
    /// 检测不完整的表格
    private func detectIncompleteTable(
        chunkLines: [String],
        allLines: [String],
        chunkEndIndex: Int,
        maxExtensionSize: Int
    ) -> StructureExtension? {
        
        // 检查最后几行是否是表格
        let lastFewLines = Array(chunkLines.suffix(3))
        var isInTable = false
        
        for line in lastFewLines {
            if isTableRow(line) {
                isInTable = true
                break
            }
        }
        
        if isInTable {
            var extensionLines: [String] = []
            var extensionSize = 0
            
            // 继续包含表格的剩余行
            for i in (chunkEndIndex + 1)..<allLines.count {
                let line = allLines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // 如果不再是表格行且不是空行，停止扩展
                if !trimmed.isEmpty && !isTableRow(line) {
                    break
                }
                
                extensionLines.append(line)
                extensionSize += line.count + 1
                
                if extensionSize > maxExtensionSize {
                    break
                }
                
                // 如果遇到非空非表格行，表格结束
                if !trimmed.isEmpty && !isTableRow(line) {
                    break
                }
            }
            
            if !extensionLines.isEmpty {
                return StructureExtension(
                    shouldExtend: true,
                    extensionLines: extensionLines,
                    reason: "表格未完整"
                )
            }
        }
        
        return nil
    }
    
    /// 检测不完整的列表
    private func detectIncompleteList(
        chunkLines: [String],
        allLines: [String],
        chunkEndIndex: Int,
        maxExtensionSize: Int
    ) -> StructureExtension? {
        
        // 检查最后几行是否是列表
        guard let lastLine = chunkLines.last else { return nil }
        
        if isListItem(lastLine) || (lastLine.trimmingCharacters(in: .whitespaces).isEmpty && 
                                    chunkLines.dropLast().last.map(isListItem) == true) {
            
            let lastListIndent = getListIndent(lastLine)
            var extensionLines: [String] = []
            var extensionSize = 0
            
            // 继续包含列表的剩余项
            for i in (chunkEndIndex + 1)..<allLines.count {
                let line = allLines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // 空行继续
                if trimmed.isEmpty {
                    extensionLines.append(line)
                    extensionSize += line.count + 1
                    continue
                }
                
                // 如果仍然是列表项或有更深的缩进（列表内容），继续
                if isListItem(trimmed) || getListIndent(line) > lastListIndent {
                    extensionLines.append(line)
                    extensionSize += line.count + 1
                    
                    if extensionSize > maxExtensionSize {
                        break
                    }
                } else {
                    // 列表结束
                    break
                }
            }
            
            if !extensionLines.isEmpty {
                return StructureExtension(
                    shouldExtend: true,
                    extensionLines: extensionLines,
                    reason: "列表未完整"
                )
            }
        }
        
        return nil
    }
    
    /// 检测不完整的HTML块
    private func detectIncompleteHTMLBlock(
        chunkLines: [String],
        allLines: [String],
        chunkEndIndex: Int,
        maxExtensionSize: Int
    ) -> StructureExtension? {
        
        // 检查最后几行是否有未闭合的HTML标签
        var openTags: [String] = []
        
        for line in chunkLines.suffix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<") && trimmed.contains(">") {
                if let tagName = extractHTMLTagName(line) {
                    if trimmed.contains("</\(tagName)>") {
                        // 自闭合或同行闭合
                        continue
                    } else if !trimmed.hasSuffix("/>") {
                        // 开放标签
                        openTags.append(tagName)
                    }
                }
            }
        }
        
        if !openTags.isEmpty {
            var extensionLines: [String] = []
            var extensionSize = 0
            var tagsToClose = openTags
            
            for i in (chunkEndIndex + 1)..<allLines.count {
                let line = allLines[i]
                extensionLines.append(line)
                extensionSize += line.count + 1
                
                if extensionSize > maxExtensionSize {
                    break
                }
                
                // 检查是否包含闭合标签
                for (index, tagName) in tagsToClose.enumerated().reversed() {
                    if line.contains("</\(tagName)>") {
                        tagsToClose.remove(at: index)
                    }
                }
                
                // 如果所有标签都闭合了，停止扩展
                if tagsToClose.isEmpty {
                    return StructureExtension(
                        shouldExtend: true,
                        extensionLines: extensionLines,
                        reason: "HTML标签未闭合"
                    )
                }
            }
        }
        
        return nil
    }
    
    /// 检测不完整的引用块
    private func detectIncompleteQuoteBlock(
        chunkLines: [String],
        allLines: [String],
        chunkEndIndex: Int,
        maxExtensionSize: Int
    ) -> StructureExtension? {
        
        // 检查最后几行是否是引用块
        guard let lastLine = chunkLines.last else { return nil }
        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix(">") || (trimmed.isEmpty && 
                                     chunkLines.dropLast().last?.trimmingCharacters(in: .whitespaces).hasPrefix(">") == true) {
            
            var extensionLines: [String] = []
            var extensionSize = 0
            
            // 继续包含引用块的剩余内容
            for i in (chunkEndIndex + 1)..<allLines.count {
                let line = allLines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // 空行或继续的引用行
                if trimmed.isEmpty || trimmed.hasPrefix(">") {
                    extensionLines.append(line)
                    extensionSize += line.count + 1
                    
                    if extensionSize > maxExtensionSize {
                        break
                    }
                } else {
                    // 引用块结束
                    break
                }
            }
            
            if !extensionLines.isEmpty {
                return StructureExtension(
                    shouldExtend: true,
                    extensionLines: extensionLines,
                    reason: "引用块未完整"
                )
            }
        }
        
        return nil
    }
    
    /// 检测markdown结构块，返回结束行索引
    private func detectMarkdownBlock(lines: [String], startIndex: Int) -> Int? {
        guard startIndex < lines.count else { return nil }
        
        let line = lines[startIndex].trimmingCharacters(in: .whitespaces)
        
        // 1. 检测代码块 (```)
        if line.hasPrefix("```") {
            // 查找代码块结束
            for i in (startIndex + 1)..<lines.count {
                let endLine = lines[i].trimmingCharacters(in: .whitespaces)
                if endLine.hasPrefix("```") {
                    print("🔍 发现代码块: 行\(startIndex+1)-\(i+1)")
                    return i
                }
            }
            // 如果没找到结束标记，将剩余内容作为一个块
            return lines.count - 1
        }
        
        // 2. 检测表格
        if line.contains("|") && isTableRow(line) {
            // 查找表格结束
            var endIndex = startIndex
            for i in (startIndex + 1)..<lines.count {
                let tableLine = lines[i].trimmingCharacters(in: .whitespaces)
                if tableLine.isEmpty || !tableLine.contains("|") || !isTableRow(tableLine) {
                    break
                }
                endIndex = i
            }
            if endIndex > startIndex {
                print("🔍 发现表格: 行\(startIndex+1)-\(endIndex+1)")
                return endIndex
            }
        }
        
        // 3. 检测标题后的内容块
        if line.hasPrefix("#") {
            // 查找下一个同级或更高级标题
            let currentLevel = line.prefix(while: { $0 == "#" }).count
            for i in (startIndex + 1)..<lines.count {
                let nextLine = lines[i].trimmingCharacters(in: .whitespaces)
                if nextLine.hasPrefix("#") {
                    let nextLevel = nextLine.prefix(while: { $0 == "#" }).count
                    if nextLevel <= currentLevel {
                        print("🔍 发现标题块: 行\(startIndex+1)-\(i)")
                        return i - 1
                    }
                }
            }
        }
        
        // 4. 检测列表块
        if isListItem(line) {
            var endIndex = startIndex
            let listIndent = getListIndent(line)
            
            for i in (startIndex + 1)..<lines.count {
                let listLine = lines[i]
                let trimmedLine = listLine.trimmingCharacters(in: .whitespaces)
                
                // 空行继续
                if trimmedLine.isEmpty {
                    endIndex = i
                    continue
                }
                
                // 仍然是列表项或缩进内容
                if isListItem(trimmedLine) || getListIndent(listLine) > listIndent {
                    endIndex = i
                } else {
                    break
                }
            }
            
            if endIndex > startIndex {
                print("🔍 发现列表块: 行\(startIndex+1)-\(endIndex+1)")
                return endIndex
            }
        }
        
        // 5. 检测HTML块
        if line.hasPrefix("<") && line.contains(">") {
            // 简单的HTML块检测
            if line.contains("</") || line.hasSuffix("/>") {
                // 单行HTML
                return startIndex
            } else {
                // 查找匹配的结束标签
                if let tagName = extractHTMLTagName(line) {
                    for i in (startIndex + 1)..<lines.count {
                        let htmlLine = lines[i]
                        if htmlLine.contains("</\(tagName)>") {
                            print("🔍 发现HTML块: 行\(startIndex+1)-\(i+1)")
                            return i
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// 判断是否为表格行
    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.hasPrefix("|") && 
               (trimmed.components(separatedBy: "|").count > 2 || trimmed.contains("---"))
    }
    
    /// 判断是否为列表项
    private func isListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || 
               trimmed.hasPrefix("+ ") || 
               trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil
    }
    
    /// 获取列表缩进级别
    private func getListIndent(_ line: String) -> Int {
        return line.count - line.trimmingCharacters(in: .whitespaces).count
    }
    
    /// 提取HTML标签名
    private func extractHTMLTagName(_ line: String) -> String? {
        let pattern = "<([a-zA-Z][a-zA-Z0-9]*)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            return String(line[range])
        }
        return nil
    }
    
    private func renderIntelligentChunk(chunks: [String], currentIndex: Int, strategy: IntelligentChunkStrategy) {
        guard currentIndex < chunks.count else {
            print("✅ 所有智能分块渲染完成")
            finalizeChunkRendering()
            return
        }
        
        let chunkContent = chunks[currentIndex]
        let chunkNumber = currentIndex + 1
        let totalChunks = chunks.count
        
        // 更新详细进度
        let renderingProgress = Double(currentIndex) / Double(totalChunks)
        let detailText = if chunkContent.count > 1000 {
            "渲染第\(chunkNumber)块 (共\(totalChunks)块) - \(formatFileSize(chunkContent.count))"
        } else {
            "渲染第\(chunkNumber)块 (共\(totalChunks)块) - \(chunkContent.count) 字符"
        }
        showDetailedLoadingState(step: .rendering, progress: renderingProgress, detail: detailText)
        
        print("📄 渲染第\(chunkNumber)块 (共\(totalChunks)块, \(chunkContent.count)字符)")
        
        let escapedContent = escapeForJavaScript(chunkContent)
        
        let renderScript = """
            try {
                console.log('🔧 准备调用renderMarkdown函数');
                if (typeof window.renderMarkdown === 'function') {
                    window.renderMarkdown('\(escapedContent)');
                    console.log('✅ renderMarkdown调用成功');
                    'render_success';
                } else {
                    console.error('❌ renderMarkdown函数不存在');
                    'render_function_missing';
                }
            } catch(e) {
                console.error('❌ renderMarkdown调用失败:', e);
                'render_failed';
            }
        """
        
        webView.evaluateJavaScript(renderScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ renderMarkdown调用失败: \(error)")
                self?.showError(message: "渲染失败: \(error.localizedDescription)")
                return
            }
            
            if let resultString = result as? String {
                switch resultString {
                case "render_success":
                    print("✅ renderMarkdown调用成功")
                    // 延迟隐藏加载状态，给渲染时间
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self, self.isProcessingAsyncOperation else { return }
                        self.hideLoadingState()
                        self.isProcessingAsyncOperation = false
                    }
                case "render_function_missing":
                    print("❌ renderMarkdown函数不存在")
                    self?.showError(message: "渲染函数不存在，请检查HTML模板")
                case "render_failed":
                    print("❌ renderMarkdown调用失败")
                    self?.showError(message: "渲染调用失败")
                default:
                    print("⚠️ 未知的渲染结果: \(resultString)")
                    self?.showError(message: "渲染过程异常")
                }
            } else {
                print("⚠️ 渲染结果为空或类型错误")
                self?.showError(message: "渲染结果异常")
            }
        }
    }
    
    private func finalizeChunkRendering() {
        print("🎨 完成分块渲染，开始后处理...")
        showDetailedLoadingState(step: .enhancing, progress: 0.0, detail: "处理LaTeX公式、Mermaid图表等...")
        
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
            
            self?.showDetailedLoadingState(step: .enhancing, progress: 0.7, detail: "渲染LaTeX数学公式...")
            
            // 延迟渲染LaTeX公式
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.renderMathJax()
            }
        }
    }
    
    private func renderMathJax() {
        print("🧮 开始渲染LaTeX公式")
        
        let mathScript = """
            try {
                if (typeof MathJax !== 'undefined' && MathJax.typesetPromise) {
                    var container = document.getElementById('rendered-content');
                    if (container) {
                        // 异步执行MathJax渲染，避免返回Promise对象
                        setTimeout(function() {
                            MathJax.typesetPromise([container])
                            .then(function() {
                                console.log('✅ LaTeX渲染完成');
                            })
                            .catch(function(err) {
                                console.error('❌ LaTeX渲染错误:', err);
                            });
                        }, 100);
                        
                        console.log('🧮 LaTeX渲染已启动');
                        'math_started';
                    } else {
                        console.warn('⚠️ 未找到内容容器');
                        'container_not_found';
                    }
                } else if (typeof MathJax !== 'undefined' && MathJax.typeset) {
                    // 降级到传统的typeset方法
                    var container = document.getElementById('rendered-content');
                    if (container) {
                        setTimeout(function() {
                            try {
                                MathJax.typeset([container]);
                                console.log('✅ LaTeX渲染完成 (传统模式)');
                            } catch (err) {
                                console.error('❌ LaTeX渲染错误 (传统模式):', err);
                            }
                        }, 100);
                        
                        console.log('🧮 LaTeX渲染已启动 (传统模式)');
                        'math_started_legacy';
                    } else {
                        'container_not_found';
                    }
                } else {
                    console.warn('⚠️ MathJax未加载或不支持渲染方法');
                    'mathjax_not_available';
                }
            } catch(e) {
                console.error('❌ LaTeX渲染启动失败:', e);
                'math_failed';
            }
        """
        
        webView.evaluateJavaScript(mathScript) { [weak self] (result, error) in
            if let error = error {
                print("❌ LaTeX渲染启动失败: \(error)")
            } else if let resultString = result as? String {
                switch resultString {
                case "math_started":
                    print("✅ LaTeX渲染已启动 (Promise模式)")
                    self?.showDetailedLoadingState(step: .finalizing, progress: 0.3, detail: "LaTeX公式渲染中...")
                case "math_started_legacy":
                    print("✅ LaTeX渲染已启动 (传统模式)")
                    self?.showDetailedLoadingState(step: .finalizing, progress: 0.3, detail: "LaTeX公式渲染中(兼容模式)...")
                case "container_not_found":
                    print("⚠️ 未找到内容容器，LaTeX渲染跳过")
                    self?.showDetailedLoadingState(step: .finalizing, progress: 0.7, detail: "跳过LaTeX渲染，优化显示...")
                case "mathjax_not_available":
                    print("⚠️ MathJax不可用，LaTeX渲染跳过")
                    self?.showDetailedLoadingState(step: .finalizing, progress: 0.7, detail: "LaTeX不可用，优化显示...")
                case "math_failed":
                    print("❌ LaTeX渲染启动失败")
                    self?.showDetailedLoadingState(step: .finalizing, progress: 0.7, detail: "LaTeX渲染失败，优化显示...")
                default:
                    print("⚠️ LaTeX渲染返回未知结果: \(resultString)")
                }
            }
            
            // 延迟完成加载，确保所有处理都完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self, self.isProcessingAsyncOperation else { return }
                self.showDetailedLoadingState(step: .finalizing, progress: 0.9, detail: "最终优化中...")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self, self.isProcessingAsyncOperation else { return }
                    self.showDetailedLoadingState(step: .finalizing, progress: 1.0, detail: "渲染完成！")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self, self.isProcessingAsyncOperation else { return }
                        self.hideLoadingState()
                        self.isProcessingAsyncOperation = false // 重置异步操作标志
                    }
                }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        guard let self = self, self.isProcessingAsyncOperation else { return }
                        self.hideLoadingState()
                        self.isProcessingAsyncOperation = false // 重置异步操作标志
                    }
                } else {
                    print("❌ 渲染启动失败")
                    self?.showError(message: "渲染启动失败")
                }
            }
        }
    }
    
    // MARK: - 状态管理（已迁移到详细加载状态系统）
    
    // MARK: - 错误处理
    private func showError(message: String) {
        // 确保在主线程执行UI操作
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 重置所有状态到安全状态
            self.hideLoadingState()
            self.isProcessingAsyncOperation = false
            self.isTemplateLoading = false
            
            // 显示错误界面
            self.errorView.isHidden = false
            self.webView.isHidden = true
            
            // 更新错误消息
            if let messageLabel = self.errorView.subviews.first?.subviews.compactMap({ $0 as? UIStackView }).first?.arrangedSubviews[2] as? UILabel {
                messageLabel.text = message
            }
            
            print("❌ 显示错误信息: \(message)")
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
        
        // 保存当前内容作为待渲染内容
        if !markdownContent.isEmpty {
            pendingMarkdownContent = markdownContent
            print("📄 保存当前Markdown内容(\(markdownContent.count)字符)，等待HTML模板重新加载")
        }
        
        // 重置所有状态标志
        isHTMLTemplateLoaded = false
        isTemplateLoading = false
        isProcessingAsyncOperation = false
        retryCount = 0
        themeInitRetryCount = 0
        needsRefreshAfterPermission = false
        
        // 停止当前加载
        webView.stopLoading()
        
        resetLoadingState()
        showDetailedLoadingState(step: .initializing, progress: 0.0, detail: "正在重新初始化...")
        
        // 延迟一点时间再加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.loadHTMLTemplate()
        }
    }
    
    // MARK: - 主题管理事件
    private func themeDidChange() {
        let theme = ThemeManager.shared.getCurrentTheme()
        
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self, self.isHTMLTemplateLoaded else { return }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self = self, self.isHTMLTemplateLoaded else { return }
                        self.syncInitialThemeToWebView()
                    }
                }
            }
        }
    }
    
    // MARK: - 工具方法
    /// 验证应用状态是否正常
    private func validateAppState() -> Bool {
        // 检查视图状态
        guard view.window != nil else {
            print("❌ 视图未添加到窗口")
            return false
        }
        
        // 检查WebView状态
        guard webView.superview != nil else {
            print("❌ WebView未添加到视图层次")
            return false
        }
        
        // 检查内存状态
        let memoryWarning = ProcessInfo.processInfo.thermalState == .critical
        if memoryWarning {
            print("⚠️ 系统内存警告")
        }
        
        return true
    }
    
    /// 安全的JavaScript字符串转义 - 处理边界情况
    private func escapeForJavaScript(_ string: String) -> String {
        // 边界检查：空字符串处理
        guard !string.isEmpty else {
            return ""
        }
        
        // 边界检查：过长字符串警告
        if string.count > 1_000_000 {
            print("⚠️ 转义字符串过长(\(formatFileSize(string.count)))，可能影响性能")
        }
        
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028") // Line separator
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029") // Paragraph separator
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
        
        showDetailedLoadingState(step: .loadingTemplate, progress: 0.9, detail: "HTML模板和JavaScript引擎加载完成")
        
        // 简化WebView优化
        hideWKBackdropView(in: webView)
        
        // 简化DOM验证 - 直接执行，不重试
        verifyDOMAndRender()
    }
    
    /// 简化的DOM验证和渲染
    private func verifyDOMAndRender() {
        // 边界检查：确保WebView可用
        guard !webView.isLoading else {
            print("⚠️ WebView仍在加载中，延迟DOM验证")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.verifyDOMAndRender()
            }
            return
        }
        
        print("🔍 验证DOM就绪状态")
        
        // 简化的DOM验证脚本
        let domScript = """
            (function() {
                try {
                    var element = document.getElementById('rendered-content');
                    var hasRenderFunction = typeof window.renderMarkdown === 'function';
                    return element !== null && hasRenderFunction;
                } catch(e) {
                    return false;
                }
            })();
        """
        
        webView.evaluateJavaScript(domScript) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ DOM验证脚本执行错误: \(error)")
                // 延迟重试，最多重试3次
                if self.retryCount < 3 {
                    self.retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.verifyDOMAndRender()
                    }
                } else {
                    print("❌ DOM验证重试次数已达上限")
                    self.showError(message: "渲染环境初始化失败\n请尝试刷新页面")
                }
                return
            }
            
            if let isReady = result as? Bool, isReady {
                print("✅ DOM验证成功")
                
                // 重置重试计数
                self.retryCount = 0
                
                // 同步主题
                self.syncInitialThemeToWebView()
                
                // 开始渲染
                if let pendingContent = self.pendingMarkdownContent, !pendingContent.isEmpty {
                    print("📄 发现待渲染内容，开始渲染")
                    self.markdownContent = pendingContent
                    self.pendingMarkdownContent = nil
                    self.renderMarkdownContent()
                } else if !self.markdownContent.isEmpty {
                    print("📄 渲染当前Markdown内容")
                    self.renderMarkdownContent()
                } else {
                    print("📄 无内容需要渲染")
                    self.hideLoadingState()
                }
            } else {
                print("❌ DOM验证失败，延迟重试")
                // 限制重试次数，防止无限循环
                if self.retryCount < 3 {
                    self.retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.verifyDOMAndRender()
                    }
                } else {
                    print("❌ DOM验证重试次数已达上限")
                    self.showError(message: "渲染环境初始化失败\n请尝试刷新页面")
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView加载失败: \(error.localizedDescription)")
        print("❌ 错误详情: \(error)")
        
        // 重置加载状态
        isHTMLTemplateLoaded = false
        isTemplateLoading = false
        isProcessingAsyncOperation = false
        
        // 分析错误类型并提供相应的解决方案
        handleWebViewLoadError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView预加载失败: \(error.localizedDescription)")
        print("❌ 错误详情: \(error)")
        
        // 重置加载状态
        isHTMLTemplateLoaded = false
        isTemplateLoading = false
        isProcessingAsyncOperation = false
        
        // 分析错误类型并提供相应的解决方案
        handleWebViewLoadError(error)
    }
    
    /// 简化的WebView加载错误处理
    private func handleWebViewLoadError(_ error: Error) {
        let errorCode = (error as NSError).code
        
        print("❌ WebView加载失败: \(error.localizedDescription)")
        
        // 增加重试计数
        retryCount += 1
        
        // 简化的重试逻辑：只对-999错误和沙盒错误重试
        let shouldRetry = (errorCode == NSURLErrorCancelled || 
                          error.localizedDescription.contains("sandbox") ||
                          error.localizedDescription.contains("extension")) && 
                          retryCount <= 3
        
        if shouldRetry {
            print("🔄 自动重试第\(retryCount)次...")
            
            let retryDelay = TimeInterval(retryCount) * 1.0 + 1.0
            
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                self?.loadHTMLTemplateIfNeeded()
            }
            
            showDetailedLoadingState(
                step: .loadingTemplate,
                progress: 0.1,
                detail: "正在重试第\(retryCount)次..."
            )
        } else {
            // 显示错误
            let errorMessage = "加载失败: \(error.localizedDescription)\n请重试"
            showError(message: errorMessage)
        }
    }
}

// MARK: - WKScriptMessageHandler
extension MarkdownReaderViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // 处理来自JavaScript的原生print消息
        if message.name == "nativePrint" {
            let logMessage: String
            
            if let messageBody = message.body as? String {
                logMessage = messageBody
            } else if let messageDict = message.body as? [String: Any] {
                // 如果是对象，转换为JSON字符串
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [.prettyPrinted])
                    logMessage = String(data: jsonData, encoding: .utf8) ?? "无法解析的对象"
                } catch {
                    logMessage = "JSON解析失败: \(error.localizedDescription)"
                }
            } else {
                logMessage = "JS消息: \(message.body)"
            }
            
            // 使用原生Swift print函数输出到Xcode控制台
            print("📱 [JavaScript] \(logMessage)")
        }
    }
}

