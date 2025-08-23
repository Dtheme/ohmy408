//
//  FileListViewController.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import UIKit
import SnapKit

/// 学科分组模型
class SubjectGroup {
    let title: String
    let files: [MarkdownFile]
    let iconName: String
    let gradientColors: [UIColor]
    var isExpanded: Bool
    
    init(title: String, files: [MarkdownFile], iconName: String, gradientColors: [UIColor], isExpanded: Bool = true) {
        self.title = title
        self.files = files
        self.iconName = iconName
        self.gradientColors = gradientColors
        self.isExpanded = isExpanded
    }
    
    var fileCount: Int { files.count }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

/// 现代化文件列表视图控制器
class FileListViewController: UIViewController {
    
    // MARK: - UI组件
    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.backgroundColor = .systemBackground
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .automatic
        return scroll
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        return view
    }()
    
    private lazy var headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "有手就行"
        label.font = .systemFont(ofSize: 34, weight: .bold)
        label.textColor = .label
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Fuck 408"
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private lazy var actionButtonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.alignment = .center
        return stackView
    }()
    
    private lazy var syncButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "icloud.and.arrow.up"), for: .normal)
        button.tintColor = .systemOrange
        button.backgroundColor = .systemOrange.withAlphaComponent(0.1)
        button.layer.cornerRadius = 20
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(syncButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var importButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle"), for: .normal)
        button.tintColor = .systemOrange
        button.backgroundColor = .systemOrange.withAlphaComponent(0.1)
        button.layer.cornerRadius = 20
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(importButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var themeButton: UIButton = {
        let button = UIButton(type: .system)
        let currentTheme = ThemeManager.shared.getCurrentTheme()
        let imageName = (currentTheme == .dark) ? "sun.max" : "moon"
        
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = .systemOrange
        button.backgroundColor = .systemOrange.withAlphaComponent(0.1)
        button.layer.cornerRadius = 20
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(themeButtonTapped), for: .touchUpInside)
        
        return button
    }()
    
    private lazy var searchBar: UISearchBar = {
        let search = UISearchBar()
        search.placeholder = "搜索文档名称或学科..."
        search.searchBarStyle = .minimal
        search.backgroundColor = .clear
        search.delegate = self
        
        // 自定义搜索栏外观
        let textField = search.searchTextField
        textField.backgroundColor = .secondarySystemGroupedBackground
        textField.layer.cornerRadius = 12
        textField.layer.masksToBounds = true
        textField.font = .systemFont(ofSize: 16)
        
        return search
    }()
    
    private lazy var statsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var subjectsCollectionView: UICollectionView = {
        let layout = createSubjectsLayout()
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.delegate = self
        collection.dataSource = self
        collection.showsVerticalScrollIndicator = false
        collection.isScrollEnabled = false // 禁用滚动
        collection.register(DocumentCell.self, forCellWithReuseIdentifier: DocumentCell.identifier)
        collection.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: SectionHeaderView.identifier)
        return collection
    }()
    
    private lazy var searchResultsTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.backgroundColor = .clear
        table.delegate = self
        table.dataSource = self
        table.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.identifier)
        table.isScrollEnabled = false
        table.separatorStyle = .none
        table.isHidden = true
        return table
    }()
    
    private lazy var emptySearchView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }()
    
    private lazy var recentFilesTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.backgroundColor = .clear
        table.delegate = self
        table.dataSource = self
        table.register(RecentFileCell.self, forCellReuseIdentifier: RecentFileCell.identifier)
        table.isScrollEnabled = false
        table.separatorStyle = .none
        return table
    }()
    
    private lazy var refreshControl: UIRefreshControl = {
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        refresh.tintColor = .systemOrange
        return refresh
    }()
    
    // MARK: - 数据源
    private var markdownFiles: [MarkdownFile] = []
    private var subjectGroups: [SubjectGroup] = []
    private var recentFiles: [MarkdownFile] = []
    private var filteredGroups: [SubjectGroup] = []
    private var searchResults: [MarkdownFile] = []
    private let fileManager = MarkdownFileManager.shared
    private let cloudSyncManager = CloudSyncManager.shared
    private let fileImportManager = FileImportManager.shared
    private let recentFileManager = RecentFileManager.shared
    private var isSearching = false
    private var currentSearchText = ""
    
    // MARK: - 分组状态管理
    private let groupStatesKey = "SubjectGroupExpandedStates"
    
    /// 保存分组展开状态到UserDefaults
    private func saveGroupStates() {
        var states: [String: Bool] = [:]
        for group in subjectGroups {
            states[group.title] = group.isExpanded
        }
        UserDefaults.standard.set(states, forKey: groupStatesKey)
        print("💾 已保存分组状态: \(states)")
    }
    
    /// 从UserDefaults恢复分组展开状态
    private func loadGroupStates() -> [String: Bool] {
        let states = UserDefaults.standard.dictionary(forKey: groupStatesKey) as? [String: Bool] ?? [:]
        print("已加载分组状态: \(states)")
        return states
    }
    
    // MARK: - 约束
    private var currentCollectionViewHeight: CGFloat = 100
    private var currentRecentFilesHeight: CGFloat = 0
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
        loadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        loadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI设置
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 设置滚动视图
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.refreshControl = refreshControl
        
        // 设置内容视图
        setupContentView()
        setupConstraints()
        
        // 设置主题管理器
        setupThemeManager()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColdStartSyncCompleted(_:)),
            name: .coldStartSyncCompleted,
            object: nil
        )
    }
    
    @objc private func handleColdStartSyncCompleted(_ notification: Notification) {
        DispatchQueue.main.async {
            // 重新加载数据以显示同步后的文件
            self.loadData()
            
            // 可选：显示同步结果提示
            if let message = notification.object as? String {
                self.showSyncCompletedToast(message: message)
            }
        }
    }
    
    private func showSyncCompletedToast(message: String) {
        showInfoToast(message)
    }
    
    private func setupContentView() {
        contentView.addSubview(headerView)
        contentView.addSubview(searchBar)
        contentView.addSubview(statsContainerView)
        contentView.addSubview(subjectsCollectionView)
        contentView.addSubview(searchResultsTableView)
        contentView.addSubview(emptySearchView)
        contentView.addSubview(recentFilesTableView)
        
        headerView.addSubview(titleLabel)
        headerView.addSubview(subtitleLabel)
        headerView.addSubview(actionButtonsStackView)
        
        // 设置按钮 - 添加主题切换按钮
        actionButtonsStackView.addArrangedSubview(themeButton)
        actionButtonsStackView.addArrangedSubview(syncButton)
        actionButtonsStackView.addArrangedSubview(importButton)
        
        setupStatsView()
        setupEmptySearchView()
    }
    
    private func setupStatsView() {
        let totalFilesCard = createStatsCard(
            title: "总文档",
            value: "0",
            icon: "doc.text.fill",
            color: .systemBlue
        )
        
        let totalSizeCard = createStatsCard(
            title: "总大小",
            value: "0 KB",
            icon: "externaldrive.fill",
            color: .systemGreen
        )
        
        let subjectsCard = createStatsCard(
            title: "学科数",
            value: "0",
            icon: "folder.fill",
            color: .systemOrange
        )
        
        let stackView = UIStackView(arrangedSubviews: [totalFilesCard, totalSizeCard, subjectsCard])
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 12
        
        statsContainerView.addSubview(stackView)
        
        // 使用SnapKit设置约束
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func setupEmptySearchView() {
        // 创建空状态图标
        let emptyIconImageView = UIImageView()
        emptyIconImageView.image = UIImage(systemName: "magnifyingglass")
        emptyIconImageView.tintColor = .systemGray3
        emptyIconImageView.contentMode = .scaleAspectFit
        
        // 创建主标题
        let emptyTitleLabel = UILabel()
        emptyTitleLabel.text = "未找到匹配的文档"
        emptyTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        emptyTitleLabel.textColor = .secondaryLabel
        emptyTitleLabel.textAlignment = .center
        
        // 创建副标题
        let emptySubtitleLabel = UILabel()
        emptySubtitleLabel.text = "尝试使用不同的关键词搜索"
        emptySubtitleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        emptySubtitleLabel.textColor = .tertiaryLabel
        emptySubtitleLabel.textAlignment = .center
        emptySubtitleLabel.numberOfLines = 0
        
        // 创建建议标签
        let suggestionLabel = UILabel()
        suggestionLabel.text = "搜索提示：可以搜索文档名称或学科名称"
        suggestionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        suggestionLabel.textColor = .systemBlue
        suggestionLabel.textAlignment = .center
        suggestionLabel.numberOfLines = 0
        
        // 创建垂直堆栈视图
        let stackView = UIStackView(arrangedSubviews: [
            emptyIconImageView,
            emptyTitleLabel,
            emptySubtitleLabel,
            suggestionLabel
        ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        
        emptySearchView.addSubview(stackView)
        
        // 设置约束
        // 使用SnapKit设置约束
        stackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(40)
            make.trailing.lessThanOrEqualToSuperview().offset(-40)
        }
        
        emptyIconImageView.snp.makeConstraints { make in
            make.size.equalTo(80)
        }
    }
    
    private func createStatsCard(title: String, value: String, icon: String, color: UIColor) -> StatsCardView {
        let cardView = StatsCardView()
        cardView.configure(title: title, value: value, icon: icon, color: color)
        return cardView
    }
    

    
    private func setupThemeManager() {
        // 监听主题变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.themeDidChangeNotification,
            object: nil
        )
        
        print("FileListViewController 主题管理器已设置")
    }
    
    private func setupConstraints() {
        // 使用 SnapKit 设置约束
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalTo(view)
        }
        
        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView)
            make.width.equalTo(scrollView)
        }
        
        headerView.snp.makeConstraints { make in
            make.top.equalTo(contentView).offset(20)
            make.leading.trailing.equalTo(contentView).inset(20)
        }
        
        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalTo(headerView)
        }
        
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.leading.bottom.equalTo(headerView)
        }
        
        actionButtonsStackView.snp.makeConstraints { make in
            make.top.trailing.equalTo(headerView)
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(16)
        }
        
        themeButton.snp.makeConstraints { make in
            make.size.equalTo(40)
        }
        
        syncButton.snp.makeConstraints { make in
            make.size.equalTo(40)
        }
        
        importButton.snp.makeConstraints { make in
            make.size.equalTo(40)
        }
        
        searchBar.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom).offset(20)
            make.leading.trailing.equalTo(contentView).inset(16)
        }
        
        statsContainerView.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom).offset(20)
            make.leading.trailing.equalTo(contentView).inset(20)
        }
        
        subjectsCollectionView.snp.makeConstraints { make in
            make.top.equalTo(statsContainerView.snp.bottom).offset(30)
            make.leading.trailing.equalTo(contentView)
            make.height.equalTo(currentCollectionViewHeight)
        }
        
        searchResultsTableView.snp.makeConstraints { make in
            make.top.equalTo(statsContainerView.snp.bottom).offset(30)
            make.leading.trailing.equalTo(contentView)
            make.height.equalTo(400)
        }
        
        emptySearchView.snp.makeConstraints { make in
            make.top.equalTo(statsContainerView.snp.bottom).offset(30)
            make.leading.trailing.equalTo(contentView)
            make.height.equalTo(400)
        }
        
        recentFilesTableView.snp.makeConstraints { make in
            make.top.equalTo(subjectsCollectionView.snp.bottom).offset(20)
            make.leading.trailing.equalTo(contentView)
            make.bottom.equalTo(contentView).offset(-20)
            make.height.equalTo(currentRecentFilesHeight)
        }
    }
    
    private func createSubjectsLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self = self else { return nil }
            
            // 文档项目大小
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(70)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
            
            // 组大小
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(78) // 70 + 8间距
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            
            // 节
            let section = NSCollectionLayoutSection(group: group)
            
            // 动态设置section间距
            let groupsToUse = self.isSearching ? self.filteredGroups : self.subjectGroups
            let isLastSection = sectionIndex == groupsToUse.count - 1
            let bottomInset: CGFloat = isLastSection ? 16 : 16
            
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: 0,
                bottom: bottomInset,
                trailing: 0
            )
            
            // 节头
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(60)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            
            return section
        }
        
        return layout
    }
    
    // MARK: - 数据加载
    private func loadData() {
        markdownFiles = fileManager.getAllMarkdownFiles()
        organizeSubjectGroups()
        updateRecentFiles()
        updateStatsView()
        
        DispatchQueue.main.async {
            self.subjectsCollectionView.reloadData()
            self.recentFilesTableView.reloadData()
            // 初始加载时不使用动画
            self.updateCollectionViewHeight(animated: false)
            self.updateRecentFilesHeight(animated: false)
            
            // 只有在不是下拉刷新触发的情况下才结束刷新控件
            if !self.refreshControl.isRefreshing {
                // 这是普通的数据加载，不需要处理刷新控件
            }
        }
    }
    
    private func organizeSubjectGroups() {
        // 加载保存的分组状态
        let savedStates = loadGroupStates()
        
        // 按学科分组
        let groupedFiles = Dictionary(grouping: markdownFiles) { file in
            let pathComponents = file.relativePath.components(separatedBy: "/")
            if pathComponents.count >= 2 && pathComponents[0] == "datas" {
                return pathComponents[1]
            }
            return "其他"
        }
        
        subjectGroups = []
        for (subject, files) in groupedFiles {
            if !files.isEmpty {
                let sortedFiles = files.sorted { $0.displayName < $1.displayName }
                let (iconName, gradientColors) = getSubjectStyle(for: subject)
                
                // 恢复之前保存的展开状态，如果没有保存过则默认为展开
                let isExpanded = savedStates[subject] ?? true
                
                let group = SubjectGroup(
                    title: subject,
                    files: sortedFiles,
                    iconName: iconName,
                    gradientColors: gradientColors,
                    isExpanded: isExpanded
                )
                subjectGroups.append(group)
            }
        }
        
        // 按优先级排序
        subjectGroups.sort { group1, group2 in
            let priority1 = getSubjectPriority(for: group1.title)
            let priority2 = getSubjectPriority(for: group2.title)
            
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return group1.title < group2.title
        }
        
        filteredGroups = subjectGroups
    }
    
    private func getSubjectStyle(for subject: String) -> (String, [UIColor]) {
        switch subject {
        case "高数":
            return ("x.squareroot", [.systemOrange, .systemRed])
        case "数据结构算法":
            return ("function", [.systemPurple, .systemIndigo])
        case "计算机组成原理":
            return ("cpu", [.systemRed, .systemPink])
        case "其他":
            return ("folder.fill", [.systemGray, .systemGray2])
        default:
            let colors: [[UIColor]] = [
                [.systemBlue, .systemCyan],
                [.systemGreen, .systemMint],
                [.systemTeal, .systemBlue],
                [.systemYellow, .systemOrange],
                [.systemPink, .systemPurple]
            ]
            let index = abs(subject.hashValue) % colors.count
            return ("book.fill", colors[index])
        }
    }
    
    private func getSubjectPriority(for subject: String) -> Int {
        switch subject {
        case "高数": return 1
        case "计算机组成原理": return 2
        case "数据结构算法": return 3
        case "其他": return 100
        default: return 50
        }
    }
    
    private func updateRecentFiles() {
        // 从RecentFileManager获取真实的最近访问记录
        recentFiles = recentFileManager.getRecentFiles()
    }
    
    private func updateStatsView() {
        let totalFiles = markdownFiles.count
        let totalSize = markdownFiles.reduce(0) { $0 + $1.size }
        let subjectCount = subjectGroups.count
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        let formattedSize = formatter.string(fromByteCount: totalSize)
        
        // 更新统计卡片
        guard let stackView = statsContainerView.subviews.first as? UIStackView,
              stackView.arrangedSubviews.count >= 3 else {
            print("统计视图结构不正确")
            return
        }
        
        // 更新总文档数
        if let totalFilesCard = stackView.arrangedSubviews[0] as? StatsCardView {
            totalFilesCard.updateValue("\(totalFiles)")
        }
        
        // 更新总大小
        if let totalSizeCard = stackView.arrangedSubviews[1] as? StatsCardView {
            totalSizeCard.updateValue(formattedSize)
        }
        
        // 更新学科数
        if let subjectsCard = stackView.arrangedSubviews[2] as? StatsCardView {
            subjectsCard.updateValue("\(subjectCount)")
        }
    }
    
    // MARK: - 搜索功能
    private func performSearch(with searchText: String) {
        currentSearchText = searchText
        
        if searchText.isEmpty {
            // 清空搜索
            isSearching = false
            searchResults.removeAll()
            showNormalView()
        } else {
            // 执行搜索
            isSearching = true
            searchResults = searchMarkdownFiles(with: searchText)
            showSearchResults()
        }
    }
    
    private func searchMarkdownFiles(with searchText: String) -> [MarkdownFile] {
        let lowercasedSearchText = searchText.lowercased()
        
        return markdownFiles.filter { file in
            // 搜索完整文件名（包含扩展名）
            let fullFileName = file.displayName.lowercased()
            let fullFileNameMatch = fullFileName.contains(lowercasedSearchText)
            
            // 搜索不带扩展名的文件名（直接使用displayName，它已经是去掉扩展名的）
            let fileNameWithoutExtension = file.displayName.lowercased()
            let fileNameWithoutExtensionMatch = fileNameWithoutExtension.contains(lowercasedSearchText)
            
            // 搜索学科名称
            let pathComponents = file.relativePath.components(separatedBy: "/")
            let subjectName = pathComponents.count >= 2 && pathComponents[0] == "datas" ? pathComponents[1] : "其他"
            let subjectMatch = subjectName.lowercased().contains(lowercasedSearchText)
            
            return fullFileNameMatch || fileNameWithoutExtensionMatch || subjectMatch
        }.sorted { file1, file2 in
            // 优先显示文件名匹配的结果
            let file1FullNameMatch = file1.displayName.lowercased().contains(lowercasedSearchText)
            let file1NameMatch = file1.displayName.lowercased().contains(lowercasedSearchText)
            let file1AnyNameMatch = file1FullNameMatch || file1NameMatch
            
            let file2FullNameMatch = file2.displayName.lowercased().contains(lowercasedSearchText)
            let file2NameMatch = file2.displayName.lowercased().contains(lowercasedSearchText)
            let file2AnyNameMatch = file2FullNameMatch || file2NameMatch
            
            if file1AnyNameMatch && !file2AnyNameMatch {
                return true
            } else if !file1AnyNameMatch && file2AnyNameMatch {
                return false
        } else {
                return file1.displayName < file2.displayName
            }
        }
    }
    
    private func showSearchResults() {
        let hasResults = !searchResults.isEmpty
        
        UIView.animate(withDuration: 0.3) {
            self.subjectsCollectionView.isHidden = true
            self.recentFilesTableView.isHidden = true
            self.searchResultsTableView.isHidden = !hasResults
            self.emptySearchView.isHidden = hasResults
        }
        
        if hasResults {
            searchResultsTableView.reloadData()
        }
    }
    
    private func showNormalView() {
        filteredGroups = subjectGroups
        
        // 先更新数据和高度
        subjectsCollectionView.reloadData()
        recentFilesTableView.reloadData()
        updateCollectionViewHeight(animated: false)
        updateRecentFilesHeight(animated: false)
        
        UIView.animate(withDuration: 0.3) {
            self.subjectsCollectionView.isHidden = false
            self.recentFilesTableView.isHidden = false
            self.searchResultsTableView.isHidden = true
            self.emptySearchView.isHidden = true
        }
    }
    
    // MARK: - 高度计算
    private func updateCollectionViewHeight(animated: Bool = true) {
        let newHeight = calculateCollectionViewContentHeight()
        
        // 避免不必要的更新
        if abs(currentCollectionViewHeight - newHeight) < 1.0 {
            return
        }
        
        currentCollectionViewHeight = newHeight
        
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.subjectsCollectionView.snp.updateConstraints { make in
                    make.height.equalTo(newHeight)
                }
                self.view.layoutIfNeeded()
            }
        } else {
            subjectsCollectionView.snp.updateConstraints { make in
                make.height.equalTo(newHeight)
            }
        }
        
        print("📏 更新CollectionView高度: \(newHeight)")
    }
    
    private func calculateCollectionViewContentHeight() -> CGFloat {
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        
        // 如果没有数据，返回最小高度
        guard !groupsToUse.isEmpty else {
            return 100
        }
        
        var totalHeight: CGFloat = 0
        
        for (sectionIndex, group) in groupsToUse.enumerated() {
            // Section header高度
            totalHeight += 60
            
            if group.isExpanded && !group.files.isEmpty {
                // 计算展开状态下的实际内容高度
                let itemCount = group.files.count
                let itemHeight: CGFloat = 78 // 每个item的实际高度（70 + 8间距）
                
                totalHeight += CGFloat(itemCount) * itemHeight
            }
            
            // 最后一个section不需要底部间距
            if sectionIndex < groupsToUse.count - 1 {
                totalHeight += 16 // section间距
            }
        }
        
        // 添加顶部和底部的内容边距
        totalHeight += 32 // 16 + 16
        
        return totalHeight
    }
    
    private func updateRecentFilesHeight(animated: Bool = true) {
        let hasRecentFiles = !recentFiles.isEmpty
        let newHeight: CGFloat = hasRecentFiles ? calculateRecentFilesHeight() : 0
        
        // 避免不必要的更新
        if abs(currentRecentFilesHeight - newHeight) < 1.0 {
            return
        }
        
        currentRecentFilesHeight = newHeight
        
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.recentFilesTableView.snp.updateConstraints { make in
                    make.height.equalTo(newHeight)
                }
                self.recentFilesTableView.alpha = hasRecentFiles ? 1.0 : 0.0
                self.view.layoutIfNeeded()
            }
        } else {
            recentFilesTableView.snp.updateConstraints { make in
                make.height.equalTo(newHeight)
            }
            recentFilesTableView.alpha = hasRecentFiles ? 1.0 : 0.0
        }
        
        print("更新最近访问高度: \(newHeight)")
    }
    
    private func calculateRecentFilesHeight() -> CGFloat {
        guard !recentFiles.isEmpty else { return 0 }
        
        // 计算表格高度：头部 + 行数 * 行高 + 间距
        let headerHeight: CGFloat = 44
        let rowHeight: CGFloat = 92 // 新设计的行高（80 + 12间距）
        let numberOfRows = min(recentFiles.count, 5) // 最多显示5行
        let totalRowsHeight = CGFloat(numberOfRows) * rowHeight
        let sectionSpacing: CGFloat = 20
        
        return headerHeight + totalRowsHeight + sectionSpacing
    }
    
    // MARK: - 事件处理
    @objc private func refreshData() {
        // 执行下拉刷新同步
        performPullToRefreshSync()
    }
    
    /// 执行下拉刷新同步
    private func performPullToRefreshSync() {
        cloudSyncManager.pullToRefreshSync { [weak self] success, message in
            DispatchQueue.main.async {
                self?.refreshControl.endRefreshing()
                
                if success {
                    // 重新加载数据
                    self?.loadData()
                    
                    // 显示成功提示
                    if let message = message {
                        self?.showRefreshToast(message: message, isSuccess: true)
                    }
                } else {
                    // 显示错误提示
                    if let message = message {
                        self?.showRefreshToast(message: message, isSuccess: false)
                    }
                }
            }
        }
    }
    
    /// 显示刷新结果提示
    private func showRefreshToast(message: String, isSuccess: Bool) {
        if isSuccess {
            showSuccessToast(message)
        } else {
            showErrorToast(message)
        }
    }
    
    @objc private func themeButtonTapped() {
        // 切换主题
        ThemeManager.shared.toggleTheme()
    }
    
    @objc private func themeDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let theme = userInfo["theme"] as? UIUserInterfaceStyle else {
            return
        }
        
        print("FileListViewController 主题已变化为: \(theme == .dark ? "深色" : "浅色")")
        
        // 更新主题按钮图标
        updateThemeButtonIcon()
    }
    
    private func updateThemeButtonIcon() {
        // 更新主题按钮图标
        let currentTheme = ThemeManager.shared.getCurrentTheme()
        let imageName = (currentTheme == .dark) ? "sun.max" : "moon"
        themeButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    @objc private func syncButtonTapped() {
        showSyncActionSheet()
    }
    
    @objc private func importButtonTapped() {
        showImportActionSheet()
    }
    
    private func openFile(_ file: MarkdownFile) {
        // 添加到最近访问记录
        recentFileManager.addRecentFile(file)
        
        // 调试信息
        print("打开文件: \(file.displayName)")
        print("  - 文件路径: \(file.url.path)")
        print("  - 是否为图片: \(isImageFile(file))")
        print("  - 是否为XMind: \(isXMindFile(file))")
        
        // 检查文件类型并打开相应的查看器
        if isImageFile(file) {
            print("  - 打开图片查看器")
            openImageViewer(for: file)
        } else if isXMindFile(file) {
            print("  - 打开XMind查看器")
            openXMindViewer(for: file)
        } else {
            print("  - 打开Markdown阅读器")
            // 打开Markdown阅读器
            let readerVC = MarkdownReaderViewController()
            readerVC.markdownFile = file
            navigationController?.pushViewController(readerVC, animated: true)
        }
    }
    
    /// 检查是否是图片文件
    private func isImageFile(_ file: MarkdownFile) -> Bool {
        let filePath = file.url.path.lowercased()
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp"]
        
        // 检查文件路径是否包含images目录或文件扩展名
        return filePath.contains("/images/") || imageExtensions.contains { filePath.hasSuffix($0) }
    }
    
    /// 检查是否是XMind文件
    private func isXMindFile(_ file: MarkdownFile) -> Bool {
        let filePath = file.url.path.lowercased()
        return filePath.hasSuffix(".xmind")
    }
    
    /// 打开XMind查看器 - 提供选择
    private func openXMindViewer(for file: MarkdownFile) {
        let alertController = UIAlertController(
            title: "打开XMind文件", 
            message: "选择查看方式", 
            preferredStyle: .actionSheet
        )
        
        // 使用XMind应用打开
        let xmindAppAction = UIAlertAction(title: "使用XMind应用打开", style: .default) { [weak self] _ in
            self?.openWithXMindApp(file: file)
        }
        xmindAppAction.setValue(UIImage(systemName: "app.badge"), forKey: "image")
        
        // 使用内置预览器打开
        let previewAction = UIAlertAction(title: "应用内预览", style: .default) { [weak self] _ in
            self?.openWithInternalViewer(file: file)
        }
        previewAction.setValue(UIImage(systemName: "eye"), forKey: "image")
        

        
        // 取消
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(xmindAppAction)
        alertController.addAction(previewAction)
        alertController.addAction(cancelAction)
        
        // 设置iPad的popover
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alertController, animated: true)
    }
    

    
    /// 使用XMind应用打开文件
    private func openWithXMindApp(file: MarkdownFile) {
        // 检查是否安装了XMind应用
        if let xmindURL = URL(string: "xmind://") {
            if UIApplication.shared.canOpenURL(xmindURL) {
                // 智能处理不同来源的文件
                openFileWithSmartHandling(file: file)
            } else {
                // XMind应用未安装，提示用户
                showXMindNotInstalledAlert(file: file)
            }
        } else {
            // 无法创建XMind URL，使用分享菜单
            presentShareSheet(for: file)
        }
    }
    
    /// 智能处理文件打开 - 自动处理不同来源的文件
    private func openFileWithSmartHandling(file: MarkdownFile) {
        // 显示统一的加载提示
        let loadingAlert = UIAlertController(title: "正在打开", message: "正在准备XMind文件...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let fileURL: URL
                
                // 根据文件来源智能处理
                switch file.source {
                case .bundle:
                    // Bundle文件需要复制到共享目录
                    fileURL = try self?.copyFileToSharedDirectory(file: file) ?? file.url
                case .documents:
                    // Documents文件可以直接使用
                    fileURL = file.url
                }
                
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        // 使用处理后的文件URL打开
                        self?.openFileWithDocumentController(fileURL)
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.showErrorToast("准备文件失败：\(error.localizedDescription)")
                        // 降级到应用内预览
                        self?.openWithInternalViewer(file: file)
                    }
                }
            }
        }
    }
    
    /// 复制文件到临时目录 - 使用系统推荐的文件共享方式
    private func copyFileToSharedDirectory(file: MarkdownFile) throws -> URL {
        // 使用系统临时目录，这是iOS推荐的应用间文件共享位置
        let tempDir = FileManager.default.temporaryDirectory
        let appTempDir = tempDir.appendingPathComponent("XMindShare_\(ProcessInfo.processInfo.processIdentifier)")
        
        // 创建应用特定的临时目录
        try FileManager.default.createDirectory(at: appTempDir, withIntermediateDirectories: true)
        
        // 使用原始文件名，确保XMind能够正确识别
        let sharedFileURL = appTempDir.appendingPathComponent(file.displayName)
        
        // 如果文件已存在，先删除
        if FileManager.default.fileExists(atPath: sharedFileURL.path) {
            try FileManager.default.removeItem(at: sharedFileURL)
        }
        
        try FileManager.default.copyItem(at: file.url, to: sharedFileURL)
        
        // 设置文件属性，确保外部应用可以读取
        let attributes = [FileAttributeKey.posixPermissions: 0o644]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: sharedFileURL.path)
        
        print("文件已复制到临时共享目录: \(sharedFileURL.path)")
        print("  - 文件大小: \(getFileSize(sharedFileURL))")
        print("  - 文件存在: \(FileManager.default.fileExists(atPath: sharedFileURL.path))")
        
        return sharedFileURL
    }
    

    
    /// 使用文档交互控制器打开文件
    private func openFileWithDocumentController(_ fileURL: URL) {
        // 验证文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            showErrorToast("文件不存在：\(fileURL.path)")
            return
        }
        
        print("🔍 尝试使用改进的文件共享方式打开XMind文件")
        print("  - 文件路径: \(fileURL.path)")
        print("  - 文件大小: \(getFileSize(fileURL))")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 使用UIActivityViewController而不是UIDocumentInteractionController
            // 这是iOS推荐的文件共享方式，成功率更高
            self.presentActivityViewController(with: fileURL, preferXMind: true)
        }
    }
    
    /// 获取文件大小
    private func getFileSize(_ url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[FileAttributeKey.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            print("获取文件大小失败: \(error)")
            }
        return "未知"
    }
    
    /// 尝试使用URL scheme打开文件
    private func tryOpenWithURLScheme(_ fileURL: URL) -> Bool {
        // 注意：大多数iOS应用（包括XMind）不支持直接通过URL scheme打开文件
        // 这里保留逻辑但会优先使用文档交互控制器
        
        // 尝试多种XMind URL schemes
        let schemes = [
            "xmind://",
            "com.xmind.zen://",
            "com.xmind.mindmap://"
        ]
        
        for scheme in schemes {
            if let schemeURL = URL(string: scheme) {
                if UIApplication.shared.canOpenURL(schemeURL) {
                    // 尝试直接打开XMind应用（不传递文件）
                    // 用户需要手动导入文件
                    UIApplication.shared.open(schemeURL) { success in
                            if success {
                            print("成功打开XMind应用: \(scheme)")
                            print("注意：文件已准备在共享目录，用户需要手动导入")
                            } else {
                            print("打开XMind应用失败: \(scheme)")
                            }
                        }
                    return false // 返回false继续使用文档交互控制器
                }
            }
        }
        
        return false
    }
    
    /// 使用内置查看器打开文件
    private func openWithInternalViewer(file: MarkdownFile) {
        let xmindViewerVC = XMindViewerViewController()
        xmindViewerVC.xmindFile = file
        let navController = UINavigationController(rootViewController: xmindViewerVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    /// 显示XMind应用未安装的提示
    private func showXMindNotInstalledAlert(file: MarkdownFile) {
        let alert = UIAlertController(
            title: "XMind应用未安装",
            message: "检测到您的设备上未安装XMind应用。\n\n为了获得最佳的思维导图体验，建议您：\n\n1. 前往App Store下载XMind\n2. 使用其他应用打开\n3. 使用应用内预览",
            preferredStyle: .alert
        )
        
        // 前往App Store
        let appStoreAction = UIAlertAction(title: "前往App Store", style: .default) { _ in
            if let appStoreURL = URL(string: "https://apps.apple.com/app/xmind-mind-mapping/id1327661892") {
                UIApplication.shared.open(appStoreURL)
            }
        }
        
        // 使用其他应用打开
        let shareAction = UIAlertAction(title: "使用其他应用打开", style: .default) { [weak self] _ in
            self?.presentShareSheet(for: file)
        }
        
        // 应用内预览
        let previewAction = UIAlertAction(title: "应用内预览", style: .default) { [weak self] _ in
            self?.openWithInternalViewer(file: file)
        }
        
        // 取消
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alert.addAction(appStoreAction)
        alert.addAction(shareAction)
        alert.addAction(previewAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    /// 显示系统分享菜单
    private func presentShareSheet(for file: MarkdownFile) {
        // 智能处理不同来源的文件分享
        let loadingAlert = UIAlertController(title: "准备分享", message: "正在准备文件...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let fileURL: URL
                
                // 根据文件来源智能处理
                switch file.source {
                case .bundle:
                    // Bundle文件需要复制到共享目录
                    fileURL = try self?.copyFileToSharedDirectory(file: file) ?? file.url
                case .documents:
                    // Documents文件可以直接使用
                    fileURL = file.url
                }
                
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        // 使用处理后的文件URL分享
                        self?.presentActivityViewController(with: fileURL)
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.showErrorToast("准备文件失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /// 显示活动视图控制器
    private func presentActivityViewController(with fileURL: URL, preferXMind: Bool = false) {
        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        // 如果是专门为XMind优化，设置标题
        if preferXMind {
            activityVC.setValue("在XMind中打开", forKey: "subject")
        }
        
        // 设置完成处理程序
        activityVC.completionWithItemsHandler = { [weak self] (activityType: UIActivity.ActivityType?, completed: Bool, returnedItems: [Any]?, error: Error?) in
            if let error = error {
                print("分享失败: \(error.localizedDescription)")
                self?.showErrorToast("分享失败: \(error.localizedDescription)")
            } else if completed {
                print("分享成功: \(activityType?.rawValue ?? "未知应用")")
                if let activityType = activityType {
                    self?.handleShareSuccess(activityType: activityType)
                }
            } else {
                print("用户取消分享")
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
    
    /// 处理分享成功
    private func handleShareSuccess(activityType: UIActivity.ActivityType) {
        let activityString = activityType.rawValue
        
        if activityString.lowercased().contains("xmind") {
            showSuccessToast("文件已成功发送到XMind应用")
        } else {
            showSuccessToast("文件已成功分享到外部应用")
        }
    }
    
    /// 打开图片查看器
    private func openImageViewer(for file: MarkdownFile) {
        // 使用原生图片查看器显示图片
        if let image = UIImage(contentsOfFile: file.url.path) {
            let imageViewer = NativeImageViewer(image: image)
            self.present(imageViewer, animated: true)
        }
    }
    
    private func openSubject(_ group: SubjectGroup) {
        let subjectVC = SubjectDetailViewController()
        subjectVC.subjectGroup = group
        navigationController?.pushViewController(subjectVC, animated: true)
    }
    
    // MARK: - 同步功能
    private func showSyncActionSheet() {
        let alertController = UIAlertController(title: "iCloud同步", message: nil, preferredStyle: .actionSheet)
        
        // 检查同步状态
        let syncStatus = cloudSyncManager.checkSyncStatus()
        let _ = syncStatus.message
        
        // 同步到iCloud
        let syncAction = UIAlertAction(title: "同步到iCloud", style: .default) { [weak self] _ in
            self?.performiCloudSync()
        }
        
        // 查看状态
        let statusAction = UIAlertAction(title: "查看状态", style: .default) { [weak self] _ in
            self?.showSyncStatus()
        }
        
        // 取消
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(syncAction)
        alertController.addAction(statusAction)
        alertController.addAction(cancelAction)
        
        // 设置iPad的popover
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = syncButton
            popover.sourceRect = syncButton.bounds
        }
        
        present(alertController, animated: true)
    }
    
    private func performiCloudSync() {
        // 显示加载指示器
        let loadingAlert = UIAlertController(title: "正在同步", message: "正在将文档同步到iCloud...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        cloudSyncManager.syncAllDocumentsToiCloud { [weak self] success, message in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    self?.showSyncResult(success: success, message: message)
                }
            }
        }
    }
    
    private func showSyncStatus() {
        let syncStatus = cloudSyncManager.checkSyncStatus()
        let title = syncStatus.isAvailable ? "同步状态" : "iCloud不可用"
        
        let alert = UIAlertController(title: title, message: syncStatus.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    private func showSyncResult(success: Bool, message: String?) {
        let displayMessage = message ?? (success ? "同步成功" : "同步失败")
        if success {
            showSuccessToast(displayMessage)
        } else {
            showErrorToast(displayMessage)
        }
    }
    

    
    // MARK: - 导入功能
    private func showImportActionSheet() {
        let alertController = UIAlertController(title: "导入文件", message: "选择要导入的文件类型", preferredStyle: .actionSheet)
        
        // 从文件导入
        let importAction = UIAlertAction(title: "从文件导入", style: .default) { [weak self] _ in
            self?.performFileImport()
        }
        
        // 查看支持的格式
        let formatsAction = UIAlertAction(title: "支持的格式", style: .default) { [weak self] _ in
            self?.showSupportedFormats()
        }
        
        // 取消
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(importAction)
        alertController.addAction(formatsAction)
        alertController.addAction(cancelAction)
        
        // 设置iPad的popover
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = importButton
            popover.sourceRect = importButton.bounds
        }
        
        present(alertController, animated: true)
    }
    
    private func performFileImport() {
        fileImportManager.presentFileImporter(from: self) { [weak self] success, message in
            DispatchQueue.main.async {
                self?.showImportResult(success: success, message: message)
                if success {
                    // 重新加载数据以显示新导入的文件
                    self?.loadData()
                }
            }
        }
    }
    
    private func showSupportedFormats() {
        let formats = fileImportManager.getSupportedFileTypes()
        let message = "\n\n" + formats.joined(separator: "\n")
        
        let alert = UIAlertController(title: "支持的文件格式", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    private func showImportResult(success: Bool, message: String?) {
        let displayMessage = message ?? (success ? "导入成功" : "导入失败")
        if success {
            showSuccessToast(displayMessage)
        } else {
            showErrorToast(displayMessage)
        }
    }
    
    // MARK: - 删除功能
    
    /// 创建删除上下文菜单
    private func createDeleteContextMenu(for file: MarkdownFile, at indexPath: IndexPath, in collectionView: UICollectionView) -> UIMenu {
        var actions: [UIAction] = []
        
        if file.source == .documents {
            // Documents文件可以删除本地和iCloud
            let deleteLocalAction = UIAction(
                title: "删除本地文件",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.deleteFile(file, deleteFromiCloud: false, at: indexPath, in: collectionView)
            }
            
            let deleteBothAction = UIAction(
                title: "删除本地和iCloud文件",
                image: UIImage(systemName: "trash.fill"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.deleteFile(file, deleteFromiCloud: true, at: indexPath, in: collectionView)
            }
            
            actions = [deleteLocalAction, deleteBothAction]
        } else {
            // Bundle文件只能删除iCloud副本
            let deleteiCloudAction = UIAction(
                title: "删除iCloud副本",
                image: UIImage(systemName: "icloud.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.deleteFile(file, deleteFromiCloud: true, at: indexPath, in: collectionView)
            }
            
            actions = [deleteiCloudAction]
        }
        
        let menuTitle = file.source == .bundle ? "Bundle文件选项" : "删除选项"
        return UIMenu(title: menuTitle, children: actions)
    }
    
    /// 显示删除选项ActionSheet
    private func showDeleteActionSheet(for file: MarkdownFile, from tableView: UITableView, at indexPath: IndexPath) {
        let title: String
        let message: String
        
        if file.source == .bundle {
            title = "Bundle文件操作"
            message = "Bundle文件无法删除，只能删除iCloud副本"
        } else {
            title = "删除文件"
            message = "选择删除方式"
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        
        if file.source == .documents {
            // Documents文件可以删除本地文件或仅删除iCloud副本
            let deleteLocalAction = UIAlertAction(title: "删除本地文件", style: .destructive) { [weak self] _ in
                self?.deleteFile(file, deleteFromiCloud: false, from: tableView, at: indexPath)
            }
            
            let deleteiCloudOnlyAction = UIAlertAction(title: "仅删除iCloud副本", style: .default) { [weak self] _ in
                self?.deleteiCloudCopyOnly(file, from: tableView, at: indexPath)
            }
            
            alertController.addAction(deleteLocalAction)
            alertController.addAction(deleteiCloudOnlyAction)
        } else {
            // Bundle文件只能删除iCloud副本
            let deleteiCloudAction = UIAlertAction(title: "删除iCloud副本", style: .destructive) { [weak self] _ in
                self?.deleteiCloudCopyOnly(file, from: tableView, at: indexPath)
            }
            
            alertController.addAction(deleteiCloudAction)
        }
        
        // 取消
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        alertController.addAction(cancelAction)
        
        // 设置iPad的popover
        if let popover = alertController.popoverPresentationController {
            let cell = tableView.cellForRow(at: indexPath)
            popover.sourceView = cell
            popover.sourceRect = cell?.bounds ?? CGRect.zero
        }
        
        present(alertController, animated: true)
    }
    
    /// 删除文件（从CollectionView）
    private func deleteFile(_ file: MarkdownFile, deleteFromiCloud: Bool, at indexPath: IndexPath, in collectionView: UICollectionView) {
        // 显示确认对话框
        let title = deleteFromiCloud ? "删除本地和iCloud文件" : "删除本地文件"
        let message = "确定要删除文件「\(file.displayName)」吗？"
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let deleteAction = UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.performFileDelete(file, deleteFromiCloud: deleteFromiCloud)
        }
        
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(deleteAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    /// 删除文件（从TableView）
    private func deleteFile(_ file: MarkdownFile, deleteFromiCloud: Bool, from tableView: UITableView, at indexPath: IndexPath) {
        // 显示确认对话框
        let title = deleteFromiCloud ? "删除本地和iCloud文件" : "删除本地文件"
        let message = "确定要删除文件「\(file.displayName)」吗？"
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let deleteAction = UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.performFileDelete(file, deleteFromiCloud: deleteFromiCloud)
        }
        
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(deleteAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    /// 执行文件删除
    private func performFileDelete(_ file: MarkdownFile, deleteFromiCloud: Bool) {
        cloudSyncManager.deleteFile(file, deleteFromiCloud: deleteFromiCloud) { [weak self] success, message in
            DispatchQueue.main.async {
                if success {
                    // 删除成功，更新数据和UI
                    self?.handleFileDeleteSuccess(file, message: message)
                } else {
                    // 删除失败，显示错误信息
                    self?.showErrorToast(message ?? "删除失败")
                }
            }
        }
    }
    
    /// 仅删除iCloud副本
    private func deleteiCloudCopyOnly(_ file: MarkdownFile, from tableView: UITableView, at indexPath: IndexPath) {
        // 显示确认对话框
        let message = "确定要删除文件「\(file.displayName)」的iCloud副本吗？本地文件将保留。"
        
        let alertController = UIAlertController(title: "删除iCloud副本", message: message, preferredStyle: .alert)
        
        let deleteAction = UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.performiCloudOnlyDelete(file)
        }
        
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(deleteAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    /// 执行仅删除iCloud副本
    private func performiCloudOnlyDelete(_ file: MarkdownFile) {
        // 暂时使用现有的删除方法，但只删除iCloud副本
        cloudSyncManager.deleteFile(file, deleteFromiCloud: true) { [weak self] success, message in
            DispatchQueue.main.async {
                if success {
                    self?.showSuccessToast("iCloud副本删除成功")
                } else {
                    self?.showErrorToast(message ?? "删除iCloud副本失败")
                }
            }
        }
    }
    
    /// 处理文件删除成功
    private func handleFileDeleteSuccess(_ deletedFile: MarkdownFile, message: String?) {
        // 从最近访问记录中移除
        recentFileManager.removeRecentFile(deletedFile)
        
        // 重新加载数据
        loadData()
        
        // 显示成功提示
        showSuccessToast(message ?? "删除成功")
    }
    
    // MARK: - Toast 提示方法
    private func showSuccessToast(_ message: String) {
        ToastManager.shared.showSuccess(message, in: view)
    }
    
    private func showErrorToast(_ message: String) {
        ToastManager.shared.showError(message, in: view)
    }
    
    private func showInfoToast(_ message: String) {
        ToastManager.shared.showInfo(message, in: view)
    }
}

// MARK: - UICollectionViewDataSource
extension FileListViewController: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        return groupsToUse.count
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        let group = groupsToUse[section]
        return group.isExpanded ? group.files.count : 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DocumentCell.identifier, for: indexPath) as! DocumentCell
        
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        let group = groupsToUse[indexPath.section]
            let file = group.files[indexPath.row]
            cell.configure(with: file)
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.identifier, for: indexPath) as! SectionHeaderView
        
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        let group = groupsToUse[indexPath.section]
        header.configure(with: group) { [weak self] in
            self?.toggleSection(indexPath.section)
        }
        
        return header
    }
}

// MARK: - UICollectionViewDelegate
extension FileListViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        let group = groupsToUse[indexPath.section]
        let file = group.files[indexPath.row]
        openFile(file)
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        let group = groupsToUse[indexPath.section]
        let file = group.files[indexPath.row]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            return self.createDeleteContextMenu(for: file, at: indexPath, in: collectionView)
        }
    }
    
    private func toggleSection(_ section: Int) {
        let groupsToUse = isSearching ? filteredGroups : subjectGroups
        guard section < groupsToUse.count else { return }
        
        let group = groupsToUse[section]
        group.isExpanded.toggle()
        
        // 保存分组状态到UserDefaults
        if !isSearching {
            saveGroupStates()
        }
        
        // 先更新高度，再执行动画
        updateCollectionViewHeight(animated: true)
        
        subjectsCollectionView.performBatchUpdates({
            subjectsCollectionView.reloadSections(IndexSet(integer: section))
        }, completion: nil)
    }
}

// MARK: - UITableViewDataSource
extension FileListViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == searchResultsTableView {
            return searchResults.count
        } else {
            return recentFiles.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == searchResultsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.identifier, for: indexPath) as! SearchResultCell
            let file = searchResults[indexPath.row]
            cell.configure(with: file, searchText: currentSearchText)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: RecentFileCell.identifier, for: indexPath) as! RecentFileCell
            let file = recentFiles[indexPath.row]
            cell.configure(with: file)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView == searchResultsTableView {
            return !searchResults.isEmpty ? "搜索结果 (\(searchResults.count))" : nil
        } else {
            return recentFiles.isEmpty ? nil : "最近访问 (\(recentFiles.count))"
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}

// MARK: - UITableViewDelegate
extension FileListViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if tableView == searchResultsTableView {
            let file = searchResults[indexPath.row]
            openFile(file)
        } else {
            let file = recentFiles[indexPath.row]
            openFile(file)
        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // 最近访问列表不提供删除功能
        if tableView == recentFilesTableView {
            return nil
        }
        
        // 只有搜索结果列表提供删除功能
        if tableView == searchResultsTableView {
            let file = searchResults[indexPath.row]
            
            let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
                self?.showDeleteActionSheet(for: file, from: tableView, at: indexPath)
                completion(true)
            }
            
            deleteAction.image = UIImage(systemName: "trash")
            
            return UISwipeActionsConfiguration(actions: [deleteAction])
        }
        
        return nil
    }
}

// MARK: - UISearchBarDelegate
extension FileListViewController: UISearchBarDelegate {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        performSearch(with: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        performSearch(with: "")
    }
}

// MARK: - 文档单元格
class DocumentCell: UICollectionViewCell {
    
    static let identifier = "DocumentCell"
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = false
        
        // 添加轻微的阴影效果
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 3
        view.layer.shadowOpacity = 0.1
        
        return view
    }()
    
    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "doc.richtext.fill")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()
    
    // 移除箭头图标
    
    private lazy var fileTypeWatermarkLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .heavy)
        label.textColor = .systemGray4.withAlphaComponent(0.5)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.isUserInteractionEnabled = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupUI() {
        contentView.addSubview(containerView)
        
        // 添加水印标签到容器视图的背景
        containerView.addSubview(fileTypeWatermarkLabel)
        
        let textStackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStackView.axis = .vertical
        textStackView.spacing = 4
        textStackView.alignment = .leading
        
        let mainStackView = UIStackView(arrangedSubviews: [iconImageView, textStackView])
        mainStackView.axis = .horizontal
        mainStackView.spacing = 12
        mainStackView.alignment = .center
        
        containerView.addSubview(mainStackView)
        
        containerView.snp.makeConstraints { make in
            make.edges.equalTo(contentView)
        }
        
        fileTypeWatermarkLabel.snp.makeConstraints { make in
            make.trailing.equalTo(containerView).offset(-8)
            make.centerY.equalTo(containerView)
            make.width.lessThanOrEqualTo(120)
        }
        
        mainStackView.snp.makeConstraints { make in
            make.edges.equalTo(containerView).inset(UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        }
        
        iconImageView.snp.makeConstraints { make in
            make.size.equalTo(24)
        }
    }
    
    func configure(with file: MarkdownFile) {
        // 直接显示displayName，它已经是去掉扩展名的文件名
        titleLabel.text = file.displayName
        subtitleLabel.text = "\(file.formattedSize) • \(file.formattedDate)"
        
        // 根据文件类型设置图标
        let (iconName, iconColor) = getFileIcon(for: file)
        iconImageView.image = UIImage(systemName: iconName)
        iconImageView.tintColor = iconColor
        
        // 设置文件类型水印
        let fileExtension = getFileExtension(for: file)
        fileTypeWatermarkLabel.text = fileExtension
    }
    
    private func getFileIcon(for file: MarkdownFile) -> (String, UIColor) {
        let name = file.displayName.lowercased()
        let filePath = file.url.path.lowercased()
        
        // 检查文件类型
        if filePath.hasSuffix(".xmind") {
            return ("brain.head.profile", .systemPurple)
        } else if name.contains("基础") {
            return ("book.fill", .systemGreen)
        } else if name.contains("算法") {
            return ("function", .systemPurple)
        } else if name.contains("高数") || name.contains("数学") || name.contains("函数") || name.contains("导数") {
            return ("x.squareroot", .systemOrange)
        } else if name.contains("计算机") {
            return ("cpu", .systemRed)
        } else {
            return ("doc.richtext.fill", .systemBlue)
        }
    }
    
    private func getFileExtension(for file: MarkdownFile) -> String {
        // 直接从文件URL获取真实的文件扩展名
        let fileExtension = file.url.pathExtension.lowercased()
        
        // 如果有扩展名，直接返回
        if !fileExtension.isEmpty {
            return ".\(fileExtension)"
        }
        
        // 如果没有扩展名，检查文件路径来推断类型
        let filePath = file.url.path.lowercased()
        
        // 检查是否在images目录中
        if filePath.contains("/images/") {
            return ".img"
        }
        
        // 默认为Markdown文件
        return ".md"
    }
}

// MARK: - 节头视图
class SectionHeaderView: UICollectionReusableView {
    
    static let identifier = "SectionHeaderView"
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = .label
        return label
    }()
    
    private lazy var chevronImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.down"))
        imageView.tintColor = .systemGray2
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private var tapHandler: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, chevronImageView])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        
        addSubview(stackView)
        
        stackView.snp.makeConstraints { make in
            make.edges.equalTo(self).inset(UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20))
        }
        
        chevronImageView.snp.makeConstraints { make in
            make.size.equalTo(16)
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(headerTapped))
        addGestureRecognizer(tapGesture)
    }
    
    @objc private func headerTapped() {
        tapHandler?()
    }
    
    func configure(with group: SubjectGroup, tapHandler: @escaping () -> Void) {
        titleLabel.text = group.title
        self.tapHandler = tapHandler
        
        UIView.animate(withDuration: 0.3) {
            self.chevronImageView.transform = group.isExpanded ? 
                .identity : 
                CGAffineTransform(rotationAngle: -CGFloat.pi / 2)
        }
    }
}

// MARK: - 搜索结果单元格
class SearchResultCell: UITableViewCell {
    
    static let identifier = "SearchResultCell"
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        return view
    }()
    
    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "doc.richtext.fill")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        return label
    }()
    
    private lazy var subjectLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .systemBlue
        label.numberOfLines = 1
        return label
    }()
    
    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()
    
    private lazy var matchLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .systemGreen
        label.backgroundColor = .systemGreen.withAlphaComponent(0.1)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .center
        return label
    }()
    
    private lazy var fileTypeWatermarkLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 36, weight: .black)
        label.textColor = .systemGray5.withAlphaComponent(0.25)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.isUserInteractionEnabled = false
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        
        // 添加水印标签到容器视图的背景
        containerView.addSubview(fileTypeWatermarkLabel)
        
        let textStackView = UIStackView(arrangedSubviews: [titleLabel, subjectLabel, detailLabel])
        textStackView.axis = .vertical
        textStackView.spacing = 4
        textStackView.alignment = .leading
        
        let rightStackView = UIStackView(arrangedSubviews: [matchLabel])
        rightStackView.axis = .vertical
        rightStackView.alignment = .trailing
        
        let mainStackView = UIStackView(arrangedSubviews: [iconImageView, textStackView, rightStackView])
        mainStackView.axis = .horizontal
        mainStackView.spacing = 12
        mainStackView.alignment = .center
        
        containerView.addSubview(mainStackView)
        
        containerView.snp.makeConstraints { make in
            make.edges.equalTo(contentView).inset(UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        }
        
        fileTypeWatermarkLabel.snp.makeConstraints { make in
            make.trailing.equalTo(containerView).offset(-8)
            make.centerY.equalTo(containerView)
            make.width.lessThanOrEqualTo(100)
        }
        
        mainStackView.snp.makeConstraints { make in
            make.edges.equalTo(containerView).inset(12)
        }
        
        iconImageView.snp.makeConstraints { make in
            make.size.equalTo(28)
        }
        
        matchLabel.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(60)
            make.height.equalTo(24)
        }
    }
    
    func configure(with file: MarkdownFile, searchText: String) {
        // 直接使用displayName，它已经是去掉扩展名的文件名
        let fileNameWithoutExtension = file.displayName
        
        // 设置标题，高亮匹配的文本
        titleLabel.attributedText = highlightText(in: fileNameWithoutExtension, searchText: searchText)
        
        // 设置学科信息
            let pathComponents = file.relativePath.components(separatedBy: "/")
        let subjectName = pathComponents.count >= 2 && pathComponents[0] == "datas" ? pathComponents[1] : "其他"
        subjectLabel.text = "📁 \(subjectName)"
        
        // 设置详细信息
        detailLabel.text = "\(file.formattedSize) • \(file.formattedDate)"
        
        // 设置匹配类型标签（基于文件名进行匹配检测）
        let fullFileName = file.displayName.lowercased()
        let fileNameWithoutExtensionLower = fileNameWithoutExtension.lowercased()
        let searchTextLower = searchText.lowercased()
        
        let isFullFileNameMatch = fullFileName.contains(searchTextLower)
        let isFileNameWithoutExtensionMatch = fileNameWithoutExtensionLower.contains(searchTextLower)
        let isFileNameMatch = isFullFileNameMatch || isFileNameWithoutExtensionMatch
        
        matchLabel.text = isFileNameMatch ? "文件名匹配" : "学科匹配"
        
        // 根据文件类型设置图标
        let (iconName, iconColor) = getFileIcon(for: file)
        iconImageView.image = UIImage(systemName: iconName)
        iconImageView.tintColor = iconColor
        
        // 设置文件类型水印
        let fileExtension = getFileExtension(for: file)
        fileTypeWatermarkLabel.text = fileExtension
    }
    
    private func highlightText(in text: String, searchText: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: text.count)
        
        // 设置默认属性
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 16, weight: .medium), range: range)
        
        // 高亮匹配的文本
        let searchRange = (text.lowercased() as NSString).range(of: searchText.lowercased())
        if searchRange.location != NSNotFound {
            attributedString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: searchRange)
            attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: searchRange)
        }
        
        return attributedString
    }
    
    private func getFileIcon(for file: MarkdownFile) -> (String, UIColor) {
        let name = file.displayName.lowercased()
        let filePath = file.url.path.lowercased()
        
        // 检查文件类型
        if filePath.hasSuffix(".xmind") {
            return ("brain.head.profile", .systemPurple)
        } else if name.contains("基础") {
            return ("book.fill", .systemGreen)
        } else if name.contains("算法") {
            return ("function", .systemPurple)
        } else if name.contains("高数") || name.contains("数学") || name.contains("函数") || name.contains("导数") {
            return ("x.squareroot", .systemOrange)
        } else if name.contains("计算机") {
            return ("cpu", .systemRed)
        } else {
            return ("doc.richtext.fill", .systemBlue)
        }
    }
    
    private func getFileExtension(for file: MarkdownFile) -> String {
        // 直接从文件URL获取真实的文件扩展名
        let fileExtension = file.url.pathExtension.lowercased()
        
        // 如果有扩展名，直接返回
        if !fileExtension.isEmpty {
            return ".\(fileExtension)"
        }
        
        // 如果没有扩展名，检查文件路径来推断类型
        let filePath = file.url.path.lowercased()
        
        // 检查是否在images目录中
        if filePath.contains("/images/") {
            return ".img"
        }
        
        // 默认为Markdown文件
        return ".md"
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        UIView.animate(withDuration: 0.15) {
            self.containerView.backgroundColor = highlighted ? 
                .tertiarySystemGroupedBackground : 
                .secondarySystemGroupedBackground
            self.transform = highlighted ? 
                CGAffineTransform(scaleX: 0.98, y: 0.98) : 
                .identity
        }
    }
}

// MARK: - 最近文件单元格
class RecentFileCell: UITableViewCell {
    
    static let identifier = "RecentFileCell"
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = false
        
        // 添加阴影
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.layer.shadowOpacity = 0.1
        
        return view
    }()
    
    private lazy var gradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.cornerRadius = 16
        return gradient
    }()
    
    private lazy var iconContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        return view
    }()
    
    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "doc.richtext.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private lazy var timeContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        return view
    }()
    
    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()
    
    private lazy var accessoryImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "clock.fill"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private lazy var fileTypeWatermarkLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 32, weight: .black)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.isUserInteractionEnabled = false
        label.alpha = 0.2
        return label
    }()
    

    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        
        // 添加渐变背景
        containerView.layer.insertSublayer(gradientLayer, at: 0)
        
        // 添加图标容器
        containerView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconImageView)
        
        // 添加文本内容
        let textStackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStackView.axis = .vertical
        textStackView.spacing = 3
        textStackView.alignment = .leading
        
        containerView.addSubview(textStackView)
        
        // 添加时间容器
        containerView.addSubview(timeContainerView)
        timeContainerView.addSubview(accessoryImageView)
        timeContainerView.addSubview(timeLabel)
        
        // 添加水印标签到容器视图的背景 - 置于最底层
        containerView.insertSubview(fileTypeWatermarkLabel, at: 0)
        
        // 设置约束
        containerView.snp.makeConstraints { make in
            make.top.bottom.equalTo(contentView).inset(6)
            make.leading.trailing.equalTo(contentView).inset(12)
            make.height.equalTo(80)
        }
        
        fileTypeWatermarkLabel.snp.makeConstraints { make in
            make.leading.equalTo(containerView).offset(8)
            make.centerY.equalTo(containerView)
            make.width.lessThanOrEqualTo(60)
        }
        
        iconContainerView.snp.makeConstraints { make in
            make.leading.equalTo(containerView).offset(16)
            make.centerY.equalTo(containerView)
            make.size.equalTo(48)
        }
        
        iconImageView.snp.makeConstraints { make in
            make.center.equalTo(iconContainerView)
            make.size.equalTo(24)
        }
        
        textStackView.snp.makeConstraints { make in
            make.leading.equalTo(iconContainerView.snp.trailing).offset(16)
            make.centerY.equalTo(containerView)
            make.trailing.lessThanOrEqualTo(timeContainerView.snp.leading).offset(-12)
        }
        
        timeContainerView.snp.makeConstraints { make in
            make.trailing.equalTo(containerView).offset(-16)
            make.centerY.equalTo(containerView)
            make.width.equalTo(90)
            make.height.equalTo(32)
        }
        
        accessoryImageView.snp.makeConstraints { make in
            make.leading.equalTo(timeContainerView).offset(8)
            make.centerY.equalTo(timeContainerView)
            make.size.equalTo(12)
        }
        
        timeLabel.snp.makeConstraints { make in
            make.leading.equalTo(accessoryImageView.snp.trailing).offset(4)
            make.trailing.equalTo(timeContainerView).offset(-8)
            make.centerY.equalTo(timeContainerView)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = containerView.bounds
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTheme()
    }
    
    func configure(with file: MarkdownFile) {
        // 直接显示displayName，它已经是去掉扩展名的文件名
        titleLabel.text = file.displayName
        
        // 获取学科信息
        let pathComponents = file.relativePath.components(separatedBy: "/")
        let subjectName = pathComponents.count >= 2 && pathComponents[0] == "datas" ? pathComponents[1] : "其他"
        subtitleLabel.text = "\(subjectName) • \(file.formattedSize)"
        
        // 显示相对时间
        timeLabel.text = getRelativeTimeString(from: file.modificationDate)
        
        // 根据文件类型设置图标和颜色
        let (iconName, iconColor) = getFileIcon(for: file)
        iconImageView.image = UIImage(systemName: iconName)
        
        // 设置图标容器的渐变背景
        setupIconGradient(with: iconColor)
        
        // 设置文件类型水印
        let fileExtension = getFileExtension(for: file)
        fileTypeWatermarkLabel.text = fileExtension
        
        // 更新主题
        updateTheme()
    }
    
    private func setupIconGradient(with color: UIColor) {
        // 移除现有的渐变图层
        iconContainerView.layer.sublayers?.removeAll { $0 is CAGradientLayer }
        
        // 创建新的渐变图层
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        gradient.cornerRadius = 12
        gradient.colors = [
            color.cgColor,
            color.withAlphaComponent(0.8).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        
        iconContainerView.layer.insertSublayer(gradient, at: 0)
    }
    
    private func updateTheme() {
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        
        // 更新主背景渐变
        if isDarkMode {
            gradientLayer.colors = [
                UIColor.secondarySystemGroupedBackground.cgColor,
                UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.8).cgColor
            ]
            
            timeContainerView.backgroundColor = UIColor.tertiarySystemGroupedBackground
            timeLabel.textColor = UIColor.secondaryLabel
            accessoryImageView.tintColor = UIColor.secondaryLabel
            
            fileTypeWatermarkLabel.textColor = UIColor.systemGray3
            
            containerView.layer.shadowOpacity = 0.15
            containerView.layer.shadowColor = UIColor.black.cgColor
        } else {
            gradientLayer.colors = [
                UIColor.systemBackground.cgColor,
                UIColor.systemBackground.withAlphaComponent(0.95).cgColor
            ]
            
            timeContainerView.backgroundColor = UIColor.systemGray6
            timeLabel.textColor = UIColor.label
            accessoryImageView.tintColor = UIColor.label
            
            fileTypeWatermarkLabel.textColor = UIColor.systemGray3
            
            containerView.layer.shadowOpacity = 0.1
            containerView.layer.shadowColor = UIColor.black.cgColor
        }
        
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    }
    
    private func getRelativeTimeString(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)天前"
        } else {
        let formatter = DateFormatter()
            formatter.dateFormat = "MM.dd"
        return formatter.string(from: date)
        }
    }
    
    private func getFileIcon(for file: MarkdownFile) -> (String, UIColor) {
        let name = file.displayName.lowercased()
        let filePath = file.url.path.lowercased()
        
        // 检查文件类型
        if filePath.hasSuffix(".xmind") {
            return ("brain.head.profile", .systemPurple)
        } else if name.contains("基础") {
            return ("book.fill", .systemGreen)
        } else if name.contains("算法") {
            return ("function", .systemPurple)
        } else if name.contains("高数") || name.contains("数学") {
            return ("x.squareroot", .systemOrange)
        } else if name.contains("计算机") {
            return ("cpu", .systemRed)
        } else {
            return ("doc.richtext.fill", .systemBlue)
        }
    }
    
    private func getFileExtension(for file: MarkdownFile) -> String {
        // 直接从文件URL获取真实的文件扩展名
        let fileExtension = file.url.pathExtension.lowercased()
        
        // 如果有扩展名，直接返回
        if !fileExtension.isEmpty {
            return ".\(fileExtension)"
        }
        
        // 如果没有扩展名，检查文件路径来推断类型
        let filePath = file.url.path.lowercased()
        
        // 检查是否在images目录中
        if filePath.contains("/images/") {
            return ".img"
        }
        
        // 默认为Markdown文件
        return ".md"
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        let duration = animated ? 0.15 : 0.0
        
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            if highlighted {
                self.containerView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                self.containerView.alpha = 0.8
                self.containerView.layer.shadowOpacity = 0.2
                self.containerView.layer.shadowRadius = 12
            } else {
                self.containerView.transform = .identity
                self.containerView.alpha = 1.0
                let isDarkMode = self.traitCollection.userInterfaceStyle == .dark
                self.containerView.layer.shadowOpacity = isDarkMode ? 0.15 : 0.1
                self.containerView.layer.shadowRadius = 8
            }
        }
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        // 防止选中状态改变背景色
    }
}

// MARK: - 学科详情视图控制器
class SubjectDetailViewController: UIViewController {
    
    var subjectGroup: SubjectGroup?
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(RecentFileCell.self, forCellReuseIdentifier: RecentFileCell.identifier)
        return table
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        title = subjectGroup?.title
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalTo(view)
        }
    }
}

// MARK: - SubjectDetailViewController TableView
extension SubjectDetailViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return subjectGroup?.files.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RecentFileCell.identifier, for: indexPath) as! RecentFileCell
        
        if let file = subjectGroup?.files[indexPath.row] {
            cell.configure(with: file)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if let file = subjectGroup?.files[indexPath.row] {
            // 添加到最近访问记录
            RecentFileManager.shared.addRecentFile(file)
            
            // 检查文件类型并打开相应的查看器
            if isImageFile(file) {
                // 直接显示图片查看器
                if let image = UIImage(contentsOfFile: file.url.path) {
                    let imageViewer = NativeImageViewer(image: image)
                    present(imageViewer, animated: true)
                }
            } else if isXMindFile(file) {
                openXMindViewer(for: file)
            } else {
                // 打开Markdown阅读器
                let readerVC = MarkdownReaderViewController()
                readerVC.markdownFile = file
                navigationController?.pushViewController(readerVC, animated: true)
            }
        }
    }
    
    /// 检查是否是图片文件
    private func isImageFile(_ file: MarkdownFile) -> Bool {
        let filePath = file.url.path.lowercased()
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp"]
        
        // 检查文件路径是否包含images目录或文件扩展名
        return filePath.contains("/images/") || imageExtensions.contains { filePath.hasSuffix($0) }
    }
    
    /// 检查是否是XMind文件
    private func isXMindFile(_ file: MarkdownFile) -> Bool {
        let filePath = file.url.path.lowercased()
        return filePath.hasSuffix(".xmind")
    }
    
    /// 打开XMind查看器
    private func openXMindViewer(for file: MarkdownFile) {
        let xmindViewerVC = XMindViewerViewController()
        xmindViewerVC.xmindFile = file
        let navController = UINavigationController(rootViewController: xmindViewerVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let file = subjectGroup?.files[indexPath.row] else { return nil }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.showDeleteActionSheet(for: file, at: indexPath)
            completion(true)
        }
        
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    private func showDeleteActionSheet(for file: MarkdownFile, at indexPath: IndexPath) {
        let alertController = UIAlertController(title: "删除文件", message: "选择删除方式", preferredStyle: .actionSheet)
        
        // 删除本地文件
        let deleteLocalAction = UIAlertAction(title: "删除本地文件", style: .destructive) { [weak self] _ in
            self?.deleteFile(file, deleteFromiCloud: false)
        }
        
        // 删除本地和iCloud文件
        let deleteBothAction = UIAlertAction(title: "删除本地和iCloud文件", style: .destructive) { [weak self] _ in
            self?.deleteFile(file, deleteFromiCloud: true)
        }
        
        // 取消
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(deleteLocalAction)
        alertController.addAction(deleteBothAction)
        alertController.addAction(cancelAction)
        
        // 设置iPad的popover
        if let popover = alertController.popoverPresentationController {
            let cell = tableView.cellForRow(at: indexPath)
            popover.sourceView = cell
            popover.sourceRect = cell?.bounds ?? CGRect.zero
        }
        
        present(alertController, animated: true)
    }
    
    private func deleteFile(_ file: MarkdownFile, deleteFromiCloud: Bool) {
        // 显示确认对话框
        let title = deleteFromiCloud ? "删除本地和iCloud文件" : "删除本地文件"
        let message = "确定要删除文件「\(file.displayName)」吗？"
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let deleteAction = UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.performFileDelete(file, deleteFromiCloud: deleteFromiCloud)
        }
        
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alertController.addAction(deleteAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    private func performFileDelete(_ file: MarkdownFile, deleteFromiCloud: Bool) {
        CloudSyncManager.shared.deleteFile(file, deleteFromiCloud: deleteFromiCloud) { [weak self] success, message in
            DispatchQueue.main.async {
                if success {
                    // 删除成功，更新数据和UI
                    self?.handleFileDeleteSuccess(file, message: message)
                } else {
                    // 删除失败，显示错误信息
                    self?.showErrorToast(message ?? "删除失败")
                }
            }
        }
    }
    
    private func handleFileDeleteSuccess(_ deletedFile: MarkdownFile, message: String?) {
        // 从最近访问记录中移除
        RecentFileManager.shared.removeRecentFile(deletedFile)
        
        // 更新subjectGroup中的文件列表
        if let group = subjectGroup {
            let updatedFiles = group.files.filter { $0.relativePath != deletedFile.relativePath }
            subjectGroup = SubjectGroup(
                title: group.title,
                files: updatedFiles,
                iconName: group.iconName,
                gradientColors: group.gradientColors
            )
        }
        
        // 重新加载表格
        tableView.reloadData()
        
        // 显示成功提示
        showSuccessToast(message ?? "删除成功")
    }
    
    private func showSuccessToast(_ message: String) {
        ToastManager.shared.showSuccess(message, in: view)
    }
    
    private func showErrorToast(_ message: String) {
        ToastManager.shared.showError(message, in: view)
    }
    
    private func showInfoToast(_ message: String) {
        ToastManager.shared.showInfo(message, in: view)
    }
}

// MARK: - 统计卡片视图
class StatsCardView: UIView {
    
    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private lazy var valueLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.masksToBounds = true
        
        // 添加轻微的阴影效果
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.1
        layer.masksToBounds = false
        
        let stackView = UIStackView(arrangedSubviews: [iconImageView, valueLabel, titleLabel])
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .center
        
        addSubview(stackView)
        
        stackView.snp.makeConstraints { make in
            make.center.equalTo(self)
            make.leading.greaterThanOrEqualTo(self).offset(8)
            make.trailing.lessThanOrEqualTo(self).offset(-8)
        }
        
        iconImageView.snp.makeConstraints { make in
            make.size.equalTo(24)
        }
        
        self.snp.makeConstraints { make in
            make.height.equalTo(100)
        }
    }
    
    func configure(title: String, value: String, icon: String, color: UIColor) {
        titleLabel.text = title
        valueLabel.text = value
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = color
    }
    
    func updateValue(_ value: String) {
        valueLabel.text = value
    }
}

// MARK: - UIDocumentInteractionControllerDelegate
extension FileListViewController: UIDocumentInteractionControllerDelegate {
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func documentInteractionControllerViewForPreview(_ controller: UIDocumentInteractionController) -> UIView? {
        return view
    }
    
    func documentInteractionControllerRectForPreview(_ controller: UIDocumentInteractionController) -> CGRect {
        return view.bounds
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, didEndSendingToApplication application: String?) {
        if let app = application {
            print("文件已发送到应用: \(app)")
            showSuccessToast("已在\(app)中打开")
        }
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, willBeginSendingToApplication application: String?) {
        if let app = application {
            print("📤 正在发送文件到应用: \(app)")
        }
    }
}

