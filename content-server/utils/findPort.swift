//
//  findPort.swift
//  content-server
//
//  Created by jiayou on 2024/04/18.
//

import Foundation
import SwiftUI
import Darwin

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
