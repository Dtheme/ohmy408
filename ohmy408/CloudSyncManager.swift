//
//  CloudSyncManager.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import Foundation
import UIKit

/// 同步方向枚举
enum SyncDirection {
    case upload   // 上传到iCloud
    case download // 从iCloud下载
}

/// 同步错误类型
enum SyncError: Error {
    case iCloudUnavailable
    case directoryCreationFailed
    case fileSyncFailed(String)
}

/// 同步结果结构
struct SyncResult {
    var downloadedFiles: Int = 0
    var uploadedFiles: Int = 0
    var downloadErrors: [String] = []
    var uploadErrors: [String] = []
}

/// 目录同步结果
struct DirectorySyncResult {
    var fileCount: Int = 0
    var errors: [String] = []
}

/// iCloud同步管理器 - 负责文档同步到iCloud功能
class CloudSyncManager {
    
    static let shared = CloudSyncManager()
    
    // iCloud中的文件夹名称
    private let iCloudFolderName = "ohmy408"
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 冷启动时自动同步检查
    /// - Parameter completion: 完成回调，返回同步结果
    func performColdStartSync(completion: @escaping (Bool, String?) -> Void) {
        print("开始冷启动同步检查...")
        
        // 检查iCloud可用性
        let availabilityCheck = checkICloudAvailability()
        guard availabilityCheck.isAvailable else {
            print("iCloud不可用，跳过同步")
            completion(false, "iCloud不可用: \(availabilityCheck.message)")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 执行双向同步
                let syncResult = try self.performBidirectionalSync()
                
                DispatchQueue.main.async {
                    let message = self.formatSyncResult(syncResult)
                    print("冷启动同步完成: \(message)")
                    completion(true, message)
                }
                
            } catch {
                DispatchQueue.main.async {
                    let errorMessage = "冷启动同步失败: \(error.localizedDescription)"
                    print("\(errorMessage)")
                    completion(false, errorMessage)
                }
            }
        }
    }
    
    /// 下拉刷新同步 - 从iCloud下载最新数据到Documents
    /// - Parameter completion: 完成回调，返回成功状态和错误信息
    func pullToRefreshSync(completion: @escaping (Bool, String?) -> Void) {
        // 检查iCloud可用性
        let availabilityCheck = checkICloudAvailability()
        guard availabilityCheck.isAvailable else {
            completion(false, availabilityCheck.message)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let iCloudURL = self.getICloudDocumentsDirectory() else {
                    DispatchQueue.main.async {
                        completion(false, "无法访问iCloud Documents目录")
                    }
                    return
                }
                
                let localDatasURL = self.getDocumentsDirectory().appendingPathComponent("datas")
                let iCloudDatasURL = iCloudURL.appendingPathComponent(self.iCloudFolderName)
                
                // 确保本地目录存在
                try self.createDirectoryIfNeeded(localDatasURL)
                
                // 检查iCloud目录是否存在
                if !FileManager.default.fileExists(atPath: iCloudDatasURL.path) {
                    DispatchQueue.main.async {
                        completion(true, "iCloud中暂无数据")
                    }
                    return
                }
                
                // 从iCloud下载文件到Documents（不影响Bundle文件）
                let downloadResult = try self.syncDirectory(
                    from: iCloudDatasURL, 
                    to: localDatasURL, 
                    direction: .download
                )
                
                DispatchQueue.main.async {
                    if downloadResult.errors.isEmpty {
                        let message = downloadResult.fileCount > 0 ? 
                            "从iCloud/\(self.iCloudFolderName)下载了 \(downloadResult.fileCount) 个文件" : 
                            "所有文件已是最新状态"
                        completion(true, message)
                    } else {
                        let errorMessage = "部分文件下载失败:\n\(downloadResult.errors.joined(separator: "\n"))"
                        completion(false, errorMessage)
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(false, "下拉同步失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 同步所有文档到iCloud
    /// - Parameter completion: 完成回调，返回成功状态和错误信息
    func syncAllDocumentsToiCloud(completion: @escaping (Bool, String?) -> Void) {
        // 检查iCloud可用性
        let availabilityCheck = checkICloudAvailability()
        guard availabilityCheck.isAvailable else {
            completion(false, availabilityCheck.message)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let documentsURL = self.getDocumentsDirectory()
                let datasURL = documentsURL.appendingPathComponent("datas")
                
                // 确保datas目录存在
                // 确保Documents/datas目录存在
                try self.createDirectoryIfNeeded(datasURL)
                
                // 检查是否需要从Bundle复制基础文件
                let localFileCount = self.countMarkdownFiles(in: datasURL)
                if localFileCount == 0 {
                    print("Documents/datas目录为空，从Bundle复制基础文件...")
                    self.copyBundleFilesToDocumentsIfNeeded()
                    
                    // Bundle文件复制完成后，重新统计文件数量，确保后续同步逻辑正常执行
                    let newLocalFileCount = self.countMarkdownFiles(in: datasURL)
                    print("Bundle文件复制完成，当前本地文件数量: \(newLocalFileCount)")
                } else {
                    print("Documents/datas已有 \(localFileCount) 个文件，跳过Bundle文件复制")
                }
                
                // 获取iCloud Documents目录
                guard let iCloudURL = self.getICloudDocumentsDirectory() else {
                    DispatchQueue.main.async {
                        completion(false, "无法访问iCloud Documents目录")
                    }
                    return
                }
                
                // 创建iCloud中的ohmy408目录
                let iCloudDatasURL = iCloudURL.appendingPathComponent(self.iCloudFolderName)
                print("iCloud路径: \(iCloudDatasURL.path)")
                
                if !FileManager.default.fileExists(atPath: iCloudDatasURL.path) {
                    try FileManager.default.createDirectory(at: iCloudDatasURL, withIntermediateDirectories: true)
                    print("创建iCloud文件夹: \(self.iCloudFolderName)")
                    print("完整路径: \(iCloudDatasURL.path)")
                } else {
                    print("iCloud文件夹已存在: \(self.iCloudFolderName)")
                }
                
                // 同步Documents中的文件到iCloud
                let syncResult = try self.syncDirectory(from: datasURL, to: iCloudDatasURL, direction: .upload)
                
                DispatchQueue.main.async {
                    if syncResult.errors.isEmpty {
                        completion(true, "成功上传 \(syncResult.fileCount) 个文件到iCloud/\(self.iCloudFolderName)")
                    } else {
                        let errorMessage = "部分文件上传失败:\n\(syncResult.errors.joined(separator: "\n"))"
                        completion(false, errorMessage)
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(false, "同步失败: \(error.localizedDescription)")
                }
            }
        }
    }
    

    
    /// 删除文件（支持本地和iCloud）
    /// - Parameters:
    ///   - file: 要删除的文件
    ///   - deleteFromiCloud: 是否同时从iCloud删除
    ///   - completion: 完成回调
    func deleteFile(_ file: MarkdownFile, deleteFromiCloud: Bool, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            var deletedLocal = false
            var deletediCloud = false
            
            print("🗑️ 开始删除文件: \(file.displayName)")
            print("📁 文件路径: \(file.relativePath)")
            print("🔍 文件来源: \(file.source)")
            
            // 1. 检查文件来源并删除本地文件
            if file.source == .documents {
                // Documents文件可以删除，使用文件的实际URL
                let localFileURL = file.url
                print("📍 尝试删除Documents文件: \(localFileURL.path)")
                
                if FileManager.default.fileExists(atPath: localFileURL.path) {
                    do {
                        try FileManager.default.removeItem(at: localFileURL)
                        print("✅ 已删除本地文件: \(file.displayName)")
                        deletedLocal = true
                    } catch {
                        let errorMsg = "删除本地文件失败: \(error.localizedDescription)"
                        print("❌ \(errorMsg)")
                        errors.append(errorMsg)
                    }
                } else {
                    print("⚠️ 本地文件不存在: \(localFileURL.path)")
                    errors.append("本地文件不存在")
                }
            } else {
                // Bundle文件无法删除
                print("⚠️ Bundle文件无法删除: \(file.displayName)")
                errors.append("Bundle文件无法删除，这些是应用内置文件")
            }
            
            // 2. 如果需要，删除iCloud文件
            if deleteFromiCloud {
                let availabilityCheck = self.checkICloudAvailability()
                if availabilityCheck.isAvailable {
                    if let iCloudURL = self.getICloudDocumentsDirectory() {
                        // 智能构建iCloud文件路径
                        let iCloudFileURL = self.buildICloudFilePath(for: file, baseURL: iCloudURL)
                        
                        print("📍 尝试删除iCloud文件: \(iCloudFileURL.path)")
                        
                        if FileManager.default.fileExists(atPath: iCloudFileURL.path) {
                            do {
                                try FileManager.default.removeItem(at: iCloudFileURL)
                                print("✅ 已删除iCloud文件: \(file.displayName)")
                                deletediCloud = true
                            } catch {
                                let errorMsg = "删除iCloud文件失败: \(error.localizedDescription)"
                                print("❌ \(errorMsg)")
                                errors.append(errorMsg)
                            }
                        } else {
                            print("⚠️ iCloud文件不存在: \(iCloudFileURL.path)")
                            // 如果iCloud文件不存在，不算错误
                        }
                    } else {
                        errors.append("无法访问iCloud目录")
                    }
                } else {
                    errors.append("iCloud不可用，无法删除云端文件")
                }
            }
            
            DispatchQueue.main.async {
                // 判断删除结果
                if file.source == .bundle && !deleteFromiCloud {
                    // 只是尝试删除Bundle文件
                    completion(false, "无法删除Bundle文件，这些是应用内置文件")
                } else if file.source == .bundle && deleteFromiCloud {
                    // Bundle文件但删除了iCloud文件
                    if deletediCloud || errors.isEmpty {
                        completion(true, "已删除iCloud文件（Bundle文件无法删除）")
                    } else {
                        completion(false, errors.joined(separator: "\n"))
                    }
                } else {
                    // Documents文件
                    if errors.isEmpty {
                        let message = deleteFromiCloud ? "已删除本地和iCloud文件" : "已删除本地文件"
                        completion(true, message)
                    } else if deletedLocal && !deleteFromiCloud {
                        // 本地删除成功，不需要删除iCloud
                        completion(true, "已删除本地文件")
                    } else if deletedLocal && deletediCloud {
                        // 都删除成功
                        completion(true, "已删除本地和iCloud文件")
                    } else {
                        completion(false, errors.joined(separator: "\n"))
                    }
                }
            }
        }
    }
    
    /// 检查iCloud同步状态
    func checkSyncStatus() -> (isAvailable: Bool, message: String) {
        let availabilityCheck = checkICloudAvailability()
        if !availabilityCheck.isAvailable {
            return (false, availabilityCheck.message)
        }
        
        guard let iCloudURL = getICloudDocumentsDirectory() else {
            return (false, "无法访问iCloud Documents目录")
        }
        
        let iCloudDatasURL = iCloudURL.appendingPathComponent(iCloudFolderName)
        let localDatasURL = getDocumentsDirectory().appendingPathComponent("datas")
        
        let localFileCount = countMarkdownFiles(in: localDatasURL)
        let iCloudFileCount = countMarkdownFiles(in: iCloudDatasURL)
        
        if iCloudFileCount == 0 {
            return (true, "iCloud可用，尚未同步文件\n本地文件: \(localFileCount) 个\niCloud文件夹: \(iCloudFolderName)")
        } else if localFileCount == iCloudFileCount {
            return (true, "同步完成\n已同步 \(iCloudFileCount) 个文件到iCloud/\(iCloudFolderName)")
        } else {
            return (true, "文件数量不一致\n本地: \(localFileCount) 个文件\niCloud/\(iCloudFolderName): \(iCloudFileCount) 个文件")
        }
    }
    
    // MARK: - 私有方法
    
    /// 智能构建iCloud文件路径
    private func buildICloudFilePath(for file: MarkdownFile, baseURL: URL) -> URL {
        let fileName = file.name
        
        // 解析relativePath，处理各种可能的格式
        var pathComponents = file.relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
        
        // 移除开头的"datas"或"privatedatas"
        if pathComponents.first == "datas" || pathComponents.first == "privatedatas" {
            pathComponents.removeFirst()
        }
        
        // 移除末尾的文件名（如果存在）
        if pathComponents.last == fileName || pathComponents.last == file.displayName {
            pathComponents.removeLast()
        }
        
        // 去重路径组件（处理"其他/其他"这种情况）
        pathComponents = removeDuplicatePathComponents(pathComponents)
        
        // 构建最终路径
        var iCloudFileURL = baseURL.appendingPathComponent(iCloudFolderName)
        
        // 添加子目录路径
        for component in pathComponents {
            iCloudFileURL = iCloudFileURL.appendingPathComponent(component)
        }
        
        // 添加文件名
        iCloudFileURL = iCloudFileURL.appendingPathComponent(fileName)
        
        print("🔧 路径构建详情:")
        print("   原始relativePath: \(file.relativePath)")
        print("   解析后pathComponents: \(pathComponents)")
        print("   最终iCloud路径: \(iCloudFileURL.path)")
        
        return iCloudFileURL
    }
    
    /// 移除重复的路径组件
    private func removeDuplicatePathComponents(_ components: [String]) -> [String] {
        var result: [String] = []
        var lastComponent: String?
        
        for component in components {
            if component != lastComponent {
                result.append(component)
                lastComponent = component
            }
        }
        
        return result
    }
    
    /// 检查iCloud是否可用
    private func isICloudAvailable() -> Bool {
        if let _ = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return true
        }
        return false
    }
    
    /// 详细检查iCloud可用性
    private func checkICloudAvailability() -> (isAvailable: Bool, message: String) {
        // 检查iCloud账户状态
        if let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            // iCloud容器可用，进一步检查目录是否可访问
            do {
                let _ = try FileManager.default.contentsOfDirectory(at: ubiquityURL, includingPropertiesForKeys: nil)
                return (true, "iCloud已登录且可用\n容器路径: \(ubiquityURL.path)")
            } catch {
                return (false, "iCloud容器不可访问\n错误: \(error.localizedDescription)\n\n请检查:\n1. iCloud Drive是否已开启\n2. 网络连接是否正常\n3. 设备存储空间是否充足")
            }
        } else {
            // 检查具体原因
            let reasons = [
                "设备未登录iCloud账户",
                "iCloud Drive未启用",
                "应用未获得iCloud权限",
                "网络连接问题"
            ]
            
            return (false, "iCloud不可用\n\n可能原因:\n\(reasons.joined(separator: "\n"))\n\n解决方法:\n1. 前往设置 > Apple ID > iCloud\n2. 确保iCloud Drive已开启\n3. 检查网络连接\n4. 重启应用")
        }
    }
    
    /// 获取iCloud Documents目录
    private func getICloudDocumentsDirectory() -> URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            print("无法获取iCloud容器URL")
            return nil
        }
        
        print("iCloud容器路径: \(containerURL.path)")
        let documentsURL = containerURL.appendingPathComponent("Documents")
        print("iCloud Documents路径: \(documentsURL.path)")
        
        return documentsURL
    }
    
    /// 获取本地Documents目录
    private func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// 同步目录（支持双向同步）
    private func syncDirectory(from sourceURL: URL, to destinationURL: URL, direction: SyncDirection) throws -> DirectorySyncResult {
        var result = DirectorySyncResult()
        
        // 确保源目录存在
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("源目录不存在: \(sourceURL.path)")
            return result
        }
        
        // 确保目标目录存在
        try createDirectoryIfNeeded(destinationURL)
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
        )
        
        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey])
            let destinationItemURL = destinationURL.appendingPathComponent(url.lastPathComponent)
            
            if resourceValues.isDirectory == true {
                // 递归同步子目录
                do {
                    let subResult = try syncDirectory(from: url, to: destinationItemURL, direction: direction)
                    result.fileCount += subResult.fileCount
                    result.errors.append(contentsOf: subResult.errors)
                } catch {
                    result.errors.append("同步目录 \(url.lastPathComponent) 失败: \(error.localizedDescription)")
                }
            } else if resourceValues.isRegularFile == true && shouldSyncFileType(url) {
                // 同步支持的文件类型（Markdown、图片、XMind）
                do {
                    let shouldSync = try shouldSyncFile(sourceURL: url, destinationURL: destinationItemURL, direction: direction)
                    
                    if shouldSync {
                        try syncSingleFile(from: url, to: destinationItemURL, direction: direction)
                        result.fileCount += 1
                        
                        let directionText = direction == .upload ? "上传" : "下载"
                        print("\(directionText)文件: \(url.lastPathComponent)")
                    }
                } catch {
                    let directionText = direction == .upload ? "上传" : "下载"
                    let errorMsg = "\(directionText)文件 \(url.lastPathComponent) 失败: \(error.localizedDescription)"
                    result.errors.append(errorMsg)
                    print("\(errorMsg)")
                }
            }
        }
        
        return result
    }
    
    /// 判断文件类型是否应该同步
    private func shouldSyncFileType(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent.lowercased()
        
        // 排除系统文件和非文档文件
        let excludedFiles = [
            ".ds_store",
            "contents.json",
            "info.plist"
        ]
        
        let excludedPrefixes = [
            "appicon",
            "app store"
        ]
        
        let excludedPaths = [
            "assets.xcassets",
            "base.lproj"
        ]
        
        // 检查是否是被排除的文件
        if excludedFiles.contains(fileName) {
            return false
        }
        
        // 检查是否有被排除的前缀
        for prefix in excludedPrefixes {
            if fileName.hasPrefix(prefix) {
                return false
            }
        }
        
        // 检查是否在被排除的路径中
        let urlPath = url.path.lowercased()
        for excludedPath in excludedPaths {
            if urlPath.contains(excludedPath) {
                return false
            }
        }
        
        // 检查是否是支持的文件扩展名
        let supportedExtensions = ["md", "jpg", "jpeg", "png", "gif", "webp", "xmind"]
        return supportedExtensions.contains(fileExtension)
    }
    
    /// 判断是否需要同步文件（基于修改时间）
    private func shouldSyncFile(sourceURL: URL, destinationURL: URL, direction: SyncDirection) throws -> Bool {
        // 如果目标文件不存在，需要同步
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            return true
        }
        
        // 获取文件修改时间
        let sourceValues = try sourceURL.resourceValues(forKeys: [.contentModificationDateKey])
        let destValues = try destinationURL.resourceValues(forKeys: [.contentModificationDateKey])
        
        guard let sourceDate = sourceValues.contentModificationDate,
              let destDate = destValues.contentModificationDate else {
            // 如果无法获取修改时间，默认同步
            return true
        }
        
        // 如果源文件更新，需要同步
        return sourceDate > destDate
    }
    
    /// 同步单个文件
    private func syncSingleFile(from sourceURL: URL, to destinationURL: URL, direction: SyncDirection) throws {
        // 如果目标文件存在，先删除
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // 复制文件
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        
        // 如果是上传到iCloud，文件已复制到iCloud目录，系统会自动处理同步
        if direction == .upload {
            print("✅ 文件已上传到iCloud: \(destinationURL.lastPathComponent)")
        }
    }
    
    /// 执行双向同步（上传本地文件到iCloud，下载iCloud文件到本地）
    private func performBidirectionalSync() throws -> SyncResult {
        guard let iCloudURL = getICloudDocumentsDirectory() else {
            throw SyncError.iCloudUnavailable
        }
        
        let localDatasURL = getDocumentsDirectory().appendingPathComponent("datas")
        let iCloudDatasURL = iCloudURL.appendingPathComponent(iCloudFolderName)
        
        // 确保目录存在
        try createDirectoryIfNeeded(localDatasURL)
        try createDirectoryIfNeeded(iCloudDatasURL)
        
        var result = SyncResult()
        
        // 1. 下载iCloud文件到本地（优先级更高）
        print("开始从iCloud下载文件...")
        let downloadResult = try syncDirectory(from: iCloudDatasURL, to: localDatasURL, direction: .download)
        result.downloadedFiles = downloadResult.fileCount
        result.downloadErrors.append(contentsOf: downloadResult.errors)
        
        // 2. 上传本地文件到iCloud
        print("开始上传文件到iCloud...")
        let uploadResult = try syncDirectory(from: localDatasURL, to: iCloudDatasURL, direction: .upload)
        result.uploadedFiles = uploadResult.fileCount
        result.uploadErrors.append(contentsOf: uploadResult.errors)
        
        return result
    }
    
    /// 创建目录（如果不存在）
    private func createDirectoryIfNeeded(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    /// 格式化同步结果消息
    private func formatSyncResult(_ result: SyncResult) -> String {
        var messages: [String] = []
        
        if result.downloadedFiles > 0 {
            messages.append("从iCloud/\(iCloudFolderName)下载了 \(result.downloadedFiles) 个文件")
        }
        
        if result.uploadedFiles > 0 {
            messages.append("上传了 \(result.uploadedFiles) 个文件到iCloud/\(iCloudFolderName)")
        }
        
        if result.downloadedFiles == 0 && result.uploadedFiles == 0 {
            messages.append("数据已全部同步")
        }
        
        let totalErrors = result.downloadErrors.count + result.uploadErrors.count
        if totalErrors > 0 {
            messages.append("\(totalErrors) 个文件同步失败")
        }
        
        return messages.joined(separator: "\n")
    }
    
    /// 从Bundle复制文件到Documents（如果需要）
    private func copyBundleFilesToDocumentsIfNeeded() {
        guard let bundleURL = Bundle.main.resourceURL else {
            print("无法获取Bundle资源目录")
            return
        }
        
        let documentsURL = getDocumentsDirectory()
        let documentsDatasURL = documentsURL.appendingPathComponent("datas")
        
        // 检查Bundle中是否有datas.bundle目录
        let bundleDatasURL = bundleURL.appendingPathComponent("datas.bundle")
        if FileManager.default.fileExists(atPath: bundleDatasURL.path) {
            // 情况1：Bundle中有datas.bundle目录，直接复制
            print("📦 Bundle中找到datas.bundle目录，直接复制...")
            do {
                try copyDirectory(from: bundleDatasURL, to: documentsDatasURL)
                print("✅ Bundle文件复制完成")
            } catch {
                print("❌ 复制Bundle文件失败: \(error)")
            }
        } else {
            // 情况2：Bundle中没有datas.bundle目录，检查旧的datas目录
            let oldBundleDatasURL = bundleURL.appendingPathComponent("datas")
            if FileManager.default.fileExists(atPath: oldBundleDatasURL.path) {
                print("📦 Bundle中找到旧的datas目录，直接复制...")
                do {
                    try copyDirectory(from: oldBundleDatasURL, to: documentsDatasURL)
                    print("✅ Bundle文件复制完成")
                } catch {
                    print("❌ 复制Bundle文件失败: \(error)")
                }
            } else {
                // 情况3：都没有，从根目录重新组织文件
                print("📦 Bundle中没有找到datas相关目录，从根目录重新组织文件...")
                do {
                    try organizeBundleFilesToDocuments(bundleURL: bundleURL, documentsURL: documentsDatasURL)
                    print("✅ Bundle文件重新组织完成")
                } catch {
                    print("❌ 重新组织Bundle文件失败: \(error)")
                }
            }
        }
    }
    
    /// 从Bundle根目录重新组织文件到Documents/datas结构
    private func organizeBundleFilesToDocuments(bundleURL: URL, documentsURL: URL) throws {
        // 确保Documents/datas目录存在
        try createDirectoryIfNeeded(documentsURL)
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
        )
        
        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            
            if resourceValues.isDirectory == true {
                // 这是一个学科目录（如"高数"、"数据结构与算法"等）
                let subjectName = url.lastPathComponent
                let destinationSubjectURL = documentsURL.appendingPathComponent(subjectName)
                
                print("📁 复制学科目录: \(subjectName)")
                try copyDirectory(from: url, to: destinationSubjectURL)
                
            } else if resourceValues.isRegularFile == true && shouldSyncFileType(url) {
                // 这是根目录下的支持文件类型，推断学科分类
                let fileName = url.lastPathComponent
                let subject = inferSubjectFromFileName(fileName)
                let destinationSubjectURL = documentsURL.appendingPathComponent(subject)
                
                // 确保目标学科目录存在
                try createDirectoryIfNeeded(destinationSubjectURL)
                
                let destinationFileURL = destinationSubjectURL.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: destinationFileURL.path) {
                    try FileManager.default.copyItem(at: url, to: destinationFileURL)
                    print("📄 复制文件: \(fileName) -> \(subject)/")
                }
            }
        }
    }
    
    /// 根据文件名推断学科分类（与MarkdownFileManager保持一致）
    private func inferSubjectFromFileName(_ fileName: String) -> String {
        let name = fileName.lowercased()
        
        if name.contains("函数") || name.contains("极限") || name.contains("导数") || name.contains("微分") || name.contains("积分") || name.contains("高数") {
            return "高数"
        } else if name.contains("数据结构") || name.contains("算法") {
            return "数据结构与算法"
        } else if name.contains("计算机") || name.contains("组成原理") {
            return "计算机组成原理"
        } else if name.contains("基础知识补充") {
            return "高数"  // 基础知识补充归类到高数
        } else {
            return "其他"
        }
    }
    
    /// 递归复制目录
    private func copyDirectory(from sourceURL: URL, to destinationURL: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        
        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            let destinationItemURL = destinationURL.appendingPathComponent(url.lastPathComponent)
            
            if resourceValues.isDirectory == true {
                // 创建子目录
                if !FileManager.default.fileExists(atPath: destinationItemURL.path) {
                    try FileManager.default.createDirectory(at: destinationItemURL, withIntermediateDirectories: true)
                }
                // 递归复制子目录
                try copyDirectory(from: url, to: destinationItemURL)
            } else if shouldSyncFileType(url) {
                // 只复制支持的文件类型（如果不存在）
                if !FileManager.default.fileExists(atPath: destinationItemURL.path) {
                    try FileManager.default.copyItem(at: url, to: destinationItemURL)
                    print("复制文件: \(url.lastPathComponent)")
                }
            }
        }
    }
    
    /// 统计目录中的Markdown文件数量
    private func countMarkdownFiles(in directory: URL) -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return 0
        }
        
        var count = 0
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                
                if resourceValues.isDirectory == true {
                    count += countMarkdownFiles(in: url)
                } else if resourceValues.isRegularFile == true && shouldSyncFileType(url) {
                    count += 1
                }
            }
        } catch {
            print("统计文件失败: \(error)")
        }
        
        return count
    }
} 
