//
//  XMindViewerViewController.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import UIKit
import WebKit
import SnapKit
import Foundation
import ZIPFoundation

/// XMind文件查看器 - 使用WKWebView + jsMind显示思维导图
class XMindViewerViewController: UIViewController {
    
    // MARK: - 属性
    var xmindFile: MarkdownFile?
    
    // MARK: - UI组件
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        // 允许JavaScript执行（用于jsMind）
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            config.preferences.javaScriptEnabled = true
        }
        
        // 添加消息处理器
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "refreshMindMap")
        config.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.backgroundColor = .systemBackground
        webView.scrollView.bounces = false
        return webView
    }()
    
    private lazy var loadingView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        return view
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .systemBlue
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private lazy var loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "正在解析思维导图..."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    private lazy var errorView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.isHidden = true
        return view
    }()
    
    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重试", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.addTarget(self, action: #selector(retryButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        loadXMindFile()
    }
    
    // MARK: - UI设置
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(webView)
        view.addSubview(loadingView)
        view.addSubview(errorView)
        
        // 设置加载视图
        loadingView.addSubview(loadingIndicator)
        loadingView.addSubview(loadingLabel)
        
        // 设置错误视图
        let errorStackView = UIStackView(arrangedSubviews: [errorLabel, retryButton])
        errorStackView.axis = .vertical
        errorStackView.spacing = 20
        errorStackView.alignment = .center
        
        errorView.addSubview(errorStackView)
        
        setupConstraints(errorStackView: errorStackView)
    }
    
    private func setupConstraints(errorStackView: UIStackView) {
        webView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        
        loadingView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        
        loadingIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-30)
        }
        
        loadingLabel.snp.makeConstraints { make in
            make.top.equalTo(loadingIndicator.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(20)
        }
        
        errorView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        
        errorStackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(40)
        }
        
        retryButton.snp.makeConstraints { make in
            make.height.equalTo(44)
            make.width.equalTo(120)
        }
    }
    
    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        title = xmindFile?.displayName ?? "XMind 思维导图"
        
        // 添加关闭按钮
        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        
        // 添加分享按钮
        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareButtonTapped)
        )
        
        // 添加刷新按钮
        let refreshButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshButtonTapped)
        )
        
        navigationItem.leftBarButtonItem = closeButton
        navigationItem.rightBarButtonItems = [shareButton, refreshButton]
    }
    
    // MARK: - XMind文件处理
    private func loadXMindFile() {
        guard let file = xmindFile else {
            showError("文件不存在")
            return
        }
        
        showLoading()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let mindMapData = try self?.parseXMindFile(file.url)
                
                DispatchQueue.main.async {
                    if let data = mindMapData {
                        self?.loadMindMapInWebView(data)
                    } else {
                        self?.showError("解析思维导图失败")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError("解析文件时出错：\(error.localizedDescription)")
                }
            }
        }
    }
    
    private func parseXMindFile(_ fileURL: URL) throws -> [String: Any] {
        print("🔍 开始解析XMind文件: \(fileURL.path)")
        
        // 1. 创建临时目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // 2. 解压XMind文件
        try unzipXMindFile(from: fileURL, to: tempDir)
        
        // 3. 查找content.json文件
        let contentJSONURL = tempDir.appendingPathComponent("content.json")
        
        // 如果没有content.json，尝试查找content.xml（旧版本XMind）
        if !FileManager.default.fileExists(atPath: contentJSONURL.path) {
            print("⚠️ 未找到content.json，尝试解析content.xml")
            return try parseContentXML(at: tempDir)
        }
        
        // 4. 读取并解析content.json
        let jsonData = try Data(contentsOf: contentJSONURL)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
        
        print("✅ 成功读取content.json")
        
        // 5. 处理不同版本的XMind格式
        var parsedData: [String: Any]
        
        if let jsonArray = jsonObject as? [[String: Any]] {
            // 新版XMind格式：content.json是数组
            print("📋 检测到新版XMind格式（数组格式）")
            guard let firstSheet = jsonArray.first else {
                throw XMindError.invalidFormat
            }
            parsedData = firstSheet
        } else if let jsonDict = jsonObject as? [String: Any] {
            // 旧版XMind格式：content.json是对象
            print("📋 检测到旧版XMind格式（对象格式）")
            parsedData = jsonDict
        } else {
            print("❌ 不支持的JSON格式")
            throw XMindError.invalidFormat
        }
        
        // 6. 转换为jsMind格式
        let mindMapData = try convertToJSMindFormat(parsedData)
        
        print("✅ 成功转换为jsMind格式")
        return mindMapData
    }
    
    private func unzipXMindFile(from sourceURL: URL, to destinationURL: URL) throws {
        print("📦 开始解压XMind文件...")
        
        // 使用ZIPFoundation解压
        do {
            try FileManager.default.unzipItem(at: sourceURL, to: destinationURL)
            print("✅ XMind文件解压成功")
            
            // 列出解压后的文件
            let contents = try FileManager.default.contentsOfDirectory(atPath: destinationURL.path)
            print("📁 解压后的文件: \(contents)")
        } catch {
            print("❌ 解压过程出错: \(error)")
            throw XMindError.unzipFailed
        }
    }
    
    private func parseContentXML(at tempDir: URL) throws -> [String: Any] {
        let contentXMLURL = tempDir.appendingPathComponent("content.xml")
        guard FileManager.default.fileExists(atPath: contentXMLURL.path) else {
            throw XMindError.contentNotFound
        }
        
        let xmlData = try Data(contentsOf: contentXMLURL)
        let parser = XMindXMLParser()
        return try parser.parseToJSMind(xmlData)
    }
    
    private func convertToJSMindFormat(_ jsonObject: [String: Any]) throws -> [String: Any] {
        print("🔄 开始转换XMind数据为jsMind格式...")
        print("📊 原始数据结构: \(jsonObject.keys.sorted())")
        
        // 查找根主题
        guard let rootTopic = findRootTopic(in: jsonObject) else {
            print("❌ 未找到根主题，创建默认主题")
            // 如果找不到根主题，创建一个默认的
            let defaultRootTopic: [String: Any] = [
                "id": "root",
                "title": xmindFile?.displayName ?? "XMind思维导图",
                "children": [String: Any]()
            ]
            return createJSMindData(from: defaultRootTopic)
        }
        
        print("✅ 找到根主题: \(rootTopic["title"] ?? rootTopic["topic"] ?? "未命名")")
        return createJSMindData(from: rootTopic)
    }
    
    private func createJSMindData(from rootTopic: [String: Any]) -> [String: Any] {
        // 转换为jsMind节点格式
        let rootNode = convertTopicToNode(rootTopic, isRoot: true)
        
        let jsMindData: [String: Any] = [
            "meta": [
                "name": xmindFile?.displayName ?? "XMind思维导图",
                "author": "XMind",
                "version": "1.0"
            ],
            "format": "node_tree",
            "data": rootNode
        ]
        
        print("✅ jsMind数据转换完成")
        return jsMindData
    }
    
    private func findRootTopic(in jsonObject: [String: Any]) -> [String: Any]? {
        print("🔍 查找根主题，JSON结构: \(jsonObject.keys.sorted())")
        
        // 尝试多种可能的路径查找根主题
        
        // 1. 新版XMind格式：直接包含rootTopic（最常见）
        if let rootTopic = jsonObject["rootTopic"] as? [String: Any] {
            print("✅ 在根级别找到rootTopic（新版格式）")
            return rootTopic
        }
        
        // 2. 标准旧版XMind格式: sheet -> rootTopic
        if let sheet = jsonObject["sheet"] as? [String: Any],
           let rootTopic = sheet["rootTopic"] as? [String: Any] {
            print("✅ 在sheet.rootTopic中找到根主题（旧版格式）")
            return rootTopic
        }
        
        // 3. 多工作表格式: sheets[0] -> rootTopic
        if let sheets = jsonObject["sheets"] as? [[String: Any]],
           let firstSheet = sheets.first,
           let rootTopic = firstSheet["rootTopic"] as? [String: Any] {
            print("✅ 在sheets[0].rootTopic中找到根主题")
            return rootTopic
        }
        
        // 4. XMind Zen格式: workbook -> sheets -> rootTopic
        if let workbook = jsonObject["workbook"] as? [String: Any],
           let sheets = workbook["sheets"] as? [[String: Any]],
           let firstSheet = sheets.first,
           let rootTopic = firstSheet["rootTopic"] as? [String: Any] {
            print("✅ 在workbook.sheets[0].rootTopic中找到根主题")
            return rootTopic
        }
        
        // 5. 检查是否有topic字段（可能是简化格式）
        if let topic = jsonObject["topic"] as? [String: Any] {
            print("✅ 在根级别找到topic")
            return topic
        }
        
        // 6. 如果直接包含主题信息（兼容某些特殊格式）
        if jsonObject["title"] != nil {
            print("✅ 根对象直接包含title，作为根主题")
            return jsonObject
        }
        
        // 7. 尝试查找任何包含title的对象
        for (key, value) in jsonObject {
            if let dict = value as? [String: Any], dict["title"] != nil {
                print("✅ 在\(key)中找到包含title的对象")
                return dict
            }
        }
        
        print("❌ 未找到根主题，可用的键: \(jsonObject.keys.sorted())")
        
        // 打印更详细的结构信息用于调试
        for (key, value) in jsonObject {
            if let dict = value as? [String: Any] {
                print("  \(key): \(dict.keys.sorted())")
            } else if let array = value as? [Any] {
                print("  \(key): 数组，长度 \(array.count)")
            } else {
                print("  \(key): \(type(of: value))")
            }
        }
        
        return nil
    }
    
    private func convertTopicToNode(_ topic: [String: Any], isRoot: Bool = false) -> [String: Any] {
        let id = topic["id"] as? String ?? UUID().uuidString
        
        // 兼容新旧格式的标题获取
        let title = topic["title"] as? String ?? 
                   topic["topic"] as? String ?? 
                   topic["text"] as? String ?? 
                   "未命名主题"
        
        var node: [String: Any] = [
            "id": isRoot ? "root" : id,
            "topic": title
        ]
        
        // 处理子主题 - 兼容多种格式
        var children: [[String: Any]] = []
        
        // 格式1: children.attached (新版XMind格式)
        if let childrenTopics = topic["children"] as? [String: Any],
           let attached = childrenTopics["attached"] as? [[String: Any]] {
            print("📝 使用children.attached格式解析子节点")
            _ = childrenTopics // 标记为已使用
            for childTopic in attached {
                let childNode = convertTopicToNode(childTopic)
                children.append(childNode)
            }
        }
        // 格式2: 直接的children数组
        else if let childrenArray = topic["children"] as? [[String: Any]] {
            print("📝 使用直接children数组格式解析子节点")
            for childTopic in childrenArray {
                let childNode = convertTopicToNode(childTopic)
                children.append(childNode)
            }
        }
        // 格式3: topics数组 (某些XMind版本)
        else if let topicsArray = topic["topics"] as? [[String: Any]] {
            print("📝 使用topics数组格式解析子节点")
            for childTopic in topicsArray {
                let childNode = convertTopicToNode(childTopic)
                children.append(childNode)
            }
        }
        // 格式4: subtopics数组
        else if let subtopicsArray = topic["subtopics"] as? [[String: Any]] {
            print("📝 使用subtopics数组格式解析子节点")
            for childTopic in subtopicsArray {
                let childNode = convertTopicToNode(childTopic)
                children.append(childNode)
            }
        }
        // 格式5: 检查是否有空的children对象但没有attached
        else if let childrenTopics = topic["children"] as? [String: Any] {
            print("📝 发现children对象但没有attached数组，可能是空的子节点集合")
            // 这种情况下children为空，不需要处理
        }
        
        if !children.isEmpty {
            node["children"] = children
        }
        
        print("📝 转换节点: \(title) (子节点: \(children.count)个)")
        return node
    }
    
    private func loadMindMapInWebView(_ mindMapData: [String: Any]) {
        print("🌐 开始在WebView中加载思维导图...")
        
        guard let htmlURL = Bundle.main.url(forResource: "xmind_jsmind_viewer", withExtension: "html") else {
            showError("找不到HTML模板文件")
            return
        }
        
        // 加载HTML文件
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        
        // 存储思维导图数据，等待HTML加载完成后传入
        self.pendingMindMapData = mindMapData
    }
    
    private var pendingMindMapData: [String: Any]?
    

    
    // MARK: - UI状态管理
    private func showLoading() {
        loadingIndicator.startAnimating()
        loadingView.isHidden = false
        webView.isHidden = true
        errorView.isHidden = true
    }
    
    private func showError(_ message: String) {
        print("❌ 显示错误: \(message)")
        loadingIndicator.stopAnimating()
        loadingView.isHidden = true
        webView.isHidden = true
        errorView.isHidden = false
        errorLabel.text = message
    }
    
    private func showWebView() {
        loadingIndicator.stopAnimating()
        loadingView.isHidden = true
        webView.isHidden = false
        errorView.isHidden = true
    }
    
    // MARK: - 事件处理
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func shareButtonTapped() {
        guard let file = xmindFile else { return }
        
        // 显示分享选择菜单
        let alertController = UIAlertController(
            title: "分享XMind文件",
            message: "选择分享方式",
            preferredStyle: .actionSheet
        )
        
        // 在XMind中打开
        let openInXMindAction = UIAlertAction(title: "在XMind中打开", style: .default) { [weak self] _ in
            self?.openInXMindApp()
        }
        openInXMindAction.setValue(UIImage(systemName: "brain.head.profile"), forKey: "image")
        
        // 分享到其他应用
        let shareAction = UIAlertAction(title: "分享到其他应用", style: .default) { [weak self] _ in
            self?.shareToOtherApps()
        }
        shareAction.setValue(UIImage(systemName: "square.and.arrow.up"), forKey: "image")
        
        // 取消
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(openInXMindAction)
        alertController.addAction(shareAction)
        alertController.addAction(cancelAction)
        
        // 设置iPad的popover
        if let popover = alertController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alertController, animated: true)
    }
    
    /// 在XMind应用中打开
    private func openInXMindApp() {
        guard let file = xmindFile else { return }
        
        // 智能处理文件，确保外部应用能够访问
        let loadingAlert = UIAlertController(title: "正在准备", message: "正在准备XMind文件...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let fileURL: URL
                
                switch file.source {
                case .bundle:
                    fileURL = try self?.copyFileToSharedDirectory(file: file) ?? file.url
                case .documents:
                    fileURL = file.url
                }
                
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.openFileWithDocumentController(fileURL)
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.showErrorAlert("准备文件失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /// 分享到其他应用
    private func shareToOtherApps() {
        guard let file = xmindFile else { return }
        
        let activityController = UIActivityViewController(
            activityItems: [file.url],
            applicationActivities: nil
        )
        
        // 设置iPad的popover
        if let popover = activityController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityController, animated: true)
    }
    
    /// 复制文件到共享目录
    private func copyFileToSharedDirectory(file: MarkdownFile) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let appTempDir = tempDir.appendingPathComponent("XMindShare_\(ProcessInfo.processInfo.processIdentifier)")
        
        try FileManager.default.createDirectory(at: appTempDir, withIntermediateDirectories: true)
        
        let sharedFileURL = appTempDir.appendingPathComponent(file.displayName)
        
        if FileManager.default.fileExists(atPath: sharedFileURL.path) {
            try FileManager.default.removeItem(at: sharedFileURL)
        }
        
        try FileManager.default.copyItem(at: file.url, to: sharedFileURL)
        
        let attributes = [FileAttributeKey.posixPermissions: 0o644]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: sharedFileURL.path)
        
        print("✅ 文件已复制到临时共享目录: \(sharedFileURL.path)")
        
        return sharedFileURL
    }
    
    /// 使用文档交互控制器打开文件
    private func openFileWithDocumentController(_ fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showErrorAlert("文件不存在：\(fileURL.path)")
            return
        }
        
        print("🔍 尝试使用改进的文件共享方式打开XMind文件")
        print("  - 文件路径: \(fileURL.path)")
        
        // 使用UIActivityViewController，这是iOS推荐的文件共享方式
        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        activityVC.setValue("在XMind中打开", forKey: "subject")
        
        // 设置完成处理程序
        activityVC.completionWithItemsHandler = { [weak self] (activityType: UIActivity.ActivityType?, completed: Bool, returnedItems: [Any]?, error: Error?) in
            if let error = error {
                print("❌ 分享失败: \(error.localizedDescription)")
                self?.showErrorAlert("分享失败: \(error.localizedDescription)")
            } else if completed {
                print("✅ 分享成功: \(activityType?.rawValue ?? "未知应用")")
                if let activityType = activityType, 
                   activityType.rawValue.lowercased().contains("xmind") {
                    self?.showSuccessAlert("文件已成功发送到XMind应用")
                } else {
                    self?.showSuccessAlert("文件已成功分享到外部应用")
                }
            } else {
                print("⚠️ 用户取消分享")
            }
        }
        
        // 设置iPad的popover
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(activityVC, animated: true)
    }
    
    /// 显示错误提示
    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    /// 显示成功提示
    private func showSuccessAlert(_ message: String) {
        let alert = UIAlertController(title: "成功", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func retryButtonTapped() {
        loadXMindFile()
    }
    
    @objc private func refreshButtonTapped() {
        print("🔄 用户点击导航栏刷新按钮")
        loadXMindFile()
    }
}

// MARK: - WKScriptMessageHandler
extension XMindViewerViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "refreshMindMap" {
            print("🔄 收到来自WebView的刷新请求")
            DispatchQueue.main.async {
                self.loadXMindFile()
            }
        }
    }
}

// MARK: - WKNavigationDelegate
extension XMindViewerViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🌐 HTML页面加载完成")
        
        // HTML加载完成后，传入思维导图数据
        if let mindMapData = pendingMindMapData {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: mindMapData, options: [])
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                
                let jsCode = "loadMindMap(\(jsonString));"
                print("📤 执行JavaScript: \(jsCode.prefix(100))...")
                
                webView.evaluateJavaScript(jsCode) { [weak self] result, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ JavaScript执行失败: \(error)")
                            self?.showError("加载思维导图失败：\(error.localizedDescription)")
                        } else {
                            print("✅ 思维导图加载成功")
                            self?.showWebView()
                        }
                    }
                }
                
                pendingMindMapData = nil
                
            } catch {
                print("❌ JSON序列化失败: \(error)")
                showError("数据序列化失败：\(error.localizedDescription)")
            }
        } else {
            showWebView()
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView加载失败: \(error)")
        showError("加载思维导图失败：\(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView预加载失败: \(error)")
        showError("加载页面失败：\(error.localizedDescription)")
    }
}

// MARK: - XMind解析相关
enum XMindError: LocalizedError {
    case contentNotFound
    case unzipFailed
    case xmlParsingFailed
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .contentNotFound:
            return "找不到思维导图内容文件"
        case .unzipFailed:
            return "解压XMind文件失败"
        case .xmlParsingFailed:
            return "解析XML文件失败"
        case .invalidFormat:
            return "不支持的XMind文件格式"
        }
    }
}

// MARK: - UIDocumentInteractionControllerDelegate
extension XMindViewerViewController: UIDocumentInteractionControllerDelegate {
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, didEndSendingToApplication application: String?) {
        if let app = application {
            print("✅ 文件已发送到应用: \(app)")
            
            let alert = UIAlertController(
                title: "成功",
                message: "XMind文件已成功发送到\(app)。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
        }
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, willBeginSendingToApplication application: String?) {
        if let app = application {
            print("📤 正在发送文件到应用: \(app)")
        }
    }
}

/// XMind XML解析器（用于旧版本XMind文件）
class XMindXMLParser: NSObject {
    
    private var mindMapData: [String: Any] = [:]
    private var currentElement = ""
    private var currentTopic: [String: Any] = [:]
    private var topicStack: [[String: Any]] = []
    private var rootTopic: [String: Any] = [:]
    
    func parseToJSMind(_ xmlData: Data) throws -> [String: Any] {
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        
        if parser.parse() {
            return createJSMindFormat()
        } else {
            throw XMindError.xmlParsingFailed
        }
    }
    
    private func createJSMindFormat() -> [String: Any] {
        return [
            "meta": [
                "name": "XMind思维导图",
                "author": "XMind",
                "version": "1.0"
            ],
            "format": "node_tree",
            "data": rootTopic.isEmpty ? createDefaultTopic() : rootTopic
        ]
    }
    
    private func createDefaultTopic() -> [String: Any] {
        return [
            "id": "root",
            "topic": "XMind思维导图",
            "children": []
        ]
    }
}

// MARK: - XMLParserDelegate
extension XMindXMLParser: XMLParserDelegate {
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "topic":
            let topic: [String: Any] = [
                "id": attributeDict["id"] ?? UUID().uuidString,
                "topic": "",
                "children": []
            ]
            
            if rootTopic.isEmpty {
                rootTopic = topic
                currentTopic = topic
            } else {
                topicStack.append(currentTopic)
                currentTopic = topic
            }
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedString.isEmpty && currentElement == "title" {
            currentTopic["topic"] = trimmedString
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "topic":
            if !topicStack.isEmpty {
                let parentTopic = topicStack.removeLast()
                var children = parentTopic["children"] as? [[String: Any]] ?? []
                children.append(currentTopic)
                
                var updatedParent = parentTopic
                updatedParent["children"] = children
                
                if topicStack.isEmpty {
                    rootTopic = updatedParent
                }
                currentTopic = updatedParent
            }
            
        default:
            break
        }
        
        currentElement = ""
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("XML解析错误: \(parseError.localizedDescription)")
    }
} 
