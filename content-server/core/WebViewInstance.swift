//
//  WebViewInstance.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import SwiftUI
@preconcurrency import WebKit

// MARK: - JS 消息模型
struct WebMessage {
  let action: String
  let params: [String: Any]?
}

// MARK: - WebViewStore
final class WebViewInstance: NSObject, ObservableObject {
  
  // MARK: - 对外状态（SwiftUI绑定）
  @Published var isLoading: Bool = true {
    didSet {
      // 当状态改变时，通知外部
      onStatusChange?()
    }
  }
  var onStatusChange: (() -> Void)?
  
  @Published var title: String = ""
  @Published var canGoBack: Bool = false
  @Published var canGoForward: Bool = false
  @Published var error: Error?
  
  // MARK: - 核心 WebView（必须强持有）
  let webView: WKWebView
  
  // MARK: - 外部行为扩展（关键设计）
  var actionHandler: ((String, String, [String: Any]?) -> Void)?
  
  // MARK: - 初始化
  init(url: URL) {
    // 1. 先准备好配置对象
    let config = WKWebViewConfiguration()
    // 允许内联播放（设为 false 则点击视频强制全屏）
    config.allowsInlineMediaPlayback = true
    // 允许 HTML5 视频全屏 API
    config.preferences.isElementFullscreenEnabled = true
    
    let userContentController = WKUserContentController()
    config.userContentController = userContentController
    
    // 2. 先把实例占位（此时不能传 self）
    self.webView = WKWebView(frame: .zero, configuration: config)
    // --- 解决白色背景 ---
    webView.isOpaque = false // 1. 设置为不透明度为 false
    webView.backgroundColor = .clear // 2. 背景设为透明
    webView.scrollView.backgroundColor = .clear // 3. 滚动视图也要设为透明
    
    // --- 强制适配内容 ---
    webView.scrollView.contentInsetAdjustmentBehavior = .never // ⚠️ 关键：禁用系统自动调整，交给网页 env() 处理
    
    super.init() // 这一步执行完后，self 才真正可用
    
    // 3. 关键：重新注册并确保注入
    // 虽然 webView 已经创建，但我们可以通过 userContentController 动态添加
    // 为了稳妥，我们直接操作 webView 现有的 configuration 对象
    self.webView.configuration.userContentController.add(self, name: "native")
    
    // 4. 其他配置
    self.webView.navigationDelegate = self
    self.webView.uiDelegate = self
    
    if #available(iOS 16.4, *) {
      self.webView.isInspectable = true
    }
    
    // 5. 最后加载页面 (确保加载时 bridge 已经注册完毕)
    self.webView.load(URLRequest(url: url))
  }
  
  deinit {
    webView.removeObserver(self, forKeyPath: "title")
    webView.removeObserver(self, forKeyPath: "canGoBack")
    webView.removeObserver(self, forKeyPath: "canGoForward")
  }
  
}

// MARK: - KVO 监听
extension WebViewInstance {
  override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
    
    guard let webView = object as? WKWebView else { return }
    
    DispatchQueue.main.async {
      switch keyPath {
      case "title":
        self.title = webView.title ?? ""
        
      case "canGoBack":
        self.canGoBack = webView.canGoBack
        
      case "canGoForward":
        self.canGoForward = webView.canGoForward
        
      default:
        break
      }
    }
  }
}

// MARK: - 页面加载状态
extension WebViewInstance: WKNavigationDelegate {
  
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    DispatchQueue.main.async {
      self.isLoading = true
    }
  }
  
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    DispatchQueue.main.async {
      DispatchQueue.main.asyncAfter(deadline: .now()+1) {
        self.isLoading = false
      }
    }
  }
  
  func webView(_ webView: WKWebView,
               didFail navigation: WKNavigation!,
               withError error: Error) {
    DispatchQueue.main.async {
      self.isLoading = false
      self.error = error
    }
  }
  
  func webView(_ webView: WKWebView,
               didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) {
    DispatchQueue.main.async {
      self.isLoading = false
      self.error = error
    }
  }
}

// MARK: - JS Bridge（核心扩展点）
extension WebViewInstance: WKScriptMessageHandler {
  
  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
    guard message.name == "native" else { return }
    
    if let body = message.body as? [String: Any] {
      
      let action = body["action"] as? String ?? ""
      let params = body["params"] as? [String: Any]
      let callback = body["callback"] as? String ?? ""
      
      DispatchQueue.main.async {
        self.handleAction(action: action, callback: callback, params: params)
      }
    }
  }
}

// MARK: - 行为分发（可扩展核心）
extension WebViewInstance {
  
  private func handleAction(action: String, callback: String, params: [String: Any]?) {
    
    // 👉 先交给外部（推荐）
    if let handler = actionHandler {
      handler(action, callback, params)
      return
    }
    
    // 👉 默认内置行为（可选）
    switch action {
      
    case "goBack":
      if webView.canGoBack {
        webView.goBack()
      }
      
    case "goForward":
      if webView.canGoForward {
        webView.goForward()
      }
      
    case "reload":
      webView.reload()
      
    default:
      print("未处理的 action: \(action)")
    }
  }
}

// MARK: - WKUIDelegate（弹窗等）
extension WebViewInstance: WKUIDelegate {
  
  // JS alert
  func webView(_ webView: WKWebView,
               runJavaScriptAlertPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping () -> Void) {
    
    print("JS Alert: \(message)")
    completionHandler()
  }
}

// MARK: - 对外控制方法（给 SwiftUI 调用）
extension WebViewInstance {
  
  func load(url: URL) {
    webView.load(URLRequest(url: url))
  }
  
  func reload() {
    webView.reload()
  }
  
  func goBack() {
    if webView.canGoBack {
      webView.goBack()
    }
  }
  
  func goForward() {
    if webView.canGoForward {
      webView.goForward()
    }
  }
  
  func evaluateJS(_ js: String, completion: ((Any?, Error?) -> Void)? = nil) {
    webView.evaluateJavaScript(js, completionHandler: completion)
  }
}
