//
//  Store.swift
//  content-server
//
//  Created by jiayou on 2024/04/25.
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine

// 简单保存数据
class Global: ObservableObject {
  // 本地服务器是否启动
  @Published var serverBooted = false
  // 本地初始访问地址
  @Published var url = ""
  // 文档目录
  @Published var documentDir: URL
  // app 版本(本地持久化)
  @Published var app_version: String {
    didSet {
      UserDefaults.standard.set(app_version, forKey: "app_version")
    }
  }
  @Published var showVolumeTip = false  
  
  init() {
    self.documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    self.app_version = UserDefaults.standard.string(forKey: "app_version") ?? ""
  }

}
