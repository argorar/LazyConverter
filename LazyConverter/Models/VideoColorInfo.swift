//
//  VideoColorInfo.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 20/01/26.
//


struct VideoColorInfo {
    let pixelFormat: String
    let colorPrimaries: String
    let colorTrc: String        // Transfer Characteristic
    let colorSpace: String      // YCbCr Matrix
    let colorRange: String      // tv/limited (16-235) o pc/full (0-255)
}

extension VideoColorInfo {
    func validFFmpegPrimaries() -> String {
        switch colorPrimaries {
        case "bt709": return "bt709"
        case "bt2020nc", "bt2020ncl": return "bt2020-nonconstant"
        case "bt2020c": return "bt2020-constant"
        case "smpte170m", "bt470bg": return "smpte170m"
        case "smpte240m": return "smpte240m"
        default: return "bt709"
        }
    }
    
    func validFFmpegTrc() -> String {
        switch colorTrc {
        case "bt709": return "bt709"
        case "gamma22": return "gamma22"
        case "gamma28": return "gamma28"
        case "smpte170m": return "smpte170m"
        case "smpte2084": return "smpte2084"  // PQ
        case "arib-std-b67": return "arib-std-b67"  // HLG
        default: return "bt709"
        }
    }
    
    func validFFmpegColorspace() -> String {
        switch colorSpace {
        case "bt709": return "bt709"
        case "bt470bg", "smpte170m": return "smpte170m"
        case "bt601": return "bt601"
        case "bt2020nc", "bt2020ncl": return "bt2020-nonconstant"
        case "smpte240m": return "smpte240m"
        default: return "bt709"
        }
    }
    
    func validFFmpegRange() -> String {
        return colorRange == "pc" ? "pc" : "tv"
    }
}
