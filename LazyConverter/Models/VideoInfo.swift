//
//  VideoInfo.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//


import Foundation
import AppKit

struct VideoInfo {
    let duration: Double
    let videoSize: CGSize
    let hasAudio: Bool
    let fileSizeMB: Double
    let fileName: String
    let originalURL: URL
    let frameRate: Double
    let colorInfo: VideoColorInfo
    
    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var sizeString: String {
        "\(Int(videoSize.width))x\(Int(videoSize.height))"
    }
}
