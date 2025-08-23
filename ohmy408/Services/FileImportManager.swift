//
//  FileImportManager.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import PDFKit

/// 文件导入管理器 - 负责从文件系统导入各种格式文件的功能
class FileImportManager: NSObject {
    
    static let shared = FileImportManager()
    
    private override init() {
        super.init()
    }
    
    // MARK: - 公共方法
    
    /// 显示文件选择器
    /// - Parameters:
    ///   - presentingViewController: 展示文件选择器的视图控制器
    ///   - completion: 完成回调，返回成功状态和消息
    func presentFileImporter(from presentingViewController: UIViewController, completion: @escaping (Bool, String?) -> Void) {
        // 保存回调和视图控制器引用
        self.importCompletion = completion
        self.presentingViewController = presentingViewController
        
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: getSupportedContentTypes())
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        documentPicker.modalPresentationStyle = .formSheet
        
        presentingViewController.present(documentPicker, animated: true)
    }
    
    /// 获取支持的文件类型
    func getSupportedFileTypes() -> [String] {
        return ["Markdown (.md)", "文本文件 (.txt)", "PDF文档 (.pdf)", "图片文件 (.jpg, .png, .gif, .webp)", "XMind思维导图 (.xmind)"]
    }
    
    // MARK: - 私有属性
    
    private var importCompletion: ((Bool, String?) -> Void)?
    private weak var presentingViewController: UIViewController?
    private var pendingImportURLs: [URL] = []
    
    // MARK: - 私有方法
    
    /// 获取支持的内容类型
    private func getSupportedContentTypes() -> [UTType] {
        return [
            UTType.plainText,           // .txt
            UTType.pdf,                 // .pdf
            UTType("net.daringfireball.markdown") ?? UTType.plainText,  // .md
            UTType.image,               // 通用图片类型
            UTType.jpeg,                // .jpg, .jpeg
            UTType.png,                 // .png
            UTType.gif,                 // .gif
            UTType.webP,                // .webp
            UTType("org.xmind.xmind") ?? UTType.data  // .xmind
        ]
    }
    
    /// 处理导入的文件
    private func processImportedFiles(_ urls: [URL], targetSubject: String) {
        print("🔄 开始处理导入文件")
        print("  - 文件数量: \(urls.count)")
        print("  - 目标科目: '\(targetSubject)'")
        
        var successCount = 0
        var errors: [String] = []
        
        let documentsURL = getDocumentsDirectory()
        let datasURL = documentsURL.appendingPathComponent("datas")
        let targetSubjectURL = datasURL.appendingPathComponent(targetSubject)
        
        print("📁 路径信息:")
        print("  - Documents目录: \(documentsURL.path)")
        print("  - datas目录: \(datasURL.path)")
        print("  - 目标科目目录: \(targetSubjectURL.path)")
        
        // 确保datas目录存在
        do {
            if !FileManager.default.fileExists(atPath: datasURL.path) {
                try FileManager.default.createDirectory(at: datasURL, withIntermediateDirectories: true)
                print("✅ 创建datas目录: \(datasURL.path)")
            } else {
                print("📁 datas目录已存在: \(datasURL.path)")
            }
            
            // 确保目标科目目录存在
            if !FileManager.default.fileExists(atPath: targetSubjectURL.path) {
                try FileManager.default.createDirectory(at: targetSubjectURL, withIntermediateDirectories: true)
                print("✅ 创建科目目录: \(targetSubjectURL.path)")
            } else {
                print("📁 科目目录已存在: \(targetSubjectURL.path)")
            }
        } catch {
            let errorMsg = "创建目录失败: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            importCompletion?(false, errorMsg)
            return
        }
        
        for url in urls {
            do {
                // 开始访问安全范围资源
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let fileName = url.lastPathComponent
                let fileExtension = url.pathExtension.lowercased()
                
                print("📄 处理文件: \(fileName) (类型: \(fileExtension))")
                
                switch fileExtension {
                case "md":
                    try importMarkdownFile(from: url, to: targetSubjectURL, targetSubject: targetSubject)
                    successCount += 1
                    print("✅ 成功导入Markdown文件: \(fileName) 到科目: \(targetSubject)")
                    
                case "txt":
                    try importTextFile(from: url, to: targetSubjectURL, targetSubject: targetSubject)
                    successCount += 1
                    print("✅ 成功导入文本文件: \(fileName) 到科目: \(targetSubject)")
                    
                case "pdf":
                    try importPDFFile(from: url, to: targetSubjectURL, targetSubject: targetSubject)
                    successCount += 1
                    print("✅ 成功导入PDF文件: \(fileName) 到科目: \(targetSubject)")
                    
                case "jpg", "jpeg", "png", "gif", "webp":
                    try importImageFile(from: url, to: targetSubjectURL, targetSubject: targetSubject)
                    successCount += 1
                    print("✅ 成功导入图片文件: \(fileName) 到科目: \(targetSubject)")
                    
                case "xmind":
                    try importXMindFile(from: url, to: targetSubjectURL, targetSubject: targetSubject)
                    successCount += 1
                    print("✅ 成功导入XMind文件: \(fileName) 到科目: \(targetSubject)")
                    
                default:
                    errors.append("不支持的文件格式: \(fileName)")
                    print("❌ 不支持的文件格式: \(fileName)")
                }
                
            } catch {
                let errorMsg = "导入文件 \(url.lastPathComponent) 失败: \(error.localizedDescription)"
                errors.append(errorMsg)
                print("❌ \(errorMsg)")
            }
        }
        
        // 回调结果
        DispatchQueue.main.async {
            if successCount > 0 {
                let message = errors.isEmpty ? 
                    "成功导入 \(successCount) 个文件" : 
                    "成功导入 \(successCount) 个文件，\(errors.count) 个失败"
                self.importCompletion?(true, message)
            } else {
                let message = errors.isEmpty ? "没有文件被导入" : errors.joined(separator: "\n")
                self.importCompletion?(false, message)
            }
        }
    }
    
    /// 导入Markdown文件
    private func importMarkdownFile(from sourceURL: URL, to targetSubjectDirectory: URL, targetSubject: String) throws {
        let fileName = sourceURL.lastPathComponent
        let destinationURL = targetSubjectDirectory.appendingPathComponent(fileName)
        
        // 调试信息
        print("📁 导入Markdown文件调试信息:")
        print("  - 源文件: \(sourceURL.path)")
        print("  - 目标科目: '\(targetSubject)'")
        print("  - 科目目录: \(targetSubjectDirectory.path)")
        print("  - 目标文件: \(destinationURL.path)")
        
        // 如果文件已存在，生成新名称
        let finalDestinationURL = generateUniqueFileName(for: destinationURL)
        print("  - 最终文件: \(finalDestinationURL.path)")
        
        // 复制文件
        try FileManager.default.copyItem(at: sourceURL, to: finalDestinationURL)
        
        print("✅ Markdown文件成功导入到: \(finalDestinationURL.path)")
    }
    
    /// 导入文本文件（转换为Markdown）
    private func importTextFile(from sourceURL: URL, to targetSubjectDirectory: URL, targetSubject: String) throws {
        let content = try String(contentsOf: sourceURL, encoding: .utf8)
        let fileName = sourceURL.deletingPathExtension().lastPathComponent + ".md"
        let destinationURL = targetSubjectDirectory.appendingPathComponent(fileName)
        
        // 调试信息
        print("📄 导入文本文件调试信息:")
        print("  - 源文件: \(sourceURL.path)")
        print("  - 目标科目: '\(targetSubject)'")
        print("  - 科目目录: \(targetSubjectDirectory.path)")
        print("  - 目标文件: \(destinationURL.path)")
        
        // 如果文件已存在，生成新名称
        let finalDestinationURL = generateUniqueFileName(for: destinationURL)
        print("  - 最终文件: \(finalDestinationURL.path)")
        
        // 将文本内容包装为Markdown格式
        let markdownContent = """
        # \(sourceURL.deletingPathExtension().lastPathComponent)
        
        \(content)
        """
        
        // 写入文件
        try markdownContent.write(to: finalDestinationURL, atomically: true, encoding: .utf8)
        
        print("✅ 文本文件成功导入到: \(finalDestinationURL.path)")
    }
    
    /// 导入PDF文件（提取文本转换为Markdown）
    private func importPDFFile(from sourceURL: URL, to targetSubjectDirectory: URL, targetSubject: String) throws {
        guard let pdfDocument = PDFDocument(url: sourceURL) else {
            throw ImportError.pdfReadFailed
        }
        
        var extractedText = ""
        let pageCount = pdfDocument.pageCount
        
        for pageIndex in 0..<pageCount {
            if let page = pdfDocument.page(at: pageIndex) {
                if let pageText = page.string {
                    extractedText += "## 第 \(pageIndex + 1) 页\n\n"
                    extractedText += pageText
                    extractedText += "\n\n---\n\n"
                }
            }
        }
        
        if extractedText.isEmpty {
            throw ImportError.pdfNoText
        }
        
        let fileName = sourceURL.deletingPathExtension().lastPathComponent + ".md"
        let destinationURL = targetSubjectDirectory.appendingPathComponent(fileName)
        
        // 调试信息
        print("📋 导入PDF文件调试信息:")
        print("  - 源文件: \(sourceURL.path)")
        print("  - 目标科目: '\(targetSubject)'")
        print("  - 科目目录: \(targetSubjectDirectory.path)")
        print("  - 目标文件: \(destinationURL.path)")
        
        // 如果文件已存在，生成新名称
        let finalDestinationURL = generateUniqueFileName(for: destinationURL)
        print("  - 最终文件: \(finalDestinationURL.path)")
        
        // 创建Markdown内容
        let markdownContent = """
        # \(sourceURL.deletingPathExtension().lastPathComponent)
        
        > 从PDF文档提取的内容
        
        \(extractedText)
        """
        
        // 写入文件
        try markdownContent.write(to: finalDestinationURL, atomically: true, encoding: .utf8)
        
        print("✅ PDF文件成功导入到: \(finalDestinationURL.path)")
    }
    
    /// 导入图片文件（创建包含图片的Markdown文件）
    private func importImageFile(from sourceURL: URL, to targetSubjectDirectory: URL, targetSubject: String) throws {
        let fileName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension.lowercased()
        
        // 调试信息
        print("🖼️ 导入图片文件调试信息:")
        print("  - 源文件: \(sourceURL.path)")
        print("  - 目标科目: '\(targetSubject)'")
        print("  - 科目目录: \(targetSubjectDirectory.path)")
        
        // 创建images子目录
        let imagesDirectory = targetSubjectDirectory.appendingPathComponent("images")
        if !FileManager.default.fileExists(atPath: imagesDirectory.path) {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            print("✅ 创建images目录: \(imagesDirectory.path)")
        }
        
        // 复制图片文件到images目录
        let imageDestinationURL = imagesDirectory.appendingPathComponent(fileName)
        let finalImageURL = generateUniqueFileName(for: imageDestinationURL)
        try FileManager.default.copyItem(at: sourceURL, to: finalImageURL)
        print("✅ 图片文件复制到: \(finalImageURL.path)")
        
        // 创建对应的Markdown文件
        let markdownFileName = sourceURL.deletingPathExtension().lastPathComponent + ".md"
        let markdownDestinationURL = targetSubjectDirectory.appendingPathComponent(markdownFileName)
        let finalMarkdownURL = generateUniqueFileName(for: markdownDestinationURL)
        
        // 获取相对路径（相对于Markdown文件的位置）
        let relativePath = "images/\(finalImageURL.lastPathComponent)"
        
        // 创建包含图片的Markdown内容
        let markdownContent = """
        # \(sourceURL.deletingPathExtension().lastPathComponent)
        
        > 图片文件：\(fileName)
        > 格式：\(fileExtension.uppercased())
        
        ![图片](\(relativePath))
        
        ---
        
        **文件信息：**
        - 原始文件名：\(fileName)
        - 文件格式：\(fileExtension.uppercased())
        - 导入时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))
        """
        
        // 写入Markdown文件
        try markdownContent.write(to: finalMarkdownURL, atomically: true, encoding: .utf8)
        
        print("✅ 图片Markdown文件创建: \(finalMarkdownURL.path)")
        print("  - 图片路径: \(relativePath)")
    }
    
    /// 导入XMind文件
    private func importXMindFile(from sourceURL: URL, to targetSubjectDirectory: URL, targetSubject: String) throws {
        let fileName = sourceURL.lastPathComponent
        let destinationURL = targetSubjectDirectory.appendingPathComponent(fileName)
        
        // 调试信息
        print("🧠 导入XMind文件调试信息:")
        print("  - 源文件: \(sourceURL.path)")
        print("  - 目标科目: '\(targetSubject)'")
        print("  - 科目目录: \(targetSubjectDirectory.path)")
        print("  - 目标文件: \(destinationURL.path)")
        
        // 如果文件已存在，生成新名称
        let finalDestinationURL = generateUniqueFileName(for: destinationURL)
        print("  - 最终文件: \(finalDestinationURL.path)")
        
        // 复制XMind文件
        try FileManager.default.copyItem(at: sourceURL, to: finalDestinationURL)
        
        print("✅ XMind文件成功导入到: \(finalDestinationURL.path)")
    }
    
    /// 生成唯一的文件名
    private func generateUniqueFileName(for url: URL) -> URL {
        var finalURL = url
        var counter = 1
        
        while FileManager.default.fileExists(atPath: finalURL.path) {
            let fileName = url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension
            let newFileName = "\(fileName)_\(counter).\(fileExtension)"
            finalURL = url.deletingLastPathComponent().appendingPathComponent(newFileName)
            counter += 1
        }
        
        return finalURL
    }
    
    /// 获取Documents目录
    private func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - UIDocumentPickerDelegate
extension FileImportManager: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // 保存待导入的文件URLs
        pendingImportURLs = urls
        
        // 显示科目选择界面
        showSubjectSelection()
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        importCompletion?(false, "用户取消了文件选择")
    }
    
    /// 显示科目选择界面
    private func showSubjectSelection() {
        guard let presentingVC = presentingViewController else {
            importCompletion?(false, "无法显示科目选择界面")
            return
        }
        
        print("📋 准备显示科目选择界面，待导入文件数量: \(pendingImportURLs.count)")
        for (index, url) in pendingImportURLs.enumerated() {
            print("  文件\(index + 1): \(url.lastPathComponent)")
        }
        
        let subjectSelectionVC = SubjectSelectionViewController()
        
        subjectSelectionVC.onSubjectSelected = { [weak self] selectedSubject in
            // 用户选择了科目，开始导入文件
            print("🎯 用户选择了科目: '\(selectedSubject)'")
            print("📁 即将导入到科目目录: \(selectedSubject)")
            
            presentingVC.dismiss(animated: true) {
                guard let self = self else {
                    print("❌ FileImportManager实例已释放")
                    return
                }
                
                print("🚀 开始处理文件导入，目标科目: '\(selectedSubject)'")
                self.processImportedFiles(self.pendingImportURLs, targetSubject: selectedSubject)
            }
        }
        
        subjectSelectionVC.onCancel = { [weak self] in
            // 用户取消了科目选择
            print("❌ 用户取消了科目选择")
            presentingVC.dismiss(animated: true) {
                self?.importCompletion?(false, "用户取消了科目选择")
            }
        }
        
        presentingVC.present(subjectSelectionVC, animated: true)
    }
}

// MARK: - 错误定义
enum ImportError: LocalizedError {
    case pdfReadFailed
    case pdfNoText
    
    var errorDescription: String? {
        switch self {
        case .pdfReadFailed:
            return "无法读取PDF文件"
        case .pdfNoText:
            return "PDF文件中没有可提取的文本"
        }
    }
} 
