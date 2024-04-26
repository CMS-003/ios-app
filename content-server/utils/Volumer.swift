//
//  Volumer.swift
//  content-server
//
//  Created by jiayou on 2024/04/25.
//

import Foundation
import AVFoundation

// 音量监听
class Volumer: ObservableObject {
  @Published var volume: Float = 0.5 // 初始音量
  
  private var audioSession = AVAudioSession.sharedInstance()
  private var volumeObservation: NSKeyValueObservation?
  
  init() {
    // 监听音量变化
    volumeObservation = audioSession.observe(\.outputVolume) { [weak self] (audioSession, _) in
      self?.volume = audioSession.outputVolume
    }
    do {
      try audioSession.setActive(true)
    } catch {
      print("Failed to set audio session active: \(error.localizedDescription)")
    }
  }
  
  deinit {
    volumeObservation?.invalidate()
    do {
      try audioSession.setActive(false)
    } catch {
      print("Failed to deactivate audio session: \(error.localizedDescription)")
    }
  }
}
