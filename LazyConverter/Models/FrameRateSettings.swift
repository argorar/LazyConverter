//
//  FrameRateSettings.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 1/02/26.
//

import Foundation

struct FrameRateSettings: Codable, Equatable {
    var mode: FrameRateMode = .keep
    var targetFrameRate: FrameRate = .fps60
    
    var isActive: Bool {
        return mode != .keep
    }
    
    static let `default` = FrameRateSettings()
    
    func toFFmpegFilter() -> String? {
        switch mode {
                case .keep:
                    return nil
   
                case .interpolate:
                    let fps = targetFrameRate.ffmpegValue
                    return "minterpolate=fps=\(fps):mi_mode=mci:mc_mode=obmc:me=epzs:me_mode=bidir:vsbmc=1:scd=fdiff"
                }
    }
}

enum FrameRateMode: String, CaseIterable, Codable {
    case keep = "keep"
    case interpolate = "interpolate"
    
    var displayName: String {
        switch self {
        case .keep: return "Keep Original"
        case .interpolate: return "Interpolate (Smooth)"
        }
    }
    
    var icon: String {
        switch self {
        case .keep: return "film"
        case .interpolate: return "wand.and.stars"
        }
    }
}

enum FrameRate: Double, CaseIterable, Codable {
    case fps23_976 = 23.976
    case fps24 = 24.0
    case fps25 = 25.0
    case fps29_97 = 29.97
    case fps30 = 30.0
    case fps48 = 48.0
    case fps50 = 50.0
    case fps59_94 = 59.94
    case fps60 = 60.0
    case fps120 = 120.0
    
    var displayName: String {
        switch self {
        case .fps23_976: return "23.976 fps (Film)"
        case .fps24: return "24 fps (Cinema)"
        case .fps25: return "25 fps (PAL)"
        case .fps29_97: return "29.97 fps (NTSC)"
        case .fps30: return "30 fps"
        case .fps48: return "48 fps (HFR)"
        case .fps50: return "50 fps (PAL High)"
        case .fps59_94: return "59.94 fps (NTSC High)"
        case .fps60: return "60 fps (Smooth)"
        case .fps120: return "120 fps (Ultra Smooth)"
        }
    }
    
    var shortName: String {
        switch self {
        case .fps23_976: return "23.98"
        case .fps24: return "24"
        case .fps25: return "25"
        case .fps29_97: return "29.97"
        case .fps30: return "30"
        case .fps48: return "48"
        case .fps50: return "50"
        case .fps59_94: return "59.94"
        case .fps60: return "60"
        case .fps120: return "120"
        }
    }
    
    var ffmpegValue: String {
        switch self {
        case .fps23_976: return "24000/1001"
        case .fps24: return "24"
        case .fps25: return "25"
        case .fps29_97: return "30000/1001"
        case .fps30: return "30"
        case .fps48: return "48"
        case .fps50: return "50"
        case .fps59_94: return "60000/1001"
        case .fps60: return "60"
        case .fps120: return "120"
        }
    }
}
