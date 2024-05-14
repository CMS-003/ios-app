//
//  content_serverApp.swift
//  content-server
//
//  Created by jiayou on 2024/04/17.
//

import SwiftUI

@main
struct content_serverApp: App {
  
  @State var currView: String {
    didSet {
      UserDefaults.standard.set(currView, forKey: "lastView")
    }
  }
  
  init() {
    self.currView = UserDefaults.standard.string(forKey: "lastView") ?? ""
  }
  var body: some Scene {
    WindowGroup {
      ZStack {
        if currView=="novel"{
          ContentView()
        }else if currView == "read" {
          ReadView()
        } else {
          VStack {
            Spacer()
            Button(action: {
              currView = "novel"
            }) {
              Text("novel")
            }
            Spacer()
              .frame(height: 50)
            Button(action: {
              currView = "read"
            }) {
              Text("read")
            }
            Spacer()
          }
        }
        
        GeometryReader { geometry in
          HStack(alignment: .bottom) { // 为 Image 之外的其他内容提供垂直居中对齐
            Spacer()
            Image(systemName: "multiply")
              .font(.system(size: 24))
              .frame(width: 40, height: 40, alignment: .center)
              .clipShape(Circle())
              .onTapGesture {
                currView = ""
              }
          }
          .offset(x: -10, y: -10) // 20 像素距离顶部和右边
          // .background(Color.gray.opacity(0.1)) // 可选，设置背景色
        }
      }
    }
  }
}
