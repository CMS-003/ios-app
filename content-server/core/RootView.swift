//
//  RootView.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import SwiftUI
import WebKit

struct RootView: View {
  
  @ObservedObject var global = Global()
  // 启动框架
  let BaseURL = "https://jiayou.work"
  @State var message = ""
  @State var err_msg = ""
  
  @StateObject private var webCache = WebViewCache()
  @State private var selectedPage: String = ""
  @State private var currentStore: WebViewInstance? = nil
  
  // 屏幕旋转管理
  @StateObject private var orientationManager = OrientationManager.shared
  @State private var lastNotifiedOrientation: String = ""  // 缓存上次通知的方向
  
  // 侧滑菜单
  @State private var offset: CGFloat = 0
  @State private var isOpen: Bool = false
  
  @State private var menuItems: [MenuItem] = []
  @State private var selectedApp: String = ""
  private let menuWidth: CGFloat = 120
  
  var body: some View {
    ZStack(alignment: .leading) {
      if (err_msg != "") {
        VStack {
          Text(err_msg)
          Button("重试") {
            err_msg = ""
          }
        }
      } else if(global.serverBooted == false) {
        HStack {
          ProgressView()
            .onAppear() {
              message = "获取中..."
              Task {
                do {
                  try await bootstrap()
                } catch {
                  err_msg = error.localizedDescription
                }
              }
            }
          Text(message)
        }
      } else {
        // 左侧菜单
        SideMenuView(
          items: menuItems,
          selected: selectedApp,
          onSelect: { item in
            selectedPage = item._id
            closeMenu()
            
            global.appBooting = item.path.starts(with: "/");
            let url_fullpath = item.path.starts(with: "http") ? item.path:global.localHost + item.path
            /// 👉 关键：这里触发 WebView 获取（缓存 or 创建）
            currentStore = webCache.getWebView(for: item._id, url: URL(string:url_fullpath)!);
            
            if global.appBooting {
              Task {
                try await updateApp(app: item.name, _id: item._id)
              }
            }
          }
        )
        .frame(width: menuWidth)
        
        // 主视图 + 遮罩
        ZStack {
          Color(.systemBackground)
            .edgesIgnoringSafeArea(.all)
          /// 当前显示的 WebView（只显示一个）
          if global.appBooting {
            ProgressView("检查中...")
          }
          else if let store = currentStore {
            ZStack {
              WebViewDisplay(store: store)
                .ignoresSafeArea(.all)
                .id(webCache.forceUpdateTrigger)
              if store.isLoading {
                Rectangle()
                  .opacity(0.9)
                  .ignoresSafeArea()
                ProgressView("载入中...")
                  .foregroundStyle(.blue)
              }
            }
            
          }
          /// 正在加载（第一次进入某页面）
          else if selectedPage != "" {
            ProgressView("加载中...")
          }
          /// 默认欢迎页
          else {
            VStack {
              Spacer()
              Text("欢迎🎉🎉")
                .font(.largeTitle)
              
              Button("应用列表") {
                offset = 1
                toggleMenu()
              }
              .padding()
              
              Spacer()
            }
          }
          
          // 遮罩（带模糊）
          if offset > 0 {
            Rectangle()
              .opacity(0.8)
              .ignoresSafeArea()
              .onTapGesture {
                closeMenu()
              }
          }
        }
        .ignoresSafeArea(.all)
        .offset(x: offset)
        .shadow(radius: isOpen ? 3 : 0)
        .gesture(dragGesture())
        .animation(.easeInOut(duration: 0.25), value: offset)
      }
    }
    .ignoresSafeArea(.all)
    .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
      // 延迟一点获取最终方向，避免中间状态
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        handleOrientationChange()
      }
    }
    .onAppear {
      UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      orientationManager.appOrientation = orientationManager.getDeviceOrientation()
      lastNotifiedOrientation = orientationManager.appOrientation
    }
  }
  
  private func handleOrientationChange() {
    let currentOrientation = orientationManager.getDeviceOrientation()
    
    // ✅ 只有真正改变时才通知
    if currentOrientation != lastNotifiedOrientation {
      // print("方向真正改变: \(lastNotifiedOrientation) -> \(currentOrientation)")
      lastNotifiedOrientation = currentOrientation
      notifyWebView(orientation: currentOrientation)
    } else {
      // print("方向未改变，忽略通知")
    }
  }
  
  private func notifyWebView(orientation: String) {
    if let store = currentStore {
      let jsCode = "NativeBridge.receive('deviceOrientation', '\(orientation)')"
      store.webView.evaluateJavaScript(jsCode, completionHandler: nil)
    }
  }
}
// 侧滑功能
extension RootView {
  
  func dragGesture() -> some Gesture {
    DragGesture()
      .onChanged { value in
        let translation = value.translation.width
        
        if !isOpen {
          // 左边缘触发
          if value.startLocation.x < 20 {
            offset = min(max(translation, 0), menuWidth)
          }
        } else {
          // 已打开 → 可关闭
          offset = min(max(menuWidth + translation, 0), menuWidth)
        }
      }
      .onEnded { value in
        let shouldOpen = offset > menuWidth / 2
        
        // 关键：这里添加动画
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          if shouldOpen {
            openMenu()
          } else {
            closeMenu()
          }
        }
      }
  }
  
  func toggleMenu() {
    // 添加动画
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      if isOpen {
        closeMenu()
      } else {
        openMenu()
      }
    }
  }
  
  func openMenu() {
    isOpen = true
    offset = menuWidth
  }
  
  func closeMenu() {
    isOpen = false
    offset = 0
  }
}
// 数据请求
extension RootView {
  
  func bootstrap() async throws -> Void {
    // 启动静态服务
    global.localHost = await withCheckedContinuation{
      continuation in
      LocalServerManager.shared.startIfNeeded {url in
        continuation.resume(returning: url)
      }
    }
    global.serverBooted = true
    // 获取应用列表
    let appResults = await withCheckedContinuation{
      continuation in
      shttp.get(BaseURL+"/gw/api/v1/public/remote/apps")
        .send{ resp in
          continuation.resume(returning: resp)
        }
    }
    switch appResults {
    case .success(let data):
      let code = data["code"].int
      if (code != 0) {
        err_msg = "数据错误"
        return
      }
      if let items = data["data"]["items"].array {
        self.menuItems = items.map { item in
          MenuItem(
            _id:  item["_id"].stringValue,
            name:  item["name"].stringValue,
            path:  item["path"].stringValue,
            title: item["title"].stringValue
          )
        }
      } else {
        err_msg = "格式错误"
        return
      }
      
    case .failure(let err):
      // 处理错误
      err_msg = "网络错误 \(err)"
      return
    }
    
  }
  
  func updateApp(app: String, _id: String) async throws -> Void {
    
    let result = await withCheckedContinuation {
      continuation in
      shttp.get(BaseURL + "/gw/api/v1/public/remote/app/\(app)/version/latest")
        .send { resp in
          continuation.resume(returning: resp)
        }
    }
    
    switch result {
    case .success(let data):
      // 处理返回的数据
      let code = data["code"].int
      if (code != 0) {
        err_msg = "数据错误"
        return
      }
      // 获取路径
      let path = data["data"]["path"].string
      
      let currentVer = global.apps_version[_id] ?? "0.0.0"
      // 版本判断
      let app_version = (data["data"]["version"].string)!
      if app_version != currentVer {
        message = "下载中.."
        // 开始加载解压
        let fileurl = URL(string: BaseURL + path!)
        FileHelper().downloadFileUnzip(from: fileurl!) { filedir in
          if filedir == nil {
            err_msg = "更新失败"
            return
          }
          print("更新应用: \(global.app_version) -> \(app_version)")
          DispatchQueue.main.async {
            global.apps_version[_id] = app_version
            global.appBooting = false
          }
        }
      } else {
        global.appBooting = false
      }
    case .failure(let err):
      // 处理错误
      err_msg = "网络错误 \(err)"
      return
    }
  }
}
