//
//  DenoiseLevel.swift
//  LazyConverter
//

enum DenoiseLevel: String, CaseIterable {
    case off = "off"
    case subtle = "subtle"
    case medium = "medium"
    case strong = "strong"

    var ffmpegFilter: String? {
        switch self {
        case .off:     return nil
        case .subtle:  return "hqdn3d=2:2:3:3"
        case .medium:  return "hqdn3d=4:3:6:4.5"
        case .strong:  return "hqdn3d=6:4:8:6"
        }
    }

    var rifeFilter: String {
        (self == .off ? DenoiseLevel.subtle : self).ffmpegFilter!
    }
}
