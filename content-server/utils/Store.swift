//
//  Store.swift
//  content-server
//
//  Created by jiayou on 2024/04/25.
//

import Foundation

// 简单保存数据
class Store: ObservableObject {
    @Published var app_version: String {
        didSet {
            UserDefaults.standard.set(app_version, forKey: "app_version")
        }
    }

    init() {
        self.app_version = UserDefaults.standard.string(forKey: "app_version") ?? ""
    }
}
