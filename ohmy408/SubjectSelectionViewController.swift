import UIKit
import SnapKit

/// 科目选择视图控制器 - 用于文件导入时选择目标科目
class SubjectSelectionViewController: UIViewController {
    
    // MARK: - UI组件
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let navigationBar = UINavigationBar()
    
    // MARK: - 数据源
    private var existingSubjects: [String] = []
    private let defaultSubjects = ["高数", "数据结构算法", "计算机组成原理", "其他"]
    
    // MARK: - 回调
    var onSubjectSelected: ((String) -> Void)?
    var onCancel: (() -> Void)?
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadExistingSubjects()
    }
    
    // MARK: - UI设置
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        
        setupNavigationBar()
        setupTableView()
        setupConstraints()
    }
    
    private func setupNavigationBar() {
        view.addSubview(navigationBar)
        
        let navItem = UINavigationItem(title: "选择科目")
        
        let cancelButton = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addNewSubjectTapped)
        )
        
        navItem.leftBarButtonItem = cancelButton
        navItem.rightBarButtonItem = addButton
        
        navigationBar.setItems([navItem], animated: false)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SubjectCell")
        view.addSubview(tableView)
    }
    
    private func setupConstraints() {
        navigationBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalTo(view)
        }
        
        tableView.snp.makeConstraints { make in
            make.top.equalTo(navigationBar.snp.bottom)
            make.leading.trailing.bottom.equalTo(view)
        }
    }
    
    // MARK: - 数据加载
    private func loadExistingSubjects() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let datasURL = documentsURL.appendingPathComponent("datas")
        
        var subjects: [String] = []
        
        // 添加默认科目
        subjects.append(contentsOf: defaultSubjects)
        
        // 扫描Documents/datas目录中的现有科目
        if FileManager.default.fileExists(atPath: datasURL.path) {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: datasURL,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                
                for url in contents {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    if resourceValues.isDirectory == true {
                        let subjectName = url.lastPathComponent
                        if !subjects.contains(subjectName) {
                            subjects.append(subjectName)
                        }
                    }
                }
            } catch {
                print("❌ 扫描科目目录失败: \(error)")
            }
        }
        
        // 去重并排序
        existingSubjects = Array(Set(subjects)).sorted { subject1, subject2 in
            // "其他"排在最后
            if subject1 == "其他" { return false }
            if subject2 == "其他" { return true }
            return subject1 < subject2
        }
        
        tableView.reloadData()
    }
    
    // MARK: - 按钮事件
    @objc private func cancelTapped() {
        onCancel?()
    }
    
    @objc private func addNewSubjectTapped() {
        showAddNewSubjectAlert()
    }
    
    private func showAddNewSubjectAlert() {
        let alert = UIAlertController(
            title: "创建新科目",
            message: "请输入新科目的名称",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "科目名称"
            textField.autocapitalizationType = .words
        }
        
        let createAction = UIAlertAction(title: "创建", style: .default) { [weak self] _ in
            guard let textField = alert.textFields?.first,
                  let subjectName = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !subjectName.isEmpty else {
                return
            }
            
            self?.createNewSubject(name: subjectName)
        }
        
        let cancelAction = UIAlertAction(title: "取消", style: .cancel)
        
        alert.addAction(createAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func createNewSubject(name: String) {
        // 检查是否已存在
        if existingSubjects.contains(name) {
            showAlert(title: "科目已存在", message: "科目 \"\(name)\" 已经存在，请选择现有科目或使用其他名称。")
            return
        }
        
        // 创建目录
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let datasURL = documentsURL.appendingPathComponent("datas")
        let subjectURL = datasURL.appendingPathComponent(name)
        
        do {
            try FileManager.default.createDirectory(at: subjectURL, withIntermediateDirectories: true)
            
            // 添加到列表并刷新
            existingSubjects.append(name)
            existingSubjects.sort { subject1, subject2 in
                if subject1 == "其他" { return false }
                if subject2 == "其他" { return true }
                return subject1 < subject2
            }
            
            tableView.reloadData()
            
            // 自动选择新创建的科目
            onSubjectSelected?(name)
            
        } catch {
            showAlert(title: "创建失败", message: "创建科目目录失败: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension SubjectSelectionViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return existingSubjects.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SubjectCell", for: indexPath)
        
        let subject = existingSubjects[indexPath.row]
        cell.textLabel?.text = subject
        cell.accessoryType = .disclosureIndicator
        
        // 为"其他"科目添加特殊图标
        if subject == "其他" {
            cell.imageView?.image = UIImage(systemName: "folder.badge.questionmark")
        } else {
            cell.imageView?.image = UIImage(systemName: "folder")
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "选择文件要保存到的科目"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "点击右上角 + 按钮可以创建新的科目分组"
    }
}

// MARK: - UITableViewDelegate
extension SubjectSelectionViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let selectedSubject = existingSubjects[indexPath.row]
        onSubjectSelected?(selectedSubject)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }
} 