//
//  MarkdownReaderViewController.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
// 

import UIKit
import WebKit
import SnapKit 

/// Markdown阅读器控制器 - 高性能优化版
class MarkdownReaderViewController: UIViewController {
    
    // MARK: - Properties
    var markdownFile: MarkdownFile? {
        didSet {
            updateTitle()
            // 重置加载状态，准备加载新内容
            isContentLoaded = false
            // 不在这里立即加载内容，等待HTML模板加载完成
        }
    }
    
    // HTML模板是否已加载完成
    private var isHTMLTemplateReady = false
    
    // 内容是否已加载完成，避免重复加载
    private var isContentLoaded = false
    
    // MARK: - Services
    private let renderingService = MarkdownRenderingService()
    private let cacheService = MarkdownCacheService.shared
    
    // MARK: - UI Components
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        
        // 允许JavaScript执行 - 兼容不同iOS版本
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            config.preferences.javaScriptEnabled = true
        }
        
        // 允许内联媒体播放
        config.allowsInlineMediaPlayback = true
        
        // 添加消息处理器
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "nativePrint")
        config.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.backgroundColor = .systemBackground
        
        // 初始透明状态，避免闪动
        webView.alpha = 0.0
        
        return webView
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .systemBlue
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private lazy var loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "正在加载文档..."
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()
    
    private lazy var errorView: UIView = createErrorView()
    
    // 悬浮目录按钮
    private lazy var floatingTOCButton: UIButton = createFloatingTOCButton()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupRenderingService()
        setupThemeManager()
        setupGestureSupport()
        loadHTMLTemplate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // 确保导航栏颜色正确
        navigationController?.navigationBar.tintColor = .systemOrange
        
        // 清理过期缓存
        cacheService.cleanExpiredCache()
        

        

    }
    
    deinit {
        // 移除主题变化监听
        NotificationCenter.default.removeObserver(self, name: ThemeManager.themeDidChangeNotification, object: nil)
    }
    
    // MARK: - Setup Methods
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 添加子视图
        view.addSubview(webView)
        view.addSubview(loadingIndicator)
        view.addSubview(loadingLabel)
        view.addSubview(errorView)
        view.addSubview(floatingTOCButton)
        
        // 设置约束 - 使用SnapKit
        
        // WebView约束
        webView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        
        // Loading indicator约束
        loadingIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-8)
        }
        
        // Loading label约束 - 紧凑布局
        loadingLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(loadingIndicator.snp.bottom).offset(12)
        }
        
        // Error view约束
        errorView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        
        // 悬浮目录按钮约束 - 左上角位置
        floatingTOCButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.size.equalTo(44)
        }
        
        // 设置导航栏
        setupNavigationBar()
    }
    
    private func setupNavigationBar() {
        // 设置导航栏返回按钮颜色
        navigationController?.navigationBar.tintColor = .systemOrange
        
        updateNavigationBarButtons()
    }
    
    private func updateNavigationBarButtons() {
        // 使用统一的按钮风格创建右上角按钮组
        let refreshButton = UIBarButtonItem.createStandardButton(
            systemName: "arrow.clockwise",
            target: self,
            action: #selector(refreshContent)
        )
        
        let shareButton = UIBarButtonItem.createStandardButton(
            systemName: "square.and.arrow.up",
            target: self,
            action: #selector(shareContent)
        )
        
        // 主题切换按钮
        let themeButton = ThemeManager.shared.createThemeToggleButton()
        
        navigationItem.rightBarButtonItems = [themeButton, shareButton, refreshButton]
    }
    
    private func showTableOfContentsButtonIfNeeded() {
        print("🔍 开始检测目录...")
        
        // 增强的检测脚本，提供更多调试信息
        let script = """
            (function() {
                console.log('🔍 开始目录检测脚本...');
                
                const container = document.getElementById('rendered-content');
                if (!container) {
                    console.log('❌ 未找到 rendered-content 容器');
                    return { hasHeaders: false, error: 'container_not_found' };
                }
                
                console.log('✅ 找到 rendered-content 容器');
                const headers = container.querySelectorAll('h1, h2, h3, h4, h5, h6');
                console.log('📊 检测到标题数量:', headers.length);
                
                if (headers.length > 0) {
                    headers.forEach((header, index) => {
                        console.log('📝 标题 ' + (index + 1) + ':', header.tagName, '-', header.textContent);
                    });
                }
                
                return { hasHeaders: headers.length > 0, count: headers.length };
            })();
        """
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 目录检测脚本执行失败: \(error)")
                    self?.updateFloatingTOCButton(hasHeaders: false)
                    return
                }
                
                if let resultDict = result as? [String: Any],
                   let hasHeaders = resultDict["hasHeaders"] as? Bool,
                   let count = resultDict["count"] as? Int {
                    self?.updateFloatingTOCButton(hasHeaders: hasHeaders)
                } else {
                    self?.updateFloatingTOCButton(hasHeaders: false)
                }
            }
        }
    }
    
    private func updateFloatingTOCButton(hasHeaders: Bool) {
        // 总是显示按钮，但透明度不同
        floatingTOCButton.isHidden = false
        
        if hasHeaders {
            // 使用目录图标
            floatingTOCButton.setImage(UIImage(systemName: "list.bullet"), for: .normal)
            
            // 渐入到完全不透明
            UIView.animate(withDuration: 0.3, delay: 0.2, options: .curveEaseOut) {
                self.floatingTOCButton.alpha = 1.0
            }
        } else {
            // 使用缩进目录图标表示无内容状态
            floatingTOCButton.setImage(UIImage(systemName: "list.bullet.indent"), for: .normal)
            
            // 显示为半透明状态
            UIView.animate(withDuration: 0.3) {
                self.floatingTOCButton.alpha = 0.5
            }
        }
    }
    

    

    

    
    private func setupRenderingService() {
        renderingService.stateChangeHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleRenderingStateChange(state)
            }
        }
    }
    
    private func setupThemeManager() {
        // 设置WebView引用
        ThemeManager.shared.setWebView(webView)
        
        // 监听主题变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange(_:)),
            name: ThemeManager.themeDidChangeNotification,
            object: nil
        )
        
        print("MarkdownReaderViewController 主题管理器已设置")
    }
    
    private func setupGestureSupport() {
        // 确保导航控制器的交互式弹出手势正常工作
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        
        // 确保WebView不会阻止边缘手势
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        
        print("MarkdownReaderViewController 手势支持已配置")
    }
    
    private func createErrorView() -> UIView {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.isHidden = true
        
        let imageView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        
        let titleLabel = UILabel()
        titleLabel.text = "加载失败"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        
        let messageLabel = UILabel()
        messageLabel.text = "无法加载Markdown文件内容"
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        
        let retryButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "重新加载"
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        retryButton.configuration = config
        retryButton.addTarget(self, action: #selector(refreshContent), for: .touchUpInside)
        
        let stackView = UIStackView(arrangedSubviews: [imageView, titleLabel, messageLabel, retryButton])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        
        view.addSubview(stackView)
        
        // 使用SnapKit设置约束
        stackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(32)
            make.trailing.lessThanOrEqualToSuperview().offset(-32)
        }
        
        imageView.snp.makeConstraints { make in
            make.size.equalTo(50)
        }
        
        return view
    }
    
    private func createFloatingTOCButton() -> UIButton {
        let button = UIButton(type: .system)
        
        // 设置按钮尺寸
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.layer.cornerRadius = 22
        
        // 简洁的高斯模糊背景
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = button.bounds
        blurView.layer.cornerRadius = 22
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        
        // 将模糊背景添加到按钮 - 确保在最底层
        button.insertSubview(blurView, at: 0)
        
        // 设置目录图标 - 在模糊背景之后设置确保在上层
        button.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        button.tintColor = .systemOrange
        button.imageView?.contentMode = .scaleAspectFit
        button.imageView?.layer.zPosition = 100  // 确保图标在最上层
        
        // 调整图标大小和位置
        button.imageEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        
        // 添加微妙的阴影
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.15
        
        // 添加点击事件
        button.addTarget(self, action: #selector(toggleTableOfContents), for: .touchUpInside)
        
        // 添加点击缩放效果
        button.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchCancel), for: [.touchCancel, .touchUpOutside])
        
        // 添加长按手势用于调试（长按重新检测目录）
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleFloatingButtonLongPress(_:)))
        longPressGesture.minimumPressDuration = 1.0
        button.addGestureRecognizer(longPressGesture)
        
        // 初始隐藏状态
        button.alpha = 0
        button.isHidden = true
        

        
        return button
    }
    
    @objc private func buttonTouchDown() {
        // 按下时缩小动画
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut) {
            self.floatingTOCButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }
    

    
    @objc private func buttonTouchCancel() {
        // 取消时恢复
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.floatingTOCButton.transform = CGAffineTransform.identity
        }
    }
    
    @objc private func handleFloatingButtonLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            
            // 添加触觉反馈
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // 重新检测目录
//            manualTestTOCDetection()
        }
    }
    
    // MARK: - Content Loading
    private func updateTitle() {
        title = markdownFile?.displayName ?? "Markdown阅读器"
    }
    
    private func loadHTMLTemplate() {
        // 调试：打印Bundle中的所有HTML文件
        let bundleURL = Bundle.main.bundleURL
        print("Bundle路径: \(bundleURL)")
        
        // 查找所有可能的HTML模板文件
        let possibleNames = ["markdown_viewer_optimized", "markdown_viewer", "xmind_jsmind_viewer"]
        for name in possibleNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "html") {
                print("找到HTML文件: \(name).html -> \(url)")
            } else {
                print("未找到HTML文件: \(name).html")
            }
        }
        
        // 尝试多个HTML模板文件
        var templateURL: URL?
        var usedTemplate = ""
        
        // 优先尝试优化版
        if let url = Bundle.main.url(forResource: "markdown_viewer_optimized", withExtension: "html") {
            templateURL = url
            usedTemplate = "markdown_viewer_optimized"
        }
        // 其次尝试原版
        else if let url = Bundle.main.url(forResource: "markdown_viewer", withExtension: "html") {
            templateURL = url
            usedTemplate = "markdown_viewer"
        }
        
        guard let finalURL = templateURL else {
            let error = "找不到HTML模板文件，请确保HTML文件已添加到Xcode项目的Bundle Resources中"
            print("错误: \(error)")
            showError(error)
            return
        }
        
        print("使用HTML模板: \(usedTemplate)")
        
        do {
            let htmlString = try String(contentsOf: finalURL, encoding: .utf8)
            print("HTML模板加载成功，长度: \(htmlString.count)")
            webView.loadHTMLString(htmlString, baseURL: finalURL)
        } catch {
            let errorMsg = "加载HTML模板失败: \(error.localizedDescription)"
            print("错误: \(errorMsg)")
            showError(errorMsg)
        }
    }
    
    private func loadContent() {
        guard let file = markdownFile else {
            showError("没有选择文件")
            return
        }
        
        // 避免重复加载
        guard !isContentLoaded else {
            print("内容已加载，跳过重复加载")
            return
        }
        
        // 确保HTML模板已加载完成
        guard isHTMLTemplateReady else {
            print("HTML模板未准备好，等待加载完成")
            return
        }
        
        print("开始加载文件内容: \(file.displayName)")
        showLoading()
        
        // 异步加载文件内容
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                print("正在读取文件: \(file.url.path)")
                let content = try String(contentsOf: file.url, encoding: .utf8)
                print("文件读取成功，内容长度: \(content.count)")
                
                DispatchQueue.main.async {
                    self?.renderContent(content)
                }
            } catch {
                print("文件读取失败: \(error)")
                DispatchQueue.main.async {
                    self?.showError("文件读取失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func renderContent(_ content: String) {
        print("开始渲染内容，长度: \(content.count)")
        
        renderingService.renderContent(content, with: webView) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("内容渲染成功")
                    self?.isContentLoaded = true
                    self?.hideLoading()
                    
                    // 目录检测现在由WebView的回调消息触发，不再需要延迟检测
                case .failure(let error):
                    print("内容渲染失败: \(error)")
                    self?.showError(error.localizedDescription)
                    // 重置渲染服务状态，确保下次可以正常渲染
                    self?.renderingService.resetState()
                }
            }
        }
    }
    
    // MARK: - UI State Management
    private func showLoading() {
        loadingIndicator.startAnimating()
        loadingLabel.isHidden = false
        errorView.isHidden = true
        
        // 重置WebView透明度
        webView.alpha = 0.0
    }
    
    private func hideLoading() {
        loadingIndicator.stopAnimating()
        loadingLabel.isHidden = true
        errorView.isHidden = true
        
        // 简单自然的渐入动画
        UIView.animate(withDuration: 0.4, delay: 0.1, options: .curveEaseOut) {
            self.webView.alpha = 1.0
        }
    }
    
    private func showError(_ message: String) {
        hideLoading()
        
        // 隐藏WebView，显示错误页面
        webView.alpha = 0.0
        
        if let stackView = errorView.subviews.first as? UIStackView,
           let messageLabel = stackView.arrangedSubviews[2] as? UILabel {
            messageLabel.text = message
        }
        
        errorView.isHidden = false
    }
    
    private func handleRenderingStateChange(_ state: RenderingState) {
        switch state {
        case .idle:
            hideLoading()
            
        case .loading, .rendering:
            // 统一的加载状态 - 简洁明了
            showLoading()
            
        case .completed:
            hideLoading()
            
            // 渲染完成后检测目录
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showTableOfContentsButtonIfNeeded()
            }
            
        case .error(let message):
            showError(message)
        }
    }
    
    // MARK: - Actions
    @objc private func toggleTableOfContents() {
        // 恢复按钮缩放状态（带弹簧动画）
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.6, options: .curveEaseOut) {
            self.floatingTOCButton.transform = CGAffineTransform.identity
        }
        
        // 调用WebView中的目录切换功能
        let script = "if (typeof toggleTOC === 'function') { toggleTOC(); } else { console.log('目录功能未加载'); }"
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("目录切换失败: \(error)")
            }
        }
    }
    
    @objc private func refreshContent() {
        // 刷新时重置状态
        isContentLoaded = false
        webView.alpha = 0.0
        loadContent()
    }
    
    @objc private func shareContent() {
        guard let file = markdownFile else { return }
        
        let activityViewController = UIActivityViewController(
            activityItems: [file.url],
            applicationActivities: nil
        )
        
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(activityViewController, animated: true)
    }
    

    
    @objc private func themeDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            if let theme = notification.userInfo?["theme"] as? UIUserInterfaceStyle {
                print("MarkdownReaderViewController 主题已变化为: \(theme == .dark ? "深色" : "浅色")")
                
                // 更新导航栏按钮颜色
                self.updateNavigationBarAppearance()
            }
        }
    }
    
    private func updateNavigationBarAppearance() {
        // 确保导航栏返回按钮也是橙色
        navigationController?.navigationBar.tintColor = .systemOrange
        
        // 使用统一的橙色样式更新右侧按钮组
        navigationItem.rightBarButtonItems?.enumerated().forEach { index, button in
            // 所有按钮都使用统一的橙色样式
            button.applyThemeAwareStyle()
            
            // 更新主题切换按钮的图标（第一个按钮，索引0）
            if index == 0, let customButton = button.customView as? UIButton {
                let currentTheme = ThemeManager.shared.getCurrentTheme()
                let imageName = (currentTheme == .dark) ? "sun.max" : "moon"
                customButton.setImage(UIImage(systemName: imageName), for: .normal)
            }
        }
        
        // 同时更新悬浮目录按钮的主题适应
        updateFloatingTOCButtonAppearance()
    }
    
    private func updateFloatingTOCButtonAppearance() {
        // 确保悬浮按钮也跟随主题色
        floatingTOCButton.tintColor = .systemOrange
    }
}

// MARK: - WKNavigationDelegate
extension MarkdownReaderViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("HTML模板加载完成")
        isHTMLTemplateReady = true
        
        // 初始化WebView主题
        ThemeManager.shared.initializeWebViewTheme()
        
        // WebView加载完成后也检测目录
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showTableOfContentsButtonIfNeeded()
        }
        
        // HTML模板加载完成后，如果有待渲染的内容且尚未加载，则开始渲染
        if markdownFile != nil && !isContentLoaded {
            loadContent()
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("HTML模板加载失败: \(error)")
        showError("页面加载失败: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("HTML模板预加载失败: \(error)")
        showError("页面预加载失败: \(error.localizedDescription)")
    }
}

// MARK: - WKScriptMessageHandler
extension MarkdownReaderViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "nativePrint" {
            if let body = message.body as? String {
                print("[WebView] \(body)")
                
                // 监听目录生成完成消息
                if body == "TOC_GENERATION_COMPLETED" {
                    DispatchQueue.main.async { [weak self] in
                        print("收到目录生成完成通知，开始检测目录按钮")
                        self?.showTableOfContentsButtonIfNeeded()
                    }
                }
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension MarkdownReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 确保边缘滑动返回手势优先级最高
        if gestureRecognizer == navigationController?.interactivePopGestureRecognizer {
            return true
        }
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 检查是否有目录面板打开
        let script = "document.getElementById('toc-panel') && document.getElementById('toc-panel').classList.contains('open')"
        var tocIsOpen = false
        
        // 同步检查目录状态（仅用于手势决策）
        webView.evaluateJavaScript(script) { result, error in
            tocIsOpen = result as? Bool ?? false
        }
        
        // 如果目录面板打开，在左边缘区域禁用返回手势，避免冲突
        if tocIsOpen && gestureRecognizer == navigationController?.interactivePopGestureRecognizer {
            let location = gestureRecognizer.location(in: view)
            return location.x > 50 // 只在距离左边缘50pt之外允许返回手势
        }
        
        return false
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 确保在根控制器时禁用返回手势
        if gestureRecognizer == navigationController?.interactivePopGestureRecognizer {
            return navigationController?.viewControllers.count ?? 0 > 1
        }
        return true
    }
}


