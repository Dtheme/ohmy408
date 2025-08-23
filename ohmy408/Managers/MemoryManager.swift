//
//  MemoryManagementSystem.swift
//  ohmy408
//
//  内存管理系统 - 监控内存压力，智能管理内存使用
//  支持实时监控、压力检测、自动清理

import Foundation
import os.log

/// 内存压力监控器
class MemoryPressureMonitor {
    
    private let logger = Logger(subsystem: "com.ohmy408.memory", category: "PressureMonitor")
    private let pressureHandler: (MemoryPressureLevel) -> Void
    private var monitoringTimer: Timer?
    private let checkInterval: TimeInterval = 1.0 // 每秒检查一次
    private var lastPressure: MemoryPressureLevel = .normal
    
    init(pressureHandler: @escaping (MemoryPressureLevel) -> Void) {
        self.pressureHandler = pressureHandler
    }
    
    /// 开始监控
    func start() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
        logger.info("🔍 内存压力监控已启动")
    }
    
    /// 停止监控
    func stop() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        logger.info("内存压力监控已停止")
    }
    
    /// 检查内存压力
    private func checkMemoryPressure() {
        let memoryInfo = SystemMemoryMonitor.getMemoryInfo()
        let pressure = determinePressureLevel(memoryInfo)
        
        // 只有在压力等级变化时才通知
        if pressure != self.lastPressure {
            logger.info("内存压力变化: \(String(describing: self.lastPressure)) -> \(String(describing: pressure))")
            pressureHandler(pressure)
            self.lastPressure = pressure
        }
    }
    
    /// 确定压力等级
    private func determinePressureLevel(_ info: MemoryInfo) -> MemoryPressureLevel {
        let usagePercentage = Float(info.usedMemory) / Float(info.totalMemory)
        
        switch usagePercentage {
        case 0..<0.7:
            return .normal
        case 0.7..<0.85:
            return .warning
        default:
            return .critical
        }
    }
    
    deinit {
        stop()
    }
}

/// 系统内存监控器
struct SystemMemoryMonitor {
    
    /// 获取当前内存使用情况
    static func currentUsage() async -> Int {
        return await Task.detached(priority: .utility) {
            return Int(getMemoryInfo().usedMemory)
        }.value
    }
    
    /// 获取详细内存信息
    static func getMemoryInfo() -> MemoryInfo {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = info.resident_size
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            
            return MemoryInfo(
                totalMemory: totalMemory,
                usedMemory: usedMemory,
                availableMemory: totalMemory - usedMemory,
                pressureLevel: determinePressure(used: usedMemory, total: totalMemory)
            )
        } else {
            // 返回默认值
            return MemoryInfo(
                totalMemory: ProcessInfo.processInfo.physicalMemory,
                usedMemory: 0,
                availableMemory: ProcessInfo.processInfo.physicalMemory,
                pressureLevel: .normal
            )
        }
    }
    
    /// 获取内存使用详情（调试用）
    static func getDetailedMemoryStats() -> String {
        let info = getMemoryInfo()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        
        return """
        📊 内存使用详情:
        总内存: \(formatter.string(fromByteCount: Int64(info.totalMemory)))
        已用内存: \(formatter.string(fromByteCount: Int64(info.usedMemory)))
        可用内存: \(formatter.string(fromByteCount: Int64(info.availableMemory)))
        使用率: \(String(format: "%.1f", Float(info.usedMemory) / Float(info.totalMemory) * 100))%
        压力等级: \(info.pressureLevel)
        """
    }
    
    private static func determinePressure(used: UInt64, total: UInt64) -> MemoryPressureLevel {
        let usage = Float(used) / Float(total)
        
        switch usage {
        case 0..<0.7:
            return .normal
        case 0.7..<0.85:
            return .warning
        default:
            return .critical
        }
    }
}

/// 内存信息结构
struct MemoryInfo {
    let totalMemory: UInt64
    let usedMemory: UInt64  
    let availableMemory: UInt64
    let pressureLevel: MemoryPressureLevel
}

/// 智能内存管理器
@MainActor
class SmartMemoryManager: ObservableObject {
    
    // MARK: - Instance Properties  
    private var lastPressure: MemoryPressureLevel = .normal
    
    private let logger = Logger(subsystem: "com.ohmy408.memory", category: "SmartManager")
    
    @Published var memoryInfo = MemoryInfo(totalMemory: 0, usedMemory: 0, availableMemory: 0, pressureLevel: .normal)
    @Published var isUnderMemoryPressure = false
    
    private var monitor: MemoryPressureMonitor?
    private var cleanupHandlers: [() async -> Void] = []
    
    init() {
        setupMemoryMonitoring()
    }
    
    /// 注册清理处理器
    func registerCleanupHandler(_ handler: @escaping () async -> Void) {
        cleanupHandlers.append(handler)
    }
    
    /// 强制内存清理
    func forceMemoryCleanup() async {
        logger.info("🧹 执行强制内存清理")
        
        // 执行所有注册的清理处理器
        for handler in cleanupHandlers {
            await handler()
        }
        
        // 系统级清理
        await performSystemCleanup()
        
        // 更新内存信息
        updateMemoryInfo()
        
        logger.info("内存清理完成")
    }
    
    /// 检查是否应该暂停操作
    func shouldPauseForMemoryPressure() -> Bool {
        return memoryInfo.pressureLevel == .critical
    }
    
    /// 获取推荐的分块大小（基于内存压力）
    func getRecommendedChunkSize(base: Int) -> Int {
        switch memoryInfo.pressureLevel {
        case .normal:
            return base
        case .warning:
            return Int(Float(base) * 0.7)
        case .critical:
            return Int(Float(base) * 0.5)
        }
    }
    
    private func setupMemoryMonitoring() {
        monitor = MemoryPressureMonitor { [weak self] pressure in
            Task { @MainActor in
                self?.handleMemoryPressure(pressure)
            }
        }
        monitor?.start()
        
        updateMemoryInfo()
    }
    
    private func handleMemoryPressure(_ pressure: MemoryPressureLevel) {
        isUnderMemoryPressure = pressure != .normal
        updateMemoryInfo()
        
        switch pressure {
        case .normal:
            logger.info("内存压力正常")
            
        case .warning:
            logger.warning("内存压力警告，开始清理")
            Task {
                await performLightweightCleanup()
            }
            
        case .critical:
            logger.error("内存压力严重，执行深度清理")
            Task {
                await forceMemoryCleanup()
            }
        }
    }
    
    private func updateMemoryInfo() {
        memoryInfo = SystemMemoryMonitor.getMemoryInfo()
    }
    
    private func performLightweightCleanup() async {
        logger.info("🧽 执行轻量级内存清理")
        
        // 清理部分缓存
        await AdvancedCacheService.shared.clearMemoryCache()
        
        // 请求垃圾回收
        autoreleasepool {
            // 空的自动释放池，强制清理
        }
    }
    
    private func performSystemCleanup() async {
        logger.info("执行系统级内存清理")
        
        // 执行所有清理操作
        await performLightweightCleanup()
        
        // 强制图像缓存清理
        if #available(iOS 13.0, *) {
            URLSession.shared.invalidateAndCancel()
        }
        
        // 其他系统级清理操作...
    }
    
    deinit {
        monitor?.stop()
    }
}

/// 内容流处理器 - 用于超大文件的流式处理
struct ContentStream: Sequence {
    private let content: String
    private let bufferSize: Int
    
    init(content: String, bufferSize: Int) {
        self.content = content
        self.bufferSize = bufferSize
    }
    
    var bufferCount: Int {
        return (content.count + bufferSize - 1) / bufferSize
    }
    
    func makeIterator() -> ContentStreamIterator {
        return ContentStreamIterator(content: content, bufferSize: bufferSize)
    }
}

/// 内容流迭代器
struct ContentStreamIterator: IteratorProtocol {
    private let content: String
    private let bufferSize: Int
    private var currentIndex: String.Index
    private let endIndex: String.Index
    
    init(content: String, bufferSize: Int) {
        self.content = content
        self.bufferSize = bufferSize
        self.currentIndex = content.startIndex
        self.endIndex = content.endIndex
    }
    
    mutating func next() -> String? {
        guard currentIndex < endIndex else {
            return nil
        }
        
        // 计算下一个缓冲区的结束位置
        let nextIndex = content.index(currentIndex, offsetBy: bufferSize, limitedBy: endIndex) ?? endIndex
        
        // 提取缓冲区内容
        let buffer = String(content[currentIndex..<nextIndex])
        
        // 更新索引
        currentIndex = nextIndex
        
        return buffer
    }
}

/// 高级预处理器 - 支持流式和分块处理
struct AdvancedPreprocessor {
    
    /// 处理完整内容
    static func process(_ content: String) -> String {
        return content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 处理单个分块
    static func processChunk(_ chunk: String) async -> String {
        return await Task.detached(priority: .userInitiated) {
            return process(chunk)
        }.value
    }
    
    /// 处理流缓冲区
    static func processStreamBuffer(_ buffer: String) async -> String {
        return await Task.detached(priority: .utility) {
            return process(buffer)
        }.value
    }
}
