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
  func printDocumentSubDir(_ sub: String) -> Void {
      let fileManager = FileManager.default
      var documentsUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
      documentsUrl = documentsUrl?.appendingPathComponent(sub)
      if let documentsUrl = documentsUrl {
        do {
          let directoryContents = try fileManager.contentsOfDirectory(at: documentsUrl, includingPropertiesForKeys: nil, options: [])
          let fileNames = directoryContents.map { $0.lastPathComponent }
          print("files: \(fileNames)")
        } catch {
          print("Error while enumerating files \(documentsUrl.path): \(error.localizedDescription)")
        }
      }
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
        print("unzip fail")
        completion(nil)
      }
    }.resume()
  }
}


