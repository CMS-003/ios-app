//
//  fileHelper.swift
//  content-server
//
//  Created by jiayou on 2024/04/19.
//

import Foundation
import Zip

class FileHelper {
  func getDocumentDirectory() -> URL? {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths.first
  }
  func downloadFileUnzip(from url: URL, completion: @escaping (URL?) -> Void) {
    URLSession.shared.downloadTask(with: url) { (tempURL, response, error) in
      guard let tempURL = tempURL, error == nil else {
        completion(nil)
        return
      }
      // 获取临时目录
      let destinationURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(url.lastPathComponent)
      
      try? FileManager.default.moveItem(at: tempURL, to: destinationURL)
      // completion(destinationURL)
      do {
        let documentsDirectory = FileManager.default.urls(for:.documentDirectory, in: .userDomainMask)[0]
        // 从临时目录解压到文档目录
        try Zip.unzipFile(destinationURL, destination: documentsDirectory, overwrite: true, password: "", progress: { (progress) -> () in
          if progress>=1 {
            completion(documentsDirectory)
          }
        })
      } catch {
        print("unzip fail \(error)")
        completion(nil)
      }
    }.resume()
  }
}


