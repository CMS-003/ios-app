//
//  WebViewCache.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import WebKit

class WebViewCache: ObservableObject {
  
  private var cache: [String: WebViewInstance] = [:]
  // 当ID用
  @Published var forceUpdateTrigger = UUID()
  
  func has(_ page: String) -> Bool {
    return cache[page] != nil
  }
  
  func getWebView(
    for page: String,
    url: URL,
    completion: @escaping (WebViewInstance?) -> Void
  ) {
    // ✅ 已缓存
    if let existing = cache[page] {
      // ✅ 强制触发更新
      DispatchQueue.main.async {
        self.forceUpdateTrigger = UUID()
        completion(existing)
      }
      return
    }
    
    let store = WebViewInstance(url: url)
    
    cache[page] = store
    DispatchQueue.main.async {
      self.forceUpdateTrigger = UUID()
      completion(store)
    }
  }
}
