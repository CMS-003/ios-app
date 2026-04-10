//
//  content_serverApp.swift
//  content-server
//
//  Created by jiayou on 2024/04/17.
//
import SwiftUI
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {// 关键：定义一个静态变量存放单例
  static private(set) var shared: AppDelegate?
  
  var orientationLock: UIInterfaceOrientationMask = .all {
    didSet {
      print("🚨 orientationLock 变更为: \(orientationLock.rawValue)")
    }
  }
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    // 在初始化时给自己赋值
    AppDelegate.shared = self
    return true
  }
  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    return orientationLock
  }
  
  // 锁定方向的方法
  func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
    orientationLock = orientation
    
    // 强制旋转到指定方向
    if #available(iOS 16.0, *) {
      // iOS 16+ 使用新 API
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        var interfaceOrientations: UIInterfaceOrientationMask = orientation
        if orientation == .landscape {
          interfaceOrientations = .landscapeRight
        }
        
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: interfaceOrientations)) { error in
          print("方向更新错误: \(error)")
        }
        
        if let rootVC = windowScene.windows.first?.rootViewController {
          rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
      }
    } else {
      // iOS 16 以下使用旧方法
      let value = orientation == .portrait ? UIInterfaceOrientation.portrait.rawValue : UIInterfaceOrientation.landscapeRight.rawValue
      UIDevice.current.setValue(value, forKey: "orientation")
      UIViewController.attemptRotationToDeviceOrientation()
    }
  }
  
  // 解锁方向（恢复自动旋转）
  func unlockOrientation() {
    orientationLock = .all
    
    if #available(iOS 16.0, *) {
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { error in
          print("解锁方向错误: \(error)")
        }
        
        if let rootVC = windowScene.windows.first?.rootViewController {
          rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
      }
    } else {
      UIViewController.attemptRotationToDeviceOrientation()
    }
  }
  
  func rotateOrientation(to orientation: UIInterfaceOrientationMask) {
    if #available(iOS 16.0, *) {
      guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
      
      // 2. 这里不要传 .all，要传具体的“目标方向”
      let geometryRequest = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientation)
      
      windowScene.requestGeometryUpdate(geometryRequest) { error in
        print("强制旋转失败: \(error)")
      }
      
      // 刷新 VC 状态
      windowScene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
  }
}

@main
struct content_serverApp: App {
  // 注入 AppDelegate
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  var body: some Scene {
    WindowGroup {
    }
  }
}
