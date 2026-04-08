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
struct WebViewContainer: UIViewRepresentable {
  
  let webView: WKWebView
  
  func makeUIView(context: Context) -> WKWebView {
    return webView
  }
  
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
