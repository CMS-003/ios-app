//
//  LocalServerManager.swift
//  content-server
//
//  Created by 家友 on 2026/4/8.
//

import SwiftUI
import Darwin
import NIO
import NIOPosix
import NIOHTTP1
import Foundation

func findAvailablePort(startingAt port: Int, maxPort: Int = 65535) -> Int? {
    var portToCheck = port
    while portToCheck <= maxPort {
        var isPortAvailable = true
        
        // Create a TCP socket to test the port
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFileDescriptor != -1 else {
            print("Failed to create socket")
            return nil
        }
        
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(portToCheck).bigEndian
        address.sin_addr.s_addr = INADDR_ANY // Listen on any address
        
        // Convert sockaddr_in to sockaddr
        var socketAddress = sockaddr()
        memcpy(&socketAddress, &address, MemoryLayout<sockaddr_in>.size)
        
        // Bind the socket to the port
        if bind(socketFileDescriptor, &socketAddress, socklen_t(MemoryLayout<sockaddr>.size)) != 0 {
            // Binding failed, which likely means the port is in use
            isPortAvailable = false
        }
        
        // Close the socket
        close(socketFileDescriptor)
        
        // If the port is available, return it
        if isPortAvailable {
            return portToCheck
        }
        
        // Try the next port
        portToCheck += 1
    }
    
    // No available port found
    return nil
}

class FileServer {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
  let fileManager = FileManager.default
  var port: Int = 8080
  var message:String = ""
  
  func start(dir: URL, completion: @escaping((Int?) -> Void)) {
    
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(
            HTTPHandler(dir: dir, fileManager: self.fileManager)
          )
        }
      }
    
    do {
      if let availablePort = findAvailablePort(startingAt: 8080) {
        port = availablePort
        
        let serverChannel = try bootstrap
          .bind(host: "127.0.0.1", port: port)
          .wait()
        
        print("✅ Server running on: \(port)")
        
        serverChannel.closeFuture.whenComplete { result in
          switch result {
          case .success:
            print("close success")
          case .failure(let error):
            print("close fail \(error)")
          }
        }
        
        /// ✅ 把端口回传出去
        completion(port)
        
      } else {
        message = "无可用端口"
        completion(nil)
      }
      
    } catch {
      message = "错误: \(error)"
      print("Server error: \(error)")
      completion(nil)
    }
  }
}

class HTTPHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart
  
  let fileManager: FileManager
  let StaticDir: URL
  
  init(dir: URL, fileManager: FileManager) {
    StaticDir = dir
    self.fileManager = fileManager
  }
  
  // MARK: - 智能路径解析
  
  /// 从 URI 中解析应用名称
  private func parseAppName(from uri: String) -> String? {
    // 移除开头的斜杠
    let trimmed = uri.hasPrefix("/") ? String(uri.dropFirst()) : uri
    
    // 分割路径
    let parts = trimmed.split(separator: "/")
    
    // 如果没有路径部分，返回 nil
    guard let firstPart = parts.first else {
      return nil
    }
    
    let appName = String(firstPart)
    
    // 检查是否是文件扩展名（不应该作为应用名）
    let fileExtensions = [".html", ".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".json", ".txt"]
    for ext in fileExtensions {
      if appName.hasSuffix(ext) {
        return nil
      }
    }
    
    return appName
  }
  
  /// 智能查找文件路径
  private func findFileURL(for uri: String) -> URL? {
    print("查找文件: \(uri)")
    
    // 1. 首先尝试原始路径（保持向后兼容）
    var fileURL: URL
    if uri.hasSuffix("/") {
      let directoryURL = StaticDir.appendingPathComponent(uri)
      fileURL = directoryURL.appendingPathComponent("index.html")
    } else {
      fileURL = StaticDir.appendingPathComponent(uri)
    }
    
    // 2. 如果文件存在，直接返回
    if fileManager.fileExists(atPath: fileURL.path) {
      print("找到原始路径文件: \(fileURL.path)")
      return fileURL
    } else {
      print("原始路径文件不存在: \(fileURL.path)")
    }
    
    // 3. 尝试智能路由到应用目录
    if let appName = parseAppName(from: uri) {
      // 构建应用路径
      var appPath = uri
      if uri.hasPrefix("/\(appName)") {
        // 移除应用名前缀和斜杠
        let prefixToRemove = "/\(appName)"
        if uri == prefixToRemove {
          appPath = "/"  // 根路径
        } else if uri.hasPrefix("\(prefixToRemove)/") {
          appPath = String(uri.dropFirst(prefixToRemove.count))
        }
      }
      
      let appDir = StaticDir
        .appendingPathComponent("apps")
        .appendingPathComponent(appName)
        .appendingPathComponent("current")
      
      // 首先检查应用目录是否存在
      guard fileManager.fileExists(atPath: appDir.path) else {
        print("应用目录不存在: \(appDir.path)")
        return nil
      }
      
      let appFileURL: URL
      if appPath.isEmpty || appPath == "/" || appPath.hasSuffix("/") {
        appFileURL = appDir.appendingPathComponent("index.html")
      } else {
        // 移除开头的斜杠（如果有）
        let pathWithoutLeadingSlash = appPath.hasPrefix("/") ? 
          String(appPath.dropFirst()) : appPath
        appFileURL = appDir.appendingPathComponent(pathWithoutLeadingSlash)
      }
      
      // 4. 检查应用文件是否存在
      if fileManager.fileExists(atPath: appFileURL.path) {
        print("找到应用文件: \(appFileURL.path)")
        return appFileURL
      } else {
        print("应用文件不存在: \(appFileURL.path)")
      }
    }
    
    // 5. 所有尝试都失败，返回 nil
    return nil
  }
  
  /// 根据文件扩展名获取 MIME 类型
  private func getMimeType(for uri: String) -> String {
    if uri.hasSuffix(".js") {
      return "application/javascript"
    } else if uri.hasSuffix(".css") {
      return "text/css"
    } else if uri.hasSuffix(".svg") {
      return "image/svg+xml"
    } else if uri.hasSuffix(".png") {
      return "image/png"
    } else if uri.hasSuffix(".jpg") || uri.hasSuffix(".jpeg") {
      return "image/jpeg"
    } else if uri.hasSuffix(".gif") {
      return "image/gif"
    } else if uri.hasSuffix(".json") {
      return "application/json"
    } else if uri.hasSuffix(".ico") {
      return "image/x-icon"
    } else {
      return "text/html"
    }
  }
  
  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let reqPart = self.unwrapInboundIn(data)
    
    switch reqPart {
    case .head(let head):
      // 使用智能路由查找文件
      guard let fileURL = findFileURL(for: head.uri) else {
        // 文件未找到，返回 404
        print("文件未找到: \(head.uri)")
        let response = HTTPResponseHead(version: head.version, status: .notFound)
        context.write(self.wrapOutboundOut(.head(response)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        return
      }
      
      do {
        let fileData = try Data(contentsOf: fileURL)
        let mime = getMimeType(for: head.uri)
        
        // 设置 HTTP 响应的头部信息
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: mime)
        headers.add(name: "Cache-Control", value: "no-cache")
        
        let response = HTTPResponseHead(version: head.version, status: .ok, headers: headers)
        context.write(self.wrapOutboundOut(.head(response)), promise: nil)
        
        var buffer = context.channel.allocator.buffer(capacity: fileData.count)
        buffer.writeBytes(fileData)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        
        print("✅ 成功返回文件: \(head.uri) -> \(fileURL.lastPathComponent)")
        
      } catch {
        print("读取文件错误: \(fileURL.path) - \(error)")
        let response = HTTPResponseHead(version: head.version, status: .internalServerError)
        context.write(self.wrapOutboundOut(.head(response)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      }
      
    default:
      break
    }
  }
}


class LocalServerManager {
  
  static let shared = LocalServerManager()
  
  private let server = FileServer()
  private(set) var port: Int?
  
  private var isStarting = false
  
  /// 启动服务器（只会执行一次）
  func startIfNeeded(completion: @escaping (String) -> Void) {
    // ✅ 已启动
    if let port = port {
      completion("http://127.0.0.1:\(port)")
      return
    }
    // ❗防止重复启动
    if isStarting {
      return
    }
    isStarting = true    
    /// 👉 你的静态目录
    let dir = FileManager.default.urls(for:.documentDirectory, in: .userDomainMask)[0]
    
    server.start(dir: dir) { [weak self] (port: Int?) in
      DispatchQueue.main.async {
        self?.port = port
        self?.isStarting = false
        
        if let port = port {
          let url = "http://127.0.0.1:\(port)"
          completion(url)
        } else {
          completion("")
        }
      }
    }
  }
}
