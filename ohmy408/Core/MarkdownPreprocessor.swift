//
//  MarkdownPreprocessor.swift
//  ohmy408
//
//  Created by AI Assistant on 2025-01-27.
//  预处理器 - 专门负责Markdown内容的预处理

import Foundation

/// Markdown预处理器 - 单一职责：内容预处理和优化
class MarkdownPreprocessor {
    
    // MARK: - Public Methods
    
    /// 预处理Markdown内容
    func process(_ content: String) -> String {
        var processedContent = content
        
        // 1. 基础清理
        processedContent = cleanupContent(processedContent)
        
        // 2. LaTeX公式预处理
        processedContent = preprocessLatexFormulas(processedContent)
        
        // 3. 代码块优化
        processedContent = optimizeCodeBlocks(processedContent)
        
        // 4. 表格优化
        processedContent = optimizeTables(processedContent)
        
        return processedContent
    }
    
    // MARK: - Private Methods
    
    /// 基础内容清理
    private func cleanupContent(_ content: String) -> String {
        return content
            .replacingOccurrences(of: "\r\n", with: "\n") // 统一换行符
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) // 去除首尾空白
    }
    
    /// LaTeX公式预处理
    private func preprocessLatexFormulas(_ content: String) -> String {
        var processedContent = content
        
        // 处理行内公式：$...$
        let inlinePattern = "\\$([^$]+?)\\$"
        if let inlineRegex = try? NSRegularExpression(pattern: inlinePattern) {
            let matches = inlineRegex.matches(in: processedContent, range: NSRange(processedContent.startIndex..., in: processedContent))
            
            // 从后往前替换，避免位置偏移
            for match in matches.reversed() {
                if let range = Range(match.range, in: processedContent) {
                    let formula = String(processedContent[range])
                    let processed = processInlineFormula(formula)
                    processedContent.replaceSubrange(range, with: processed)
                }
            }
        }
        
        // 处理块级公式：$$...$$
        let blockPattern = "\\$\\$([^$]+?)\\$\\$"
        if let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: .dotMatchesLineSeparators) {
            let matches = blockRegex.matches(in: processedContent, range: NSRange(processedContent.startIndex..., in: processedContent))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: processedContent) {
                    let formula = String(processedContent[range])
                    let processed = processBlockFormula(formula)
                    processedContent.replaceSubrange(range, with: processed)
                }
            }
        }
        
        return processedContent
    }
    
    /// 处理行内公式
    private func processInlineFormula(_ formula: String) -> String {
        // 简单清理：移除多余空格
        let cleaned = formula
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    /// 处理块级公式
    private func processBlockFormula(_ formula: String) -> String {
        // 确保块级公式前后有足够的空行
        let cleaned = formula
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return "\n\n" + cleaned + "\n\n"
    }
    
    /// 代码块优化
    private func optimizeCodeBlocks(_ content: String) -> String {
        var processedContent = content
        
        // 处理代码块，确保语法高亮标识正确
        let codeBlockPattern = "```(\\w*)?\\n([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern) {
            let matches = regex.matches(in: processedContent, range: NSRange(processedContent.startIndex..., in: processedContent))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: processedContent) {
                    let codeBlock = String(processedContent[range])
                    let optimized = optimizeCodeBlock(codeBlock)
                    processedContent.replaceSubrange(range, with: optimized)
                }
            }
        }
        
        return processedContent
    }
    
    /// 优化单个代码块
    private func optimizeCodeBlock(_ codeBlock: String) -> String {
        let lines = codeBlock.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return codeBlock }
        
        let firstLine = lines[0]  // ```language
        let lastLine = lines[lines.count - 1]  // ```
        let codeContent = Array(lines[1..<lines.count-1]).joined(separator: "\n")
        
        // 移除代码内容的过度缩进
        let trimmedContent = removeExcessIndentation(codeContent)
        
        return firstLine + "\n" + trimmedContent + "\n" + lastLine
    }
    
    /// 移除代码的过度缩进
    private func removeExcessIndentation(_ code: String) -> String {
        let lines = code.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return code }
        
        // 找到最小缩进
        var minIndent = Int.max
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            minIndent = min(minIndent, leadingSpaces)
        }
        
        if minIndent == Int.max || minIndent == 0 {
            return code
        }
        
        // 移除公共缩进
        let trimmedLines = lines.map { line in
            if line.count >= minIndent {
                return String(line.dropFirst(minIndent))
            } else {
                return line
            }
        }
        
        return trimmedLines.joined(separator: "\n")
    }
    
    /// 表格优化
    private func optimizeTables(_ content: String) -> String {
        var processedContent = content
        
        // 简单的表格检测和优化
        let lines = content.components(separatedBy: .newlines)
        var optimizedLines: [String] = []
        var inTable = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 检测表格行（包含 | 符号）
            if trimmed.contains("|") && !trimmed.hasPrefix("|") {
                inTable = true
                // 确保表格格式正确
                let optimizedLine = optimizeTableRow(line)
                optimizedLines.append(optimizedLine)
            } else {
                if inTable {
                    // 表格结束，添加空行
                    optimizedLines.append("")
                    inTable = false
                }
                optimizedLines.append(line)
            }
        }
        
        return optimizedLines.joined(separator: "\n")
    }
    
    /// 优化表格行
    private func optimizeTableRow(_ row: String) -> String {
        // 简单清理：规范化分隔符周围的空格
        return row
            .replacingOccurrences(of: " *\\| *", with: " | ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
