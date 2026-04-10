//
//  OrientationManager.swift
//  content-server
//
//  Created by 家友 on 2026/4/9.
//

import SwiftUI
import UIKit

class OrientationManager: ObservableObject {
  static let shared = OrientationManager()
  
  @Published var appOrientation = "portrait"
  @Published var isLocked: Bool = true
  @Published var lockMode: String = "portrait"
  // 直接拿 AppDelegate 里的静态实例
  private var appDelegate: AppDelegate? {
    return AppDelegate.shared
  }
  
  init() {
    setupOrientationObserver()
  }
  
  private func setupOrientationObserver() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(orientationChanged),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
  }
  
  @objc private func orientationChanged() {
    // 只有在未锁定的情况下才更新实际方向
    if !isLocked {
      // App跟随设备旋转
      appOrientation = getDeviceOrientation()
      appDelegate?.rotateOrientation(to: appOrientation == "portrait" ? .portrait : .landscape )
    }
    print("当前方向: \(appOrientation), 锁定状态: \(isLocked) \(String(describing: appDelegate?.orientationLock))")
  }
  
  func getDeviceOrientation() -> String {
    let deviceOrientation = UIDevice.current.orientation
    if deviceOrientation.isPortrait {
      return "portrait"
    } else if deviceOrientation.isLandscape {
      return "landscape"
    }
    // 如果无法获取，通过屏幕尺寸判断
    return UIScreen.main.bounds.width > UIScreen.main.bounds.height ? "landscape" : "portrait"
  }

  func lock() {
    isLocked = true
    lockMode = appOrientation
    if appOrientation == "lanscape" {
      appDelegate?.lockOrientation(.landscape)
    } else {
      appDelegate?.lockOrientation(.portrait)
    }
    print("✅ 屏幕锁定：\(lockMode)")
  }
  
  // 解锁（自动旋转）
  func unlock() {
    appDelegate?.unlockOrientation()
    isLocked = false
    lockMode = "all"
    print("✅ 已解锁")
  }

  func rotate(_ orientation: String) {
    appOrientation = orientation
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      self.appDelegate?.rotateOrientation(to: self.appOrientation == "portrait" ? .portrait : .landscape )
    }
  }
}
