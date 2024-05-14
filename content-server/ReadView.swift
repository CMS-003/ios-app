//
//  ReadView.swift
//  content-server
//
//  Created by jiayou on 2024/05/14.
//

import SwiftUI
import NIO
import NIOPosix
import NIOHTTP1
import Foundation
import WebKit
import UIKit

struct WebViewContainer2: UIViewRepresentable {
  let homepage: String
  
  let configuration: WKWebViewConfiguration
  
  func makeUIView(context: Context) -> WKWebView {
    let webview = WKWebView(frame: .zero,configuration: configuration)
    webview.allowsBackForwardNavigationGestures = false
    webview.configuration.allowsPictureInPictureMediaPlayback = true
    // webview.configuration.preferences.javaScriptEnabled = true
    webview.navigationDelegate = context.coordinator
    webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    // 加载 url
    if let url = URL(string: homepage) {
      let request = URLRequest(url: url);
      print(url)
      webview.load(request);
      webview.allowsBackForwardNavigationGestures = true
    }
    // 处理事件
    
    return webview;
  }
  func updateUIView (_ uiView: WKWebView, context: Context){
    // 在变量变化时执行相应的操作
    
  }
  func makeCoordinator() -> Coordinator {
    return Coordinator(parent: self)
  }
  
  class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      
    }
    
    var parent: WebViewContainer2
    
    init(parent: WebViewContainer2) {
      self.parent = parent
    }
    
  }
}

struct ReadView: View {
  @ObservedObject var global = Global()
  
  var body: some View {
    WebViewContainer2(
      homepage: "https://u67631x482.vicp.fun/read/#/",
      configuration: createConfiguration()
    )
    .edgesIgnoringSafeArea(.all)
    .onAppear() {
      print("read appear")
    }
  }
  // 创建 webview 配置
  func createConfiguration() -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true;
    // 添加自定义偏好设置
    let preferences = WKPreferences();
    preferences.javaScriptCanOpenWindowsAutomatically = true;
    preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
    if #available(iOS 15.4, *) {
      // 无效..
      preferences.isElementFullscreenEnabled = true
    } else {
      // Fallback on earlier versions
    };
    // 注入脚本
    
    let pagePerference = WKWebpagePreferences()
    pagePerference.allowsContentJavaScript = true;
    configuration.defaultWebpagePreferences = pagePerference;
    return configuration;
  }
}
