//
//  Server.swift
//  content-server
//
//  Created by jiayou on 2024/04/25.
//

import NIO
import NIOPosix
import NIOHTTP1
import Foundation

class FileServer {
  let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
  let fileManager = FileManager.default
  var port: Int = 8080
  var message:String = ""
  
  func start(dir: URL, completion: @escaping(() -> Void)) {
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(HTTPHandler(dir: dir, fileManager: self.fileManager))
        }
      }
    
    do {
      if let availablePort = findAvailablePort(startingAt: 8080) {
        port = availablePort
        let serverChannel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        print("Server running on:", serverChannel.localAddress!, " static: \(dir)")
        // 信号处理
        
        serverChannel.closeFuture.whenComplete { result in
          switch result {
          case .success:
            // 服务器通道关闭成功后的处理逻辑
            print("close success")
          case .failure(let error):
            // 服务器通道关闭失败时的处理逻辑
            print("close fail \(error)")
          }
        }
      } else {
        message = "无可用端口"
      }
      completion()
    } catch {
      message = "错误: \(error)"
      print("Server error: \(error)")
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
      var fileURL = StaticDir.appendingPathComponent(head.uri)

      // 路由匹配失败返回主页
      if !fileManager.fileExists(atPath: fileURL.path) {
        fileURL = StaticDir.appendingPathComponent("/novel/index.html")
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
