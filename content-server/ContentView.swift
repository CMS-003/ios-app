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
import AVFoundation
import MediaPlayer

struct WebViewContainer: UIViewRepresentable {
  @Binding var url: String
  @Binding var showVolume: Bool
  @Binding var volume: Float
  @Binding var realVolume: Float
  let configuration: WKWebViewConfiguration
  var onLockOrientationMessage: ((WKScriptMessage) -> Void)?
  
  func makeUIView(context: Context) -> WKWebView {

    let webview = WKWebView(frame: .zero,configuration: configuration)
    webview.allowsBackForwardNavigationGestures = false
    webview.configuration.allowsPictureInPictureMediaPlayback = true
    // webview.configuration.preferences.javaScriptEnabled = true
    webview.navigationDelegate = context.coordinator
    webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    // 加载 url
    if let url = URL(string: url) {
      let request = URLRequest(url: url);
      webview.load(request);
      webview.allowsBackForwardNavigationGestures = true
    }
    // 处理事件
    configuration.userContentController.add(context.coordinator, name: "volumeChanged")
    webview.configuration.userContentController.add(context.coordinator, name: "evaluate")
    return webview;
  }
  func updateUIView (_ uiView: WKWebView, context: Context){
    // 在变量变化时执行相应的操作
    uiView.evaluateJavaScript("setVolume(\(realVolume))") { result, error in
      if let result = result as? String {
        print(result)
      } else if let error = error {
        print("JavaScript evaluation error:", error.localizedDescription)
      }
    }
  }
  func makeCoordinator() -> Coordinator {
    return Coordinator(parent: self)
  }
  
  class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      if message.name == "volumeChanged", let volumeInfo = message.body as? [String: Any], let volumeNow = volumeInfo["volume"] as? Double {
        // 在此处理收到的音量信息
        print("Received volume change: \(volumeNow)")
        
        self.parent.showVolume = true
        self.parent.volume = Float(volumeNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          self.parent.showVolume = false
        }
      }
    }
    
    var parent: WebViewContainer
    
    init(parent: WebViewContainer) {
      self.parent = parent
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      self.parent.url = webView.url?.absoluteString ?? ""
      // 注入 JavaScript 代码以监听 SwiftUI 变量的变化
    }
  }
}

struct VolumeControlView: UIViewRepresentable {
  @Binding var volume: Float
  @Binding var show: Bool
  
  func makeUIView(context: Context) -> MPVolumeView {
    let volumeView = MPVolumeView()
    volumeView.showsRouteButton = false // 隐藏AirPlay按钮
    volumeView.tintColor = .clear
    print("init volume: \(volume)")
    // 整个不显示
    volumeView.showsVolumeSlider = show
    // 找到进度条的子视图，并设置进度条颜色
    for subview in volumeView.subviews {
      if subview is UISlider {
        let slider = subview as! UISlider
        slider.minimumTrackTintColor = UIColor(hex: "#2299ddff") // 设置进度条颜色
      }
    }
    setVolume(volumeView)
    volumeView.setNeedsLayout()
    return volumeView
  }
  
  func updateUIView(_ uiView: MPVolumeView, context: Context) {
    // 更新视图
    setVolume(uiView)
    uiView.setNeedsLayout()
  }
  func setVolume(_ uiView: MPVolumeView) {
    let volumeSlider = uiView.subviews.first(where: { $0 is UISlider }) as? UISlider
    print("set volume: \(volume)")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {//延迟0.01秒就能够正常播放
      volumeSlider?.value = volume
    }
  }
}

struct ContentView: View {
  @ObservedObject var store = Store()
  @StateObject var volumeObserver = Volumer()
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
  // 显示系统音量
  @State var showVolume = false
  @State private var volume:Float = AVAudioSession.sharedInstance().outputVolume
  
  let BaseURL = "http://ios.nat300.top"
  
  var body: some View {
    ZStack {
      VStack {
        if booted {
          WebViewContainer(
            url: $realURL,
            showVolume: $showVolume,
            volume: $volume,
            realVolume: $volumeObserver.volume,
            configuration: createConfiguration(volume: $volumeObserver.volume),
            onLockOrientationMessage: {message in
              print("lock")
            }
          )
          .edgesIgnoringSafeArea(.all)
          Text("volume: \(volumeObserver.volume)")
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
              // print("volue: \(volumeObserver.volume)")
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
      
      if showVolume {
        // MPVolumeView(frame: CGRect(x: -200, y: -200, width: 200, height: 50))
        VolumeControlView(volume: $volume, show: $showVolume )
          .frame(width: 200)
          .position(x: -200, y: -200)
          .allowsHitTesting(false)
        
        VStack {
          Text("音量: \(Int(volume*100))")
            .padding(.vertical, 4)
            .padding(.horizontal, 5)
            .foregroundColor(.white)
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
          Spacer()
        }
        .padding([.vertical], 10)
      }
    }
    
  }
}

// 创建 webview 配置
func createConfiguration(volume: Binding<Float>) -> WKWebViewConfiguration {
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
  configuration.userContentController.addUserScript(WKUserScript(source: """
    console.log("inject swift")
    window.volume = \(volume.wrappedValue);
    function setVolume(v) { window.volume = v; window.webkit.messageHandlers.volumeChanged.postMessage({ volume: v }); }
    function getVolume() { return window.volume; }
  """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
  
  let pagePerference = WKWebpagePreferences()
  pagePerference.allowsContentJavaScript = true;
  configuration.defaultWebpagePreferences = pagePerference;
  return configuration;
}



//struct ContentView_Previews: PreviewProvider {
//  static var previews: some View {
//    ContentView()
//  }
//}
