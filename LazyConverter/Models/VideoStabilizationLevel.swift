//
//  VideoStabilizationLevel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 24/02/26.
//

import Foundation

enum VideoStabilizationLevel: String, CaseIterable, Codable {
    case low
    case medium
    case high

    var detectParameters: String {
        switch self {
        case .low:
            return "shakiness=4:accuracy=8:stepsize=6:mincontrast=0.28:fileformat=ascii"
        case .medium:
            return "shakiness=7:accuracy=11:stepsize=6:mincontrast=0.24:fileformat=ascii"
        case .high:
            return "shakiness=10:accuracy=13:stepsize=4:mincontrast=0.20:fileformat=ascii"
        }
    }

    var transformParameters: String {
        switch self {
        case .low:
            return "smoothing=6:optalgo=gauss:maxshift=12:maxangle=0:crop=black:optzoom=0:zoomspeed=0.10:interpol=bicubic"
        case .medium:
            return "smoothing=10:optalgo=gauss:maxshift=20:maxangle=0:crop=black:optzoom=0:zoomspeed=0.10:interpol=bicubic"
        case .high:
            return "smoothing=22:optalgo=gauss:maxshift=32:maxangle=0:crop=black:optzoom=1:zoomspeed=0.08:interpol=bicubic"
        }
    }

    func buildDetectFilter(transformsPath: String) -> String {
        let escaped = escapeFilterValue(transformsPath)
        return "fps=30000/1001,vidstabdetect=result='\(escaped)':\(detectParameters)"
    }

    func buildTransformFilter(transformsPath: String) -> String {
        let escaped = escapeFilterValue(transformsPath)
        return "fps=30000/1001,vidstabtransform=input='\(escaped)':\(transformParameters),unsharp=5:5:0.5:3:3:0.2"
    }

    private func escapeFilterValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
