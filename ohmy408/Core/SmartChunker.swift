//
//  SmartChunker.swift
//  ohmy408
//
//  智能分块器 - 专门处理Markdown内容的智能分块
//  保持内容结构完整性，优化渲染性能

import Foundation

/// 智能分块器 - 根据内容结构进行智能分块
struct SmartChunker {
    
    /// 内容分块 - 主入口方法
    static func chunk(_ content: String, targetSize: Int) async -> [String] {
        return await Task.detached(priority: .userInitiated) {
            return performIntelligentChunking(content: content, targetSize: targetSize)
        }.value
    }
    
    /// 执行智能分块
    private static func performIntelligentChunking(content: String, targetSize: Int) -> [String] {
        // 1. 按结构元素预分割
        let structuralElements = parseStructuralElements(content)
        
        // 2. 按目标大小合并元素
        let chunks = mergeElementsIntoChunks(elements: structuralElements, targetSize: targetSize)
        
        // 3. 优化分块边界
        let optimizedChunks = optimizeChunkBoundaries(chunks)
        
        return optimizedChunks
    }
    
    /// 解析结构化元素
    private static func parseStructuralElements(_ content: String) -> [StructuralElement] {
        var elements: [StructuralElement] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentElement: StructuralElement?
        var elementContent: [String] = []
        
        for line in lines {
            let elementType = determineElementType(line)
            
            // 如果元素类型改变，保存当前元素
            if let current = currentElement, current.type != elementType {
                if !elementContent.isEmpty {
                    elements.append(StructuralElement(
                        type: current.type,
                        content: elementContent.joined(separator: "\n"),
                        priority: current.priority
                    ))
                }
                elementContent.removeAll()
            }
            
            // 开始新元素
            if currentElement?.type != elementType {
                currentElement = StructuralElement(
                    type: elementType,
                    content: "",
                    priority: elementType.priority
                )
            }
            
            elementContent.append(line)
        }
        
        // 添加最后一个元素
        if let current = currentElement, !elementContent.isEmpty {
            elements.append(StructuralElement(
                type: current.type,
                content: elementContent.joined(separator: "\n"),
                priority: current.priority
            ))
        }
        
        return elements
    }
    
    /// 确定元素类型
    private static func determineElementType(_ line: String) -> ElementType {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // 标题
        if trimmed.hasPrefix("#") {
            return .heading
        }
        
        // 代码块
        if trimmed.hasPrefix("```") {
            return .codeBlock
        }
        
        // 数学公式块
        if trimmed.hasPrefix("$$") {
            return .mathBlock
        }
        
        // 列表
        if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("+") ||
           (trimmed.range(of: "^\\d+\\.", options: .regularExpression) != nil) {
            return .list
        }
        
        // 引用
        if trimmed.hasPrefix(">") {
            return .blockquote
        }
        
        // 表格
        if trimmed.contains("|") {
            return .table
        }
        
        // 分割线
        if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") {
            return .separator
        }
        
        // 空行
        if trimmed.isEmpty {
            return .emptyLine
        }
        
        // 默认为段落
        return .paragraph
    }
    
    /// 将元素合并为分块
    private static func mergeElementsIntoChunks(elements: [StructuralElement], targetSize: Int) -> [String] {
        var chunks: [String] = []
        var currentChunk: [StructuralElement] = []
        var currentSize = 0
        
        for element in elements {
            let elementSize = element.content.count
            
            // 检查是否应该开始新分块
            let shouldStartNewChunk = currentSize + elementSize > targetSize && 
                                    !currentChunk.isEmpty &&
                                    element.type.canSplit
            
            if shouldStartNewChunk {
                // 完成当前分块
                let chunkContent = currentChunk.map { $0.content }.joined(separator: "\n")
                if !chunkContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chunks.append(chunkContent)
                }
                
                currentChunk.removeAll()
                currentSize = 0
            }
            
            // 处理超大单个元素
            if elementSize > targetSize * 2 {
                // 如果当前分块不为空，先完成它
                if !currentChunk.isEmpty {
                    let chunkContent = currentChunk.map { $0.content }.joined(separator: "\n")
                    chunks.append(chunkContent)
                    currentChunk.removeAll()
                    currentSize = 0
                }
                
                // 分割超大元素
                let subChunks = splitLargeElement(element, targetSize: targetSize)
                chunks.append(contentsOf: subChunks)
            } else {
                currentChunk.append(element)
                currentSize += elementSize
            }
        }
        
        // 处理最后一个分块
        if !currentChunk.isEmpty {
            let chunkContent = currentChunk.map { $0.content }.joined(separator: "\n")
            if !chunkContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(chunkContent)
            }
        }
        
        return chunks
    }
    
    /// 分割大型元素
    private static func splitLargeElement(_ element: StructuralElement, targetSize: Int) -> [String] {
        let content = element.content
        let lines = content.components(separatedBy: .newlines)
        
        var subChunks: [String] = []
        var currentSubChunk: [String] = []
        var currentSize = 0
        
        for line in lines {
            let lineSize = line.count + 1 // +1 for newline
            
            if currentSize + lineSize > targetSize && !currentSubChunk.isEmpty {
                subChunks.append(currentSubChunk.joined(separator: "\n"))
                currentSubChunk.removeAll()
                currentSize = 0
            }
            
            currentSubChunk.append(line)
            currentSize += lineSize
        }
        
        if !currentSubChunk.isEmpty {
            subChunks.append(currentSubChunk.joined(separator: "\n"))
        }
        
        return subChunks
    }
    
    /// 优化分块边界
    private static func optimizeChunkBoundaries(_ chunks: [String]) -> [String] {
        var optimizedChunks: [String] = []
        
        for chunk in chunks {
            let optimized = optimizeChunkContent(chunk)
            optimizedChunks.append(optimized)
        }
        
        return optimizedChunks
    }
    
    /// 优化单个分块内容
    private static func optimizeChunkContent(_ chunk: String) -> String {
        var lines = chunk.components(separatedBy: .newlines)
        
        // 移除开头和结尾的空行（保留一个用于分隔）
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true && lines.count > 1 {
            lines.removeFirst()
        }
        
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true && lines.count > 1 {
            lines.removeLast()
        }
        
        // 确保代码块完整性
        let optimizedContent = ensureCodeBlockIntegrity(lines.joined(separator: "\n"))
        
        return optimizedContent
    }
    
    /// 确保代码块完整性
    private static func ensureCodeBlockIntegrity(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var codeBlockCount = 0
        var result: [String] = []
        
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                codeBlockCount += 1
            }
            result.append(line)
        }
        
        // 如果代码块不完整（奇数个```），添加闭合标记
        if codeBlockCount % 2 == 1 {
            result.append("```")
        }
        
        return result.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

/// 结构化元素
struct StructuralElement {
    let type: ElementType
    let content: String
    let priority: Int
}

/// 元素类型
enum ElementType {
    case heading
    case paragraph
    case codeBlock
    case mathBlock
    case list
    case blockquote
    case table
    case separator
    case emptyLine
    
    /// 优先级（数字越小优先级越高）
    var priority: Int {
        switch self {
        case .heading: return 1
        case .codeBlock: return 2
        case .mathBlock: return 2
        case .table: return 3
        case .blockquote: return 4
        case .list: return 5
        case .paragraph: return 6
        case .separator: return 7
        case .emptyLine: return 8
        }
    }
    
    /// 是否可以分割
    var canSplit: Bool {
        switch self {
        case .codeBlock, .mathBlock: return false
        case .heading: return false
        default: return true
        }
    }
}
