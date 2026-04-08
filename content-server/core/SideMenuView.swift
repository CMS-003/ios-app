//
//  SideMenuView.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import SwiftUI

struct MenuItem {
  let name: String  // 唯一标识
  var path: String  // 地址
  let title: String // 显示标题
}

struct SideMenuView: View {
  
  let items: [MenuItem]
  @State var selected: String = ""
  let onSelect: (MenuItem) -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      
      Text("应用")
        .font(.largeTitle)
        .bold()
        .padding(.top, 20)
      
      ForEach(items, id: \.name) { item in
        Button {
          selected = item.name
          onSelect(item)
        } label: {
          HStack {
            Spacer()
            if item.name == selected {
              Text(item.title)
                .padding(.bottom, 4)
                .overlay(
                  Rectangle()
                    .frame(height: 2)
                    .foregroundColor(.blue),
                  alignment: .bottom
                )
            } else {
              Text(item.title)
            }
            Spacer()
          }
        }
      }
      
      Spacer()
      
      HStack {
        Spacer()
        Image(systemName: "person.fill")
          .resizable()
          .padding(20)
          .frame(width: 60, height: 60)
          .background(Color.blue)
          .foregroundColor(.white)
          .clipShape(Circle())
          .frame(alignment: .center)
        Spacer()
      }
    }
    .padding(.horizontal, 20)
    .background(Color(.systemBackground))
  }
}
