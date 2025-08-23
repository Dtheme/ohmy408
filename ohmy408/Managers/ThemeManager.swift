import UIKit
import WebKit

// 主题管理器 - 负责原生应用与WebView的主题同步
class ThemeManager: NSObject {
    static let shared = ThemeManager()
    
    // 当前主题状态
    private var currentTheme: UIUserInterfaceStyle = .unspecified
    
    // 主题变化通知名称
    static let themeDidChangeNotification = Notification.Name("ThemeDidChangeNotification")
    
    // WebView引用
    private weak var webView: WKWebView?
    
    // 是否正在同步主题（防止循环调用）
    private var isSyncingTheme = false
    
    override init() {
        super.init()
        
        // 监听系统主题变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemThemeDidChange),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        // 获取当前系统主题
        updateCurrentTheme()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 公共方法
    
    /// 设置WebView引用
    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        
        // 配置WebView消息处理器
        let configuration = webView.configuration
        configuration.userContentController.add(self, name: "themeHandler")
        
        // 注意：不在这里立即同步主题，而是等待WebView完全加载完成后
        // 主题同步将在WebView的didFinish回调中进行
        print("🎨 ThemeManager WebView已设置，等待页面加载完成后同步主题")
    }
    
    /// 切换主题
    func toggleTheme() {
        let newTheme: UIUserInterfaceStyle
        
        switch currentTheme {
        case .dark:
            newTheme = .light
        case .light:
            newTheme = .dark
        default:
            // 如果当前是未指定，根据系统主题切换
            newTheme = UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .light : .dark
        }
        
        setTheme(newTheme)
    }
    
    /// 设置主题
    func setTheme(_ theme: UIUserInterfaceStyle) {
        guard !isSyncingTheme else { return }
        
        currentTheme = theme
        
        // 更新应用主题
        updateApplicationTheme(theme)
        
        // 同步到WebView
        syncThemeToWebView(notifyNative: false)
        
        // 发送通知
        NotificationCenter.default.post(
            name: ThemeManager.themeDidChangeNotification,
            object: self,
            userInfo: ["theme": theme]
        )
        
        // 保存主题设置
        UserDefaults.standard.set(theme.rawValue, forKey: "selectedTheme")
        
        print("🎨 原生主题已切换到: \(theme == .dark ? "深色" : "浅色")")
    }
    
    /// 获取当前主题
    func getCurrentTheme() -> UIUserInterfaceStyle {
        return currentTheme
    }
    
    /// 创建主题切换按钮
    func createThemeToggleButton() -> UIBarButtonItem {
        // 使用自定义视图创建统一风格的主题切换按钮
        let customButton = UIButton(type: .system)
        customButton.setImage(getThemeButtonImage(), for: .normal)
        customButton.tintColor = .systemOrange
        customButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        
        // 不添加背景色，保持简洁的橙色线条效果
        customButton.backgroundColor = .clear
        
        // 添加点击效果
        customButton.addTarget(self, action: #selector(themeButtonTapped), for: .touchUpInside)
        
        // 添加触摸反馈
        if #available(iOS 13.0, *) {
            customButton.addTarget(customButton, action: #selector(UIButton.buttonHighlight), for: .touchDown)
            customButton.addTarget(customButton, action: #selector(UIButton.buttonNormal), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        
        let button = UIBarButtonItem(customView: customButton)
        
        return button
    }
    
    // MARK: - 私有方法
    
    /// 更新当前主题
    private func updateCurrentTheme() {
        // 检查是否有保存的主题设置
        if UserDefaults.standard.object(forKey: "selectedTheme") != nil {
            // 有保存的主题设置，使用保存的值
            let savedTheme = UserDefaults.standard.integer(forKey: "selectedTheme")
            currentTheme = UIUserInterfaceStyle(rawValue: savedTheme) ?? .unspecified
            print("🎨 恢复保存的主题: \(currentTheme == .dark ? "深色" : currentTheme == .light ? "浅色" : "未指定")")
        } else {
            // 没有保存的主题设置，使用系统主题
            currentTheme = UIScreen.main.traitCollection.userInterfaceStyle
            print("🎨 使用系统主题: \(currentTheme == .dark ? "深色" : "浅色")")
        }
        
        // 应用恢复的主题
        updateApplicationTheme(currentTheme)
    }
    
    /// 更新应用主题
    private func updateApplicationTheme(_ theme: UIUserInterfaceStyle) {
        DispatchQueue.main.async {
            // 更新所有窗口的主题
            UIApplication.shared.windows.forEach { window in
                window.overrideUserInterfaceStyle = theme
            }
            
            // 更新状态栏样式
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.windows.forEach { window in
                    window.overrideUserInterfaceStyle = theme
                }
            }
        }
    }
    
    /// 同步主题到WebView
    private func syncThemeToWebView(notifyNative: Bool) {
        guard let webView = webView else { return }
        
        let themeString = (currentTheme == .dark) ? "dark" : "light"
        let script = """
        (function() {
            if (window.handleNativeThemeChange) {
                window.handleNativeThemeChange('\(themeString)');
            } else {
                // 如果函数还未加载，等待一小段时间再尝试
                setTimeout(function() {
                    if (window.handleNativeThemeChange) {
                        window.handleNativeThemeChange('\(themeString)');
                    }
                }, 100);
            }
        })();
        """
        
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("⚠️ WebView主题同步失败: \(error)")
                } else {
                    print("✅ WebView主题已同步到: \(themeString)")
                }
            }
        }
    }
    
    /// 初始化WebView主题（页面加载完成后调用）
    func initializeWebViewTheme() {
        // 延迟执行，确保JS函数已加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.syncThemeToWebView(notifyNative: false)
        }
    }
    
    /// 获取主题按钮图标
    private func getThemeButtonImage() -> UIImage? {
        let imageName = (currentTheme == .dark) ? "sun.max" : "moon"
        return UIImage(systemName: imageName)
    }
    
    /// 更新导航栏按钮图标
    private func updateNavigationBarButtons() {
        NotificationCenter.default.post(
            name: Notification.Name("UpdateThemeButtonNotification"),
            object: self
        )
    }
    
    // MARK: - 事件处理
    
    @objc private func systemThemeDidChange() {
        // 检查系统主题是否改变
        let systemTheme = UIScreen.main.traitCollection.userInterfaceStyle
        
        // 如果用户没有手动设置主题，跟随系统
        if UserDefaults.standard.object(forKey: "selectedTheme") == nil {
            setTheme(systemTheme)
            print("🎨 系统主题变化，自动跟随: \(systemTheme == .dark ? "深色" : "浅色")")
        } else {
            print("🎨 系统主题变化，但保持用户设置的主题")
        }
    }
    
    @objc private func themeButtonTapped() {
        toggleTheme()
    }
}

// MARK: - WKScriptMessageHandler
extension ThemeManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "themeHandler",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              type == "themeChanged",
              let themeString = body["theme"] as? String else {
            return
        }
        
        print("📱 收到WebView主题变化通知: \(themeString)")
        
        // 避免循环调用
        isSyncingTheme = true
        
        let theme: UIUserInterfaceStyle = (themeString == "dark") ? .dark : .light
        setTheme(theme)
        
        // 更新导航栏按钮
        updateNavigationBarButtons()
        
        isSyncingTheme = false
    }
}

// MARK: - UIBarButtonItem扩展 - 统一按钮风格
extension UIBarButtonItem {
    
    /// 创建统一风格的导航栏按钮
    static func createStandardButton(
        systemName: String,
        target: Any?,
        action: Selector
    ) -> UIBarButtonItem {
        // 使用自定义视图创建统一的橙色按钮
        let customButton = UIButton(type: .system)
        customButton.setImage(UIImage(systemName: systemName), for: .normal)
        customButton.tintColor = .systemOrange  // 统一使用橙色
        customButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        
        // 不添加背景色，保持简洁的橙色线条效果
        customButton.backgroundColor = .clear
        
        // 添加点击效果
        customButton.addTarget(target, action: action, for: .touchUpInside)
        
        // 添加触摸反馈
        if #available(iOS 13.0, *) {
            customButton.addTarget(nil, action: #selector(UIButton.buttonHighlight), for: .touchDown)
            customButton.addTarget(nil, action: #selector(UIButton.buttonNormal), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        
        let button = UIBarButtonItem(customView: customButton)
        
        return button
    }
    
    /// 创建带现代化配置的系统按钮
    static func createSystemButton(
        _ systemItem: UIBarButtonItem.SystemItem,
        target: Any?,
        action: Selector
    ) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            barButtonSystemItem: systemItem,
            target: target,
            action: action
        )
        
        // 统一使用橙色主题
        button.tintColor = .systemOrange
        
        return button
    }
    
    /// 创建带文本的按钮
    static func createTextButton(
        title: String,
        target: Any?,
        action: Selector
    ) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            title: title,
            style: .plain,
            target: target,
            action: action
        )
        
        // 统一使用橙色主题
        button.tintColor = .systemOrange
        
        // 设置现代化字体和颜色
        if #available(iOS 13.0, *) {
            button.setTitleTextAttributes([
                .font: UIFont.systemFont(ofSize: 17, weight: .medium),
                .foregroundColor: UIColor.systemOrange
            ], for: .normal)
        }
        
        return button
    }
    
    /// 获取自定义按钮视图（如果存在）
    private var customButtonView: UIButton? {
        return customView as? UIButton
    }
    
    /// 应用主题感知的颜色
    func applyThemeAwareStyle(isSpecialButton: Bool = false) {
        // 统一使用橙色主题
        let targetColor: UIColor = .systemOrange
        
        // 更新标准按钮的颜色
        self.tintColor = targetColor
        
        // 如果是自定义视图按钮，更新其样式（不添加背景色）
        if let customButton = customButtonView {
            customButton.tintColor = targetColor
            customButton.backgroundColor = .clear  // 保持透明背景
        }
        
        // 为所有按钮添加统一的视觉效果
        if #available(iOS 13.0, *) {
            // 设置按钮的选中状态样式
            self.setTitleTextAttributes([
                .foregroundColor: targetColor
            ], for: .normal)
        }
    }
}

// MARK: - UIButton扩展 - 触摸反馈效果
extension UIButton {
    
    @objc func buttonHighlight() {
        UIView.animate(withDuration: 0.1) {
            self.alpha = 0.6
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }
    
    @objc func buttonNormal() {
        UIView.animate(withDuration: 0.1) {
            self.alpha = 1.0
            self.transform = CGAffineTransform.identity
        }
    }
}

// MARK: - UIViewController扩展
extension UIViewController {
    
    /// 设置主题切换按钮到导航栏
    func setupThemeToggleButton() {
        let themeButton = ThemeManager.shared.createThemeToggleButton()
        
        // 获取现有的右侧按钮
        var rightBarButtonItems = navigationItem.rightBarButtonItems ?? []
        
        // 将主题按钮添加到最左边（数组开头）
        rightBarButtonItems.insert(themeButton, at: 0)
        
        navigationItem.rightBarButtonItems = rightBarButtonItems
        
        // 监听主题变化以更新按钮
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UpdateThemeButtonNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThemeButton()
        }
        
        // 监听主题变化
        NotificationCenter.default.addObserver(
            forName: ThemeManager.themeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThemeButton()
        }
    }
    
    /// 更新主题按钮图标
    private func updateThemeButton() {
        guard let rightBarButtonItems = navigationItem.rightBarButtonItems,
              let themeButton = rightBarButtonItems.first else {
            return
        }
        
        let currentTheme = ThemeManager.shared.getCurrentTheme()
        let imageName = (currentTheme == .dark) ? "sun.max" : "moon"
        themeButton.image = UIImage(systemName: imageName)
    }
} 