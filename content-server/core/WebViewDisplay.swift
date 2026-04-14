//
//  WebViewContainer.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import SwiftUI
import WebKit

/// UIKit 的 WKWebView 包装
/// 👉 不在这里做任何 reload 或逻辑
struct WebViewDisplay: UIViewRepresentable {
  
  @ObservedObject var store: WebViewInstance
  
  func makeUIView(context: Context) -> WKWebView {
    return store.webView
  }
  
  func updateUIView(_ uiView: WKWebView, context: Context) {
    // print("WebView Safe Area: \(store.webView.safeAreaInsets)")
  }
}
