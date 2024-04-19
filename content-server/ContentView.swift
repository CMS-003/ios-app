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

// 简单保存数据
class UserSettings: ObservableObject {
    @Published var app_version: String {
        didSet {
            UserDefaults.standard.set(app_version, forKey: "app_version")
        }
    }

    init() {
        self.app_version = UserDefaults.standard.string(forKey: "app_version") ?? ""
    }
}

// 创建一个类来符合 WKScriptMessageHandler 协议
class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
  var onMessage: ((WKScriptMessage) -> Void)?
  
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    onMessage?(message)
  }
}

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

class FileServer {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
  let fileManager = FileManager.default
  var port: Int = 8080
  var message:String = ""
  
  func start(dir: URL, completion: @escaping(() -> Void)) {
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(HTTPHandler(dir: dir, fileManager: self.fileManager))
        }
      }
    
    do {
      if let availablePort = findAvailablePort(startingAt: 8080) {
        port = availablePort
        let serverChannel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        print("Server running on:", serverChannel.localAddress!, " static: \(dir)")
        // 信号处理
        
        serverChannel.closeFuture.whenComplete { result in
          switch result {
          case .success:
            // 服务器通道关闭成功后的处理逻辑
            print("close success")
          case .failure(let error):
            // 服务器通道关闭失败时的处理逻辑
            print("close fail \(error)")
          }
        }
      } else {
        message = "无可用端口"
      }
      completion()
    } catch {
      message = "错误: \(error)"
      print("Server error: \(error)")
    }
  }
}

class HTTPHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart
  
  let fileManager: FileManager
  let StaticDir: URL
  
  init(dir: URL, fileManager: FileManager) {
    StaticDir = dir
    self.fileManager = fileManager
  }
  
  func removePrefix(from uri: String, prefixToRemove: String) -> String {
    if uri.hasPrefix(prefixToRemove) {
      return String(uri.dropFirst(prefixToRemove.count))
    } else {
      return uri
    }
  }
  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let reqPart = self.unwrapInboundIn(data)
    
    switch reqPart {
    case .head(let head):
      var fileURL = StaticDir.appendingPathComponent(head.uri)
      // StaticDir.appendingPathComponent(removePrefix(from: head.uri, prefixToRemove: "/novel/"))
      // print("url:\(head.uri)")
      
      // 路由匹配失败返回主页
      if !fileManager.fileExists(atPath: fileURL.path) {
        fileURL = StaticDir.appendingPathComponent("/index.html")
      }
      var mime = "text/html"
      if head.uri.hasSuffix(".js") {
        mime = "application/javascript"
      } else if head.uri.hasSuffix(".css") {
        mime = "text/css"
      } else if head.uri.hasSuffix(".svg") {
        mime = "image/svg+xml"
      }
      if fileManager.fileExists(atPath: fileURL.path) {
        do {
          let fileData = try Data(contentsOf: fileURL)
          // 设置HTTP响应的头部信息
          var headers = HTTPHeaders()
          headers.add(name: "Content-Type", value: mime)
          let response = HTTPResponseHead(version: head.version, status: .ok, headers: headers)
          context.write(self.wrapOutboundOut(.head(response)), promise: nil)
          var buffer = context.channel.allocator.buffer(capacity: fileData.count)
          buffer.writeBytes(fileData)
          context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
          context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        } catch {
          print("error: \(fileURL.path) \(error)")
          let response = HTTPResponseHead(version: head.version, status: .notFound)
          context.write(self.wrapOutboundOut(.head(response)), promise: nil)
          context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
      } else {
        let response = HTTPResponseHead(version: head.version, status: .notFound)
        context.write(self.wrapOutboundOut(.head(response)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      }
      
    default:
      break
    }
  }
}

struct ContentView: View {
  @ObservedObject var userSettings = UserSettings()
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
            print("loading")
            message = "获取中..."
            shttp.get("https://u67631x482.vicp.fun/gw/novel/v1/public/app-version/novel/latest")
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
                  if app_version != userSettings.app_version {
                    message = "下载中.."
                    // 获取路径
                    let path = data["data"]["path"].string
                    print("path: \(path!)")
                    // 开始加载解压
                    let fileurl = URL(string: "https://u67631x482.vicp.fun" + path!)
                    FileHelper().downloadFileUnzip(from: fileurl!) { filedir in
                      if filedir == nil {
                        error = "更新失败"
                        return
                      }
                      print("更新应用: \(userSettings.app_version) -> \(app_version)")
                      userSettings.app_version = app_version
                      // 启动本地服务器
                      Server.start(dir: filedir!) {
                        realURL = "http://127.0.0.1:\(Server.port)/novel/index.html"
                        booted = true
                      }
                    }
                  } else {
                    // 启动本地服务器
                    print("无需更新应用")
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
