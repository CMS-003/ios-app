//
//  WebViewInstance.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import WebKit

/// WebView 持有者（引用类型）
/// 👉 关键点：WebView 必须被持有，否则会被释放导致刷新
class WebViewInstance {
  
  let webView: WKWebView
  
  init(url: URL) {
    self.webView = WKWebView()
    self.webView.load(URLRequest(url: url))
  }
}
