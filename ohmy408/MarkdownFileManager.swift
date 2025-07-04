//
//  MarkdownFileManager.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import Foundation

/// 文件来源枚举
enum FileSource {
    case bundle     // Bundle中的文件
    case documents  // Documents中的文件
}

/// Markdown文件模型
struct MarkdownFile {
    let url: URL
    let name: String
    let displayName: String
    let size: Int64
    let modificationDate: Date
    let relativePath: String
    let source: FileSource
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: modificationDate)
    }
}

/// Markdown文件管理器 - 负责扫描和管理Markdown文件
class MarkdownFileManager {
    
    static let shared = MarkdownFileManager()
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取所有Markdown文件
    func getAllMarkdownFiles() -> [MarkdownFile] {
        var allFiles: [MarkdownFile] = []
        
        // 1. 扫描Bundle中的Markdown文件（作为基础文件）
        let bundleFiles = scanBundleMarkdownFiles()
        
        // 2. 扫描Documents中的datas文件夹
        let documentsFiles = scanDocumentsDatasFolder()
        
        // 3. 合并文件并去重（Documents中的文件优先）
        allFiles = mergeAndDeduplicateFiles(bundleFiles: bundleFiles, documentsFiles: documentsFiles)
        
        return allFiles
    }
    
    /// 创建datas目录（如果不存在）
    func createDatasDirectoryIfNeeded() {
        let documentsURL = getDocumentsDirectory()
        let datasURL = documentsURL.appendingPathComponent("datas")
        
        if !FileManager.default.fileExists(atPath: datasURL.path) {
            do {
                try FileManager.default.createDirectory(at: datasURL, withIntermediateDirectories: true)
                print("✅ 创建datas目录: \(datasURL.path)")
            } catch {
                print("❌ 创建datas目录失败: \(error)")
            }
        }
    }
    
    /// 合并Bundle和Documents文件，去重处理
    private func mergeAndDeduplicateFiles(bundleFiles: [MarkdownFile], documentsFiles: [MarkdownFile]) -> [MarkdownFile] {
        var mergedFiles: [MarkdownFile] = []
        var fileNames: Set<String> = []
        
        // 1. 优先添加Documents中的文件
        for file in documentsFiles {
            if !fileNames.contains(file.name) {
                mergedFiles.append(file)
                fileNames.insert(file.name)
            }
        }
        
        // 2. 添加Bundle中不重复的文件
        for file in bundleFiles {
            if !fileNames.contains(file.name) {
                mergedFiles.append(file)
                fileNames.insert(file.name)
            }
        }
        
        print("📊 文件统计: Bundle(\(bundleFiles.count)) + Documents(\(documentsFiles.count)) = 合并后(\(mergedFiles.count))")
        
        return mergedFiles
    }
    
    // MARK: - 私有方法
    
    /// 获取Documents目录
    private func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// 扫描Bundle中的Markdown文件
    private func scanBundleMarkdownFiles() -> [MarkdownFile] {
        guard let bundleURL = Bundle.main.resourceURL else {
            print("❌ 无法获取Bundle资源目录")
            return []
        }
        
        var bundleFiles: [MarkdownFile] = []
        
        // 检查Bundle中是否有datas.bundle目录
        let bundleDatasURL = bundleURL.appendingPathComponent("datas.bundle")
        if FileManager.default.fileExists(atPath: bundleDatasURL.path) {
            print("📦 在Bundle中找到datas.bundle目录，开始扫描...")
            bundleFiles = scanMarkdownFiles(in: bundleDatasURL, baseURL: bundleDatasURL, pathPrefix: "datas", source: .bundle)
        } else {
            // 检查旧的datas目录
            let oldBundleDatasURL = bundleURL.appendingPathComponent("datas")
            if FileManager.default.fileExists(atPath: oldBundleDatasURL.path) {
                print("📦 在Bundle中找到旧的datas目录，开始扫描...")
                bundleFiles = scanMarkdownFiles(in: oldBundleDatasURL, baseURL: oldBundleDatasURL, pathPrefix: "datas", source: .bundle)
            } else {
                print("⚠️ Bundle中没有找到datas相关目录，扫描根目录...")
                // 扫描Bundle根目录的.md文件（备用方案）
                do {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: bundleURL,
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                    )
                    
                    for url in contents {
                        if shouldIncludeFile(url) {
                            if let file = createMarkdownFileFromBundle(from: url) {
                                bundleFiles.append(file)
                            }
                        }
                    }
                } catch {
                    print("❌ 扫描Bundle文件失败: \(error)")
                }
            }
        }
        
        print("📦 Bundle中找到 \(bundleFiles.count) 个Markdown文件")
        for file in bundleFiles {
            print("  - \(file.displayName) -> \(file.relativePath)")
        }
        
        return bundleFiles
    }
    
    /// 从Bundle文件创建MarkdownFile对象，根据文件名推断学科分类
    private func createMarkdownFileFromBundle(from url: URL) -> MarkdownFile? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            
            let size = resourceValues.fileSize ?? 0
            let modificationDate = resourceValues.contentModificationDate ?? Date()
            let name = url.lastPathComponent
            let fileExtension = url.pathExtension.lowercased()
            // 对于图片文件和XMind文件，保留扩展名；对于Markdown文件，去掉扩展名
            let displayName = ["jpg", "jpeg", "png", "gif", "webp", "xmind"].contains(fileExtension) ? 
                url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            
            // 根据文件名推断学科分类
            let subject = inferSubjectFromFileName(displayName)
            let relativePath = "datas/\(subject)/"
            
            return MarkdownFile(
                url: url,
                name: name,
                displayName: displayName,
                size: Int64(size),
                modificationDate: modificationDate,
                relativePath: relativePath,
                source: .bundle
            )
        } catch {
            print("❌ 创建MarkdownFile失败 \(url.path): \(error)")
            return nil
        }
    }
    
    /// 判断文件是否应该被包含（排除系统文件）
    private func shouldIncludeFile(_ url: URL) -> Bool {
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
    
    /// 根据文件名推断学科分类
    private func inferSubjectFromFileName(_ fileName: String) -> String {
        let name = fileName.lowercased()
        
        // 根据文件名中的关键词判断学科
        if name.contains("函数") || name.contains("极限") || name.contains("导数") || name.contains("微分") || name.contains("积分") || name.contains("高数") {
            return "高数"
        } else if name.contains("数据结构") || name.contains("算法") {
            return "数据结构算法"
        } else if name.contains("计算机") || name.contains("组成原理") {
            return "计算机组成原理"
        } else if name.contains("基础知识补充") {
            return "高数"  // 基础知识补充归类到高数
        } else {
            return "其他"
        }
    }
    
    /// 扫描Documents中的datas文件夹
    private func scanDocumentsDatasFolder() -> [MarkdownFile] {
        let documentsURL = getDocumentsDirectory()
        let datasURL = documentsURL.appendingPathComponent("datas")
        
        // 如果datas文件夹不存在，返回空数组
        guard FileManager.default.fileExists(atPath: datasURL.path) else {
            print("📁 Documents中没有找到datas文件夹，返回空数组")
            return []
        }
        
        let files = scanMarkdownFiles(in: datasURL, baseURL: datasURL, pathPrefix: "datas")
        print("📁 Documents/datas中找到 \(files.count) 个Markdown文件")
        
        return files
    }
    
    /// 递归扫描指定目录中的Markdown文件
    private func scanMarkdownFiles(in directory: URL, baseURL: URL, pathPrefix: String, source: FileSource = .documents) -> [MarkdownFile] {
        var files: [MarkdownFile] = []
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                
                if resourceValues.isDirectory == true {
                    // 递归扫描子文件夹
                    let subjectName = url.lastPathComponent
                    let subPathPrefix = pathPrefix + "/" + subjectName
                    files.append(contentsOf: scanMarkdownFiles(in: url, baseURL: baseURL, pathPrefix: subPathPrefix, source: source))
                } else if resourceValues.isRegularFile == true {
                    // 处理支持的文件类型，排除系统文件
                    if shouldIncludeFile(url) {
                        if let file = createMarkdownFileFromPath(url: url, baseURL: baseURL, pathPrefix: pathPrefix, source: source) {
                            files.append(file)
                        }
                    }
                }
            }
        } catch {
            print("❌ 扫描目录失败 \(directory.path): \(error)")
        }
        
        return files
    }
    
    /// 从文件路径创建MarkdownFile对象，保持正确的相对路径
    private func createMarkdownFileFromPath(url: URL, baseURL: URL, pathPrefix: String, source: FileSource) -> MarkdownFile? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            
            let size = resourceValues.fileSize ?? 0
            let modificationDate = resourceValues.contentModificationDate ?? Date()
            let name = url.lastPathComponent
            let fileExtension = url.pathExtension.lowercased()
            // 对于图片文件和XMind文件，保留扩展名；对于Markdown文件，去掉扩展名
            let displayName = ["jpg", "jpeg", "png", "gif", "webp", "xmind"].contains(fileExtension) ? 
                url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            
            // 计算相对路径 - 获取从baseURL到当前文件的相对路径
            let relativePath: String
            if url.path.hasPrefix(baseURL.path + "/") {
                let remainingPath = String(url.path.dropFirst(baseURL.path.count + 1))
                relativePath = pathPrefix + "/" + remainingPath
            } else {
                relativePath = pathPrefix + "/" + url.lastPathComponent
            }
            
            // 调试信息（仅在需要时启用）
            if fileExtension == "xmind" {
                print("📄 创建XMind文件调试信息:")
                print("  - 文件名: \(name)")
                print("  - 显示名: \(displayName)")
                print("  - 完整路径: \(url.path)")
                print("  - 相对路径: \(relativePath)")
            }
            
            return MarkdownFile(
                url: url,
                name: name,
                displayName: displayName,
                size: Int64(size),
                modificationDate: modificationDate,
                relativePath: relativePath,
                source: source
            )
        } catch {
            print("❌ 创建MarkdownFile失败 \(url.path): \(error)")
            return nil
        }
    }
} 
