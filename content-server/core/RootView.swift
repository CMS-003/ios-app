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
  
  // 侧滑菜单
  @State private var offset: CGFloat = 0
  @State private var isOpen: Bool = false
  
  @State private var menuItems: [MenuItem] = []
  @State private var selectedApp: String = ""
  private let menuWidth: CGFloat = 120
  
  @StateObject private var webCache = WebViewCache()
  @State private var selectedPage: String = ""
  @State private var currentStore: WebViewInstance? = nil
  
  var body: some View {
    ZStack(alignment: .leading) {
      if (err_msg != "") {
        VStack {
          Text(err_msg)
          Button("重试") {
            err_msg = ""
          }
        }
      } else if(global.appBooted == false) {
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
            selectedPage = item.name
            
            let url_fullpath = item.path.starts(with: "http") ? item.path:global.localHost + item.path
            /// 👉 关键：这里触发 WebView 获取（缓存 or 创建）
            webCache.getWebView(for: item.name, url: URL(string:url_fullpath)!) { webStore in
              DispatchQueue.main.async {
                currentStore = webStore
              }
            }
            closeMenu()
          }
        )
        .frame(width: menuWidth)
        
        // 主视图 + 遮罩
        ZStack {
          /// 当前显示的 WebView（只显示一个）
          if let store = currentStore {
            WebViewDisplay(store: store)
              .id(webCache.forceUpdateTrigger)
          }
          /// 正在加载（第一次进入某页面）
          else if selectedPage != "" {
            ProgressView("加载中...")
          }
          /// 默认欢迎页
          else {
            Color(.systemBackground)
              .edgesIgnoringSafeArea(.all)
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
        .offset(x: offset)
        // .scaleEffect(isOpen ? 0.95 : 1) // 轻微缩放（更高级）
        .shadow(radius: isOpen ? 3 : 0)
        .gesture(dragGesture())
        .animation(.easeInOut(duration: 0.25), value: offset)
      }
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
    // 👉 模拟主进程获取数据（你可以替换为 API / 本地数据库）
    menuItems = [
      MenuItem(name: "hentai", path: "/hentai/", title: "首页"),
      MenuItem(name: "reader", path: "https://jiayou.work/read/#/", title: "阅读")
    ]
    
    // 恢复上次选择
    if let last = UserDefaults.standard.string(forKey: "last_selection"){
      for item in menuItems {
        if item.name == last {
          selectedApp = item.name
          break
        }
      }
    } else {
      selectedApp = ""
    }
    
    global.localHost = await withCheckedContinuation{
      continuation in
      LocalServerManager.shared.startIfNeeded {url in
        continuation.resume(returning: url)
      }
    }
    
    let result = await withCheckedContinuation {
      continuation in
      shttp.get(BaseURL + "/gw/api/v1/public/remote/app/hentai/version/latest")
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
      
      // 版本判断
      let app_version = (data["data"]["version"].string)!
      if app_version != global.app_version {
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
            global.app_version = app_version
            global.appBooted = true
          }
        }
      } else {
        global.appBooted = true
      }
    case .failure(let err):
      // 处理错误
      err_msg = "网络错误 \(err)"
      return
    }
  }
  
  func saveLastSelection(_ item: String) {
    UserDefaults.standard.set(item, forKey: "last_selection")
  }
}
