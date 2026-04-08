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
  
  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let reqPart = self.unwrapInboundIn(data)
    
    switch reqPart {
    case .head(let head):
      var fileURL: URL
      if head.uri.hasSuffix("/") {
        // 如果是目录，创建新的 URL 追加 index.html
        let directoryURL = StaticDir.appendingPathComponent(head.uri)
        fileURL = directoryURL.appendingPathComponent("index.html")
      } else {
        fileURL = StaticDir.appendingPathComponent(head.uri)
      }
      
      // 路由匹配失败返回主页
      if !fileManager.fileExists(atPath: fileURL.path) {
        fileURL = StaticDir.appendingPathComponent("hentai/index.html")
      }
      var mime = "text/html"
      if head.uri.hasSuffix(".js") {
        mime = "application/javascript"
      } else if head.uri.hasSuffix(".css") {
        mime = "text/css"
      } else if head.uri.hasSuffix(".svg") {
        mime = "image/svg+xml"
      }
      if fileManager.fileExists(atPath: fileURL.path) {
        do {
          let fileData = try Data(contentsOf: fileURL)
          // 设置HTTP响应的头部信息
          var headers = HTTPHeaders()
          headers.add(name: "Content-Type", value: mime)
          let response = HTTPResponseHead(version: head.version, status: .ok, headers: headers)
          context.write(self.wrapOutboundOut(.head(response)), promise: nil)
          var buffer = context.channel.allocator.buffer(capacity: fileData.count)
          buffer.writeBytes(fileData)
          context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
          context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        } catch {
          print("error: \(fileURL.path) \(error)")
          let response = HTTPResponseHead(version: head.version, status: .notFound)
          context.write(self.wrapOutboundOut(.head(response)), promise: nil)
          context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
      } else {
        print("nofound \(fileURL.path)")
        let response = HTTPResponseHead(version: head.version, status: .notFound)
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
