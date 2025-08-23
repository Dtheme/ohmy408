//
//  NativeImageViewer.swift  
//  ohmy408
//
//  现代化原生图片查看器 - 替代JXPhotoBrowser
//  功能：缩放、平移、双击缩放、优雅动画、手势交互
//

import UIKit

/// 原生图片查看器 - 现代化实现，兼容iOS 12+
class NativeImageViewer: UIViewController {
    
    // MARK: - Properties
    
    /// 要显示的图片
    private let image: UIImage
    
    /// 滚动视图
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 3.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = UIScrollView.DecelerationRate.fast
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        return scrollView
    }()
    
    /// 图片视图
    private lazy var imageView: UIImageView = {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        return imageView
    }()
    
    /// 关闭按钮
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        
        // iOS版本兼容性处理
        if #available(iOS 13.0, *) {
            button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        } else {
            // iOS 12 兼容处理
            button.setTitle("✕", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        }
        
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        return button
    }()
    
    /// 加载指示器
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator: UIActivityIndicatorView
        
        // iOS版本兼容性处理
        if #available(iOS 13.0, *) {
            indicator = UIActivityIndicatorView(style: .large)
        } else {
            indicator = UIActivityIndicatorView(style: .whiteLarge)
        }
        
        indicator.color = .white
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Initialization
    
    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        setupConstraints()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateScrollViewContentSize()
        centerImageView()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .black
        
        view.addSubview(scrollView)
        scrollView.addSubview(imageView)
        view.addSubview(closeButton)
        view.addSubview(loadingIndicator)
        
        // 初始化时显示加载动画
        loadingIndicator.startAnimating()
        
        // 延迟隐藏加载动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.loadingIndicator.stopAnimating()
        }
    }
    
    private func setupConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // 兼容iOS 11以下版本的安全区域
        let safeAreaTop: NSLayoutYAxisAnchor
        if #available(iOS 11.0, *) {
            safeAreaTop = view.safeAreaLayoutGuide.topAnchor
        } else {
            safeAreaTop = view.topAnchor
        }
        
        NSLayoutConstraint.activate([
            // ScrollView约束
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // ImageView约束
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            
            // 关闭按钮约束
            closeButton.topAnchor.constraint(equalTo: safeAreaTop, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            // 加载指示器约束
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupGestures() {
        // 双击手势
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTapGesture)
        
        // 单击手势
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(singleTapGesture)
        
        // 滑动关闭手势
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        view.addGestureRecognizer(panGesture)
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let pointInView = gesture.location(in: imageView)
        
        var newZoomScale = scrollView.minimumZoomScale
        
        if scrollView.zoomScale == scrollView.minimumZoomScale {
            newZoomScale = scrollView.maximumZoomScale
        }
        
        let scrollViewSize = scrollView.bounds.size
        let zoomWidth = scrollViewSize.width / newZoomScale
        let zoomHeight = scrollViewSize.height / newZoomScale
        let zoomX = pointInView.x - (zoomWidth / 2.0)
        let zoomY = pointInView.y - (zoomHeight / 2.0)
        
        let rectToZoom = CGRect(x: zoomX, y: zoomY, width: zoomWidth, height: zoomHeight)
        
        UIView.animate(withDuration: 0.3) {
            self.scrollView.zoom(to: rectToZoom, animated: false)
        }
    }
    
    @objc private func handleSingleTap() {
        toggleCloseButton()
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard scrollView.zoomScale == scrollView.minimumZoomScale else { return }
        
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        
        switch gesture.state {
        case .changed:
            let alpha = max(0, 1 - abs(translation.y) / 200)
            view.backgroundColor = UIColor.black.withAlphaComponent(alpha)
            view.transform = CGAffineTransform(translationX: translation.x * 0.3, y: translation.y)
            
        case .ended, .cancelled:
            let shouldDismiss = abs(translation.y) > 100 || abs(velocity.y) > 500
            
            if shouldDismiss {
                dismiss(animated: true)
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    self.view.backgroundColor = .black
                    self.view.transform = .identity
                }
            }
            
        default:
            break
        }
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func updateScrollViewContentSize() {
        guard imageView.image != nil else { return }
        
        let imageSize = image.size
        let scrollSize = scrollView.bounds.size
        
        guard scrollSize.width > 0, scrollSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return
        }
        
        let widthScale = scrollSize.width / imageSize.width
        let heightScale = scrollSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)
        
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(2.0, minScale * 3)
        scrollView.zoomScale = minScale
        
        // 设置imageView的frame
        let scaledWidth = imageSize.width * minScale
        let scaledHeight = imageSize.height * minScale
        imageView.frame = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
    }
    
    private func centerImageView() {
        let scrollViewSize = scrollView.bounds.size
        let imageViewSize = imageView.frame.size
        
        let horizontalPadding = max(0, (scrollViewSize.width - imageViewSize.width) / 2)
        let verticalPadding = max(0, (scrollViewSize.height - imageViewSize.height) / 2)
        
        scrollView.contentInset = UIEdgeInsets(
            top: verticalPadding,
            left: horizontalPadding,
            bottom: verticalPadding,
            right: horizontalPadding
        )
    }
    
    private func toggleCloseButton() {
        UIView.animate(withDuration: 0.3) {
            self.closeButton.alpha = self.closeButton.alpha == 0 ? 1 : 0
        }
    }
}

// MARK: - UIScrollViewDelegate

extension NativeImageViewer: UIScrollViewDelegate {
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
    }
}

// MARK: - Static Factory Methods

extension NativeImageViewer {
    
    /// 便捷的展示方法
    /// - Parameters:
    ///   - image: 要显示的图片
    ///   - from: 展示的父控制器
    static func show(image: UIImage, from viewController: UIViewController) {
        let imageViewer = NativeImageViewer(image: image)
        viewController.present(imageViewer, animated: true)
    }
}

// MARK: - UIViewController Extension

extension UIViewController {
    
    /// 显示图片查看器的便捷方法
    /// - Parameter image: 要显示的图片
    func showImageViewer(with image: UIImage) {
        NativeImageViewer.show(image: image, from: self)
    }
}