//
//  ToastManager.swift
//  ohmy408
//
//  Created by dzw on 2025-01-27.
//

import UIKit
import SnapKit

/// Toast类型枚举
enum ToastType {
    case success
    case error
    case info
    case warning
    
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var backgroundColor: UIColor {
        switch self {
        case .success:
            return .systemGreen
        case .error:
            return .systemRed
        case .info:
            return .systemBlue
        case .warning:
            return .systemOrange
        }
    }
}

/// Toast位置枚举
enum ToastPosition {
    case top
    case center
    case bottom
    
    var offset: CGFloat {
        switch self {
        case .top:
            return 20
        case .center:
            return 0
        case .bottom:
            return -20
        }
    }
}

/// 优雅的Toast管理器 - 负责显示各种类型的提示消息
class ToastManager {
    
    static let shared = ToastManager()
    
    private var currentToast: ToastView?
    private let animationDuration: TimeInterval = 0.3
    private let displayDuration: TimeInterval = 3.0
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 显示成功Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - in: 显示的视图
    ///   - position: 显示位置
    func showSuccess(_ message: String, in view: UIView, position: ToastPosition = .top) {
        showToast(message: message, type: .success, in: view, position: position)
    }
    
    /// 显示错误Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - in: 显示的视图
    ///   - position: 显示位置
    func showError(_ message: String, in view: UIView, position: ToastPosition = .top) {
        showToast(message: message, type: .error, in: view, position: position)
    }
    
    /// 显示信息Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - in: 显示的视图
    ///   - position: 显示位置
    func showInfo(_ message: String, in view: UIView, position: ToastPosition = .top) {
        showToast(message: message, type: .info, in: view, position: position)
    }
    
    /// 显示警告Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - in: 显示的视图
    ///   - position: 显示位置
    func showWarning(_ message: String, in view: UIView, position: ToastPosition = .top) {
        showToast(message: message, type: .warning, in: view, position: position)
    }
    
    /// 隐藏当前Toast
    func hideCurrentToast() {
        guard let toast = currentToast else { return }
        hideToast(toast)
    }
    
    // MARK: - 私有方法
    
    /// 显示Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - type: Toast类型
    ///   - view: 显示的视图
    ///   - position: 显示位置
    private func showToast(message: String, type: ToastType, in view: UIView, position: ToastPosition) {
        // 隐藏当前Toast
        hideCurrentToast()
        
        // 创建新Toast
        let toast = ToastView(message: message, type: type)
        currentToast = toast
        
        view.addSubview(toast)
        setupToastConstraints(toast: toast, in: view, position: position)
        
        // 显示动画
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: -20)
        
        UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.curveEaseOut]) {
            toast.alpha = 1
            toast.transform = .identity
        }
        
        // 自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
            if self.currentToast == toast {
                self.hideToast(toast)
            }
        }
    }
    
    /// 设置Toast约束
    /// - Parameters:
    ///   - toast: Toast视图
    ///   - view: 父视图
    ///   - position: 显示位置
    private func setupToastConstraints(toast: ToastView, in view: UIView, position: ToastPosition) {
        toast.snp.makeConstraints { make in
            make.centerX.equalTo(view)
            make.leading.greaterThanOrEqualTo(view).offset(20)
            make.trailing.lessThanOrEqualTo(view).offset(-20)
        
        switch position {
        case .top:
                make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(position.offset)
        case .center:
                make.centerY.equalTo(view).offset(position.offset)
        case .bottom:
                make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(position.offset)
            }
        }
    }
    
    /// 隐藏Toast
    /// - Parameter toast: 要隐藏的Toast
    private func hideToast(_ toast: ToastView) {
        UIView.animate(withDuration: animationDuration, animations: {
            toast.alpha = 0
            toast.transform = CGAffineTransform(translationX: 0, y: -20)
        }) { _ in
            toast.removeFromSuperview()
            if self.currentToast == toast {
                self.currentToast = nil
            }
        }
    }
}

// MARK: - Toast视图

/// Toast视图组件
private class ToastView: UIView {
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        return imageView
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .left
        return label
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = false
        
        // 添加阴影
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.layer.shadowOpacity = 0.15
        
        return view
    }()
    
    init(message: String, type: ToastType) {
        super.init(frame: .zero)
        setupUI(message: message, type: type)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI(message: String, type: ToastType) {
        backgroundColor = .clear
        
        // 设置容器背景色
        containerView.backgroundColor = type.backgroundColor.withAlphaComponent(0.95)
        
        // 设置图标
        iconImageView.image = UIImage(systemName: type.icon)
        
        // 设置消息
        messageLabel.text = message
        
        // 添加子视图
        addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(messageLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        containerView.snp.makeConstraints { make in
            make.edges.equalTo(self)
            make.height.greaterThanOrEqualTo(44)
        }
        
        iconImageView.snp.makeConstraints { make in
            make.leading.equalTo(containerView).offset(16)
            make.centerY.equalTo(containerView)
            make.size.equalTo(20)
        }
        
        messageLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconImageView.snp.trailing).offset(12)
            make.trailing.equalTo(containerView).offset(-16)
            make.top.bottom.equalTo(containerView).inset(12)
        }
    }
}

// MARK: - UIViewController扩展

extension UIViewController {
    
    /// 显示成功Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - position: 显示位置
    func showSuccessToast(_ message: String, position: ToastPosition = .top) {
        ToastManager.shared.showSuccess(message, in: view, position: position)
    }
    
    /// 显示错误Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - position: 显示位置
    func showErrorToast(_ message: String, position: ToastPosition = .top) {
        ToastManager.shared.showError(message, in: view, position: position)
    }
    
    /// 显示信息Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - position: 显示位置
    func showInfoToast(_ message: String, position: ToastPosition = .top) {
        ToastManager.shared.showInfo(message, in: view, position: position)
    }
    
    /// 显示警告Toast
    /// - Parameters:
    ///   - message: 消息内容
    ///   - position: 显示位置
    func showWarningToast(_ message: String, position: ToastPosition = .top) {
        ToastManager.shared.showWarning(message, in: view, position: position)
    }
} 
