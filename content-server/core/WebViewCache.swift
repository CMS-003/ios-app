//
//  WebViewCache.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import WebKit
import AVFoundation
import MediaPlayer

func setSystemVolume(_ value: Float) {
    let session = AVAudioSession.sharedInstance()
    
    do {
        // 1. 关键：必须设置为 playback 类别，即使你不播放声音
        try session.setCategory(.playback, mode: .default, options: [])
        // 2. 强制激活会话
        try session.setActive(true)
    } catch {
        print("激活音频失败: \(error)")
    }

    // 找到当前 Window
    let windowScene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    guard let window = windowScene?.windows.first else { return }

    let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
    window.addSubview(volumeView)

    // 3. 增加一点延迟，给系统分配 Context 的时间
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            // 某些时候需要先触发一次滑动
            slider.setValue(value, animated: false)
            slider.sendActions(for: .valueChanged)
            print("指令已发出，音量应为: \(slider.value)")
        }
        
        // 留出时间让系统处理，然后再移除
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            volumeView.removeFromSuperview()
        }
    }
}

class WebViewCache: ObservableObject {
  
  private var cache: [String: WebViewInstance] = [:]
  private var orientationManager = OrientationManager.shared
  // 当ID用
  @Published var forceUpdateTrigger = UUID()
  
  func has(_ app_id: String) -> Bool {
    return cache[app_id] != nil
  }
  
  func getWebView(
    for app_id: String,
    url: URL
  ) -> WebViewInstance {
    // ✅ 已缓存
    if let existing = cache[app_id] {
      // ✅ 强制触发更新
      self.forceUpdateTrigger = UUID()
      return existing
    }
    
    let store = WebViewInstance(url: url)
    store.actionHandler = { action, callback, params in
      print("收到命令 \(action)", params ?? [:])
      switch action {
      case "getVolume":
        do {
          let session = AVAudioSession.sharedInstance()
          try? session.setActive(true) // 激活会话以同步硬件状态
          let volume = session.outputVolume
          
          DispatchQueue.main.async {
            // 2. 调用 JS 的统一接收入口，传回 ID 和 数据
            let jsCode = "NativeBridge.receive('\(callback)', \(volume))"
            store.webView.evaluateJavaScript(jsCode, completionHandler: nil)
          }
        }
      case "getOrientationMode":
        do {
          let mode: String = self.orientationManager.appOrientation
          DispatchQueue.main.async {
            let jsCode = "NativeBridge.receive('\(callback)', '\(mode)')"
            store.webView.evaluateJavaScript(jsCode, completionHandler: nil)
          }
        }
      case "lockScreen":
        do {
          let lockVal = params?["lock"] as? Int ?? 0
          let lock = (lockVal != 0)
          if lock == true {
            self.orientationManager.lock()
          } else {
            self.orientationManager.unlock()
          }
          DispatchQueue.main.async {
            let jsCode = "NativeBridge.receive('\(callback)', true)"
            store.webView.evaluateJavaScript(jsCode, completionHandler: nil)
          }
        }
      case "isScreenLocked":
        DispatchQueue.main.async {
          let jsCode = "NativeBridge.receive('\(callback)', \(self.orientationManager.isLocked))"
          store.webView.evaluateJavaScript(jsCode, completionHandler: nil)
        }
        
      case "rotateOrientation":
        do {
          let mode = params?["mode"] as? String ?? "portrait"
          self.orientationManager.rotate(mode == "portrait" ? "portrait" : "landscape")
          DispatchQueue.main.async {
            let jsCode = "NativeBridge.receive('\(callback)', true)"
            store.webView.evaluateJavaScript(jsCode, completionHandler: nil)
          }
        }        
      case "setVolume":
        if let params = params,
           let value = params["value"] as? NSNumber {
          let volumeFloat = value.floatValue
          setSystemVolume(volumeFloat)
        }
      case "download":
        print("下载文件", params ?? [:])
        
      case "lockOrientation":
        print("锁定屏幕")
        
      default: break;
      }
    }
    store.onStatusChange = { [weak self] in
      self?.objectWillChange.send()
    }
    
    cache[app_id] = store
    self.forceUpdateTrigger = UUID()
    return store;
  }
}
