//
//  VideoFormat.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 23/12/25.
//

import Foundation

public enum VideoFormat: String, CaseIterable {
    case mp4
    case mkv
    case mov
    case webm
    case av1
    
    public var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .mkv: return "MKV"
        case .mov: return "MOV"
        case .av1: return "AV1"
        case .webm: return "WebM"
        }
    }
}

extension VideoInfo {
    var previewURL: URL? {
        guard let path = Bundle.main.path(forResource: "preview_video", ofType: "mp4") else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}
