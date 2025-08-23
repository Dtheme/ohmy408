//
//  ContentComplexityAnalyzer.swift
//  ohmy408
//
//  内容复杂度分析器 - 分析Markdown内容复杂度
//  根据复杂度调整渲染策略和参数

import Foundation

/// 内容复杂度分析器
struct ContentComplexityAnalyzer {
    
    /// 分析内容复杂度
    static func analyze(_ content: String) async -> ContentComplexity {
        return await Task.detached(priority: .userInitiated) {
            return performComplexityAnalysis(content)
        }.value
    }
    
    /// 执行复杂度分析
    private static func performComplexityAnalysis(_ content: String) -> ContentComplexity {
        let metrics = calculateComplexityMetrics(content)
        let score = calculateComplexityScore(metrics)
        let level = determineComplexityLevel(score)
        
        return ContentComplexity(
            score: score,
            level: level,
            metrics: metrics
        )
    }
    
    /// 计算复杂度指标
    private static func calculateComplexityMetrics(_ content: String) -> ComplexityMetrics {
        let lines = content.components(separatedBy: .newlines)
        let characters = content.count
        
        var mathFormulaCount = 0
        var codeBlockCount = 0
        var tableCount = 0
        var imageCount = 0
        var linkCount = 0
        var headingCount = 0
        var listItemCount = 0
        
        var inCodeBlock = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 统计标题
            if trimmed.hasPrefix("#") {
                headingCount += 1
            }
            
            // 统计代码块
            if trimmed.hasPrefix("```") {
                if !inCodeBlock {
                    codeBlockCount += 1
                }
                inCodeBlock.toggle()
            }
            
            // 统计表格
            if trimmed.contains("|") && !inCodeBlock {
                tableCount += 1
            }
            
            // 统计列表项
            if (trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("+") ||
                trimmed.range(of: "^\\d+\\.", options: .regularExpression) != nil) && !inCodeBlock {
                listItemCount += 1
            }
        }
        
        // 统计数学公式
        mathFormulaCount += countMatches(in: content, pattern: "\\$[^$]+\\$")  // 行内公式
        mathFormulaCount += countMatches(in: content, pattern: "\\$\\$[^$]+\\$\\$") // 块级公式
        
        // 统计图片
        imageCount = countMatches(in: content, pattern: "!\\[[^\\]]*\\]\\([^)]+\\)")
        
        // 统计链接
        linkCount = countMatches(in: content, pattern: "\\[[^\\]]+\\]\\([^)]+\\)")
        
        return ComplexityMetrics(
            totalCharacters: characters,
            totalLines: lines.count,
            headingCount: headingCount,
            mathFormulaCount: mathFormulaCount,
            codeBlockCount: codeBlockCount,
            tableCount: tableCount,
            imageCount: imageCount,
            linkCount: linkCount,
            listItemCount: listItemCount
        )
    }
    
    /// 计算复杂度评分
    private static func calculateComplexityScore(_ metrics: ComplexityMetrics) -> Float {
        var score: Float = 0
        
        // 基础内容复杂度 (40%)
        let contentDensity = Float(metrics.totalCharacters) / Float(max(metrics.totalLines, 1))
        score += contentDensity * 0.4
        
        // 数学公式复杂度 (20%)
        let mathComplexity = Float(metrics.mathFormulaCount) * 10
        score += mathComplexity * 0.2
        
        // 代码块复杂度 (15%)
        let codeComplexity = Float(metrics.codeBlockCount) * 8
        score += codeComplexity * 0.15
        
        // 表格复杂度 (10%)
        let tableComplexity = Float(metrics.tableCount) * 5
        score += tableComplexity * 0.1
        
        // 媒体内容复杂度 (10%)
        let mediaComplexity = Float(metrics.imageCount + metrics.linkCount) * 3
        score += mediaComplexity * 0.1
        
        // 结构复杂度 (5%)
        let structureComplexity = Float(metrics.headingCount + metrics.listItemCount) * 2
        score += structureComplexity * 0.05
        
        return min(score, 1000) // 限制最大值
    }
    
    /// 确定复杂度等级
    private static func determineComplexityLevel(_ score: Float) -> ComplexityLevel {
        switch score {
        case 0..<50:
            return .low
        case 50..<150:
            return .medium
        case 150..<300:
            return .high
        default:
            return .extreme
        }
    }
    
    /// 统计正则表达式匹配数量
    private static func countMatches(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return 0
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}

// MARK: - Supporting Types

/// 内容复杂度
struct ContentComplexity {
    let score: Float
    let level: ComplexityLevel
    let metrics: ComplexityMetrics
    
    /// 根据复杂度调整分块大小
    func adjustedChunkSize(base: Int) -> Int {
        let multiplier: Float
        
        switch level {
        case .low:
            multiplier = 1.5    // 简单内容可以用更大的分块
        case .medium:
            multiplier = 1.0    // 中等复杂度保持原始分块大小
        case .high:
            multiplier = 0.7    // 高复杂度减小分块大小
        case .extreme:
            multiplier = 0.5    // 极高复杂度显著减小分块
        }
        
        return max(Int(Float(base) * multiplier), 5000) // 最小5K
    }
    
    /// 建议的渲染延迟
    var recommendedRenderDelay: TimeInterval {
        switch level {
        case .low:
            return 0.01      // 10ms
        case .medium:
            return 0.016     // 16ms (60FPS)
        case .high:
            return 0.033     // 33ms (30FPS)
        case .extreme:
            return 0.05      // 50ms (20FPS)
        }
    }
}

/// 复杂度等级
enum ComplexityLevel {
    case low
    case medium
    case high
    case extreme
    
    var description: String {
        switch self {
        case .low: return "低复杂度"
        case .medium: return "中等复杂度"
        case .high: return "高复杂度"
        case .extreme: return "极高复杂度"
        }
    }
}

/// 复杂度指标
struct ComplexityMetrics {
    let totalCharacters: Int
    let totalLines: Int
    let headingCount: Int
    let mathFormulaCount: Int
    let codeBlockCount: Int
    let tableCount: Int
    let imageCount: Int
    let linkCount: Int
    let listItemCount: Int
    
    var description: String {
        return """
        总字符数: \(totalCharacters)
        总行数: \(totalLines)
        标题: \(headingCount)
        数学公式: \(mathFormulaCount)
        代码块: \(codeBlockCount)
        表格: \(tableCount)
        图片: \(imageCount)
        链接: \(linkCount)
        列表项: \(listItemCount)
        """
    }
}
