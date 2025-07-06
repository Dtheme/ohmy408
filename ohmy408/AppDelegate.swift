//
//  AppDelegate.swift
//  ohmy408
//
//  Created by dzw on 1/22/25.
//

import UIKit

// MARK: - 通知名称扩展
extension Notification.Name {
    static let coldStartSyncCompleted = Notification.Name("coldStartSyncCompleted")
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // 初始化主题管理器
        initializeThemeManager()
        
        // 初始化文件系统
        initializeFileSystem()
        
        // 执行冷启动同步检查
        performColdStartSync()
        
        return true
    }
    
    // MARK: - 主题管理器初始化
    
    /// 初始化主题管理器
    private func initializeThemeManager() {
        // 获取主题管理器实例并触发初始化
        let _ = ThemeManager.shared
        print("🎨 App启动时主题管理器已初始化")
    }
    
    // MARK: - 文件系统初始化
    
    /// 初始化文件系统，创建必要的目录结构
    private func initializeFileSystem() {
        // 只创建Documents/datas目录，不复制文件
        // 文件复制将在需要时（如上传到iCloud时）进行
        MarkdownFileManager.shared.createDatasDirectoryIfNeeded()
    }
    

    
    // MARK: - 冷启动同步
    
    /// 执行冷启动同步检查
    private func performColdStartSync() {
        // 延迟执行，确保应用完全启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            CloudSyncManager.shared.performColdStartSync { success, message in
                if success {
                    print("🎉 冷启动同步成功: \(message ?? "无消息")")
                    // 发送通知，通知UI更新
                    NotificationCenter.default.post(name: .coldStartSyncCompleted, object: message)
                } else {
                    print("⚠️ 冷启动同步失败: \(message ?? "未知错误")")
                    // 可以选择是否显示错误提示给用户
                }
            }
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

