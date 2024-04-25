//
//  ContentView.swift
//  content-server
//
//  Created by jiayou on 2024/04/17.
//

import SwiftUI
import NIO
import NIOPosix
import NIOHTTP1
import Foundation
import WebKit
import UIKit

struct WebViewContainer: UIViewRepresentable {
  @Binding var url: String
  let configuration: WKWebViewConfiguration
  var onFullScreenMessage: ((WKScriptMessage) -> Void)?
  var onLockOrientationMessage: ((WKScriptMessage) -> Void)?
  
  func makeUIView(context: Context) -> WKWebView {
    let webview = WKWebView(frame: .zero,configuration: configuration)
    webview.allowsBackForwardNavigationGestures = false
    webview.configuration.allowsPictureInPictureMediaPlayback = true
    // webview.configuration.preferences.javaScriptEnabled = true
    webview.navigationDelegate = context.coordinator
    webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    return webview;
  }
  func updateUIView (_ uiView: WKWebView, context: Context){
    if let url = URL(string: url) {
      let request = URLRequest(url: url);
      uiView.load(request);
      uiView.allowsBackForwardNavigationGestures = true
    }
    
  }
  func makeCoordinator() -> Coordinator {
    return Coordinator(parent: self)
  }
  class Coordinator: NSObject, WKNavigationDelegate {
    var parent: WebViewContainer
    
    init(parent: WebViewContainer) {
      self.parent = parent
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      self.parent.url = webView.url?.absoluteString ?? ""
    }
  }
}

struct ContentView: View {
  @ObservedObject var store = Store()
  // 入口 url
  @State private var realURL: String = ""
  // 静态文件服务器
  @State var Server = FileServer()
  // 启动
  @State var booted: Bool = false
  // error
  @State var error = ""
  // 启动信息
  @State var message = ""
  let BaseURL = "http://ios.nat300.top"
  
  var body: some View {
    VStack {
      if booted {
        WebViewContainer(
          url: $realURL,
          configuration: createConfiguration(),
          onFullScreenMessage: { message in
            print("fullscreen")
          },
          onLockOrientationMessage: {message in
            print("lock")
          }
        )
        .edgesIgnoringSafeArea(.all)
      } else if (error != "") {
        Text(error)
        Button("重试") {
          error = ""
        }
      } else {
        Text(message)
        ProgressView()
          .onAppear() {
            print("进入程序")
            message = "获取中..."
            shttp.get(BaseURL + "/gw/novel/v1/public/app-version/novel/latest")
              .send { result in
                switch result {
                case .success(let data):
                  // 处理返回的数据
                  let code = data["code"].int
                  if (code != 0) {
                    error = "数据错误"
                    return
                  }
                  // 版本判断
                  let app_version = (data["data"]["version"].string)!
                  if app_version != store.app_version {
                    message = "下载中.."
                    // 获取路径
                    let path = data["data"]["path"].string
                    print("path: \(path!)")
                    // 开始加载解压
                    let fileurl = URL(string: BaseURL + path!)
                    FileHelper().downloadFileUnzip(from: fileurl!) { filedir in
                      if filedir == nil {
                        error = "更新失败"
                        return
                      }
                      print("更新应用: \(store.app_version) -> \(app_version)")
                      store.app_version = app_version
                      // 启动本地服务器
                      Server.start(dir: filedir!) {
                        realURL = "http://127.0.0.1:\(Server.port)/novel/index.html"
                        booted = true
                      }
                    }
                  } else {
                    // 启动本地服务器
                    print("无需更新应用(\(app_version))")
                    Server.start(dir: FileHelper().getDocumentDirectory()!) {
                      realURL = "http://127.0.0.1:\(Server.port)/novel/index.html"
                      booted = true
                    }
                  }
                  
                case .failure(let err):
                  // 处理错误
                  print("Network request failed with error: \(err)")
                  error = "网络错误"
                }
              }
          }
      }
    }
  }
}
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
  let pagePerference = WKWebpagePreferences()
  pagePerference.allowsContentJavaScript = true;
  configuration.defaultWebpagePreferences = pagePerference;
  return configuration;
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
