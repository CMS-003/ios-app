//
//  UIColor.swift
//  content-server
//
//  Created by jiayou on 2024/04/25.
//

import UIKit

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        let startIndex = hexSanitized.index(hexSanitized.startIndex, offsetBy: 0)
        let endIndex = hexSanitized.index(hexSanitized.startIndex, offsetBy: 6)
        let range = startIndex..<endIndex
        Scanner(string: String(hexSanitized[range])).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        var alpha: CGFloat = 1.0
        if hexSanitized.count == 8 {
            let startIndex = hexSanitized.index(hexSanitized.startIndex, offsetBy: 6)
            let endIndex = hexSanitized.index(hexSanitized.startIndex, offsetBy: 8)
            let range = startIndex..<endIndex
            Scanner(string: String(hexSanitized[range])).scanHexInt64(&rgb)
            alpha = CGFloat(rgb) / 255.0
        }
        
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
