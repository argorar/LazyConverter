//
//  VideoResolution.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 24/12/25.
//


public enum VideoResolution: String, CaseIterable {
    case original = "Original"
    case p480 = "480p"
    case p720 = "720p"
    case p1080 = "1080p"
    case p2k = "2K"
    case p4k = "4K"
    
    var displayName: String {
        self.rawValue
    }
    
    var ffmpegParam: String {
        switch self {
        case .original:
            return "0:0"
        case .p480:
            return "854:480"
        case .p720:
            return "1280:720"
        case .p1080:
            return "1920:1080"
        case .p2k:
            return "2560:1440"
        case .p4k:
            return "3840:2160"
        }
    }
    
    var isCustom: Bool {
        self == .original
    }
}

