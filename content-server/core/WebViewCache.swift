//
//  WebViewCache.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import WebKit

class WebViewCache: ObservableObject {
  
  private var cache: [String: WebViewStore] = [:]
  
  func has(_ page: String) -> Bool {
    return cache[page] != nil
  }
  
  /// ❗改成异步（因为本地 server 需要时间启动）
  func getWebView(
    for page: String,
    path: String,
    completion: @escaping (WKWebView?) -> Void
  ) {
    
    // ✅ 已缓存
    if let existing = cache[page] {
      completion(existing.webView)
      return
    }
    if (path.starts(with: "http")) {
      let url = URL(string: path)!
      print(url)
      let store = WebViewStore(url: url)
      
      cache[page] = store
      completion(store.webView)
    } else {
      /// ✅ 先启动 server，再创建 WebView
      LocalServerManager.shared.startIfNeeded { url in
        guard let uri = URL(string: url+path)
        else {
          completion(nil)
          return
        }
        print(uri)
        let store = WebViewStore(url: uri)
        self.cache[page] = store
        
        completion(store.webView)
      }
    }
  }
}
