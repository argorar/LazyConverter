//
//  ColorAdjustments.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 20/01/26.
//


import Foundation

struct ColorAdjustments: Codable, Equatable {
    var brightness: Double = 0.0    // -1.0 a 1.0
    var contrast: Double = 1.0      // 0.0 a 2.0 (UI range)
    var gamma: Double = 1.0         // 0.5 a 2.5
    var saturation: Double = 1.0    // 0.0 a 2.0
    
    static let `default` = ColorAdjustments()
    
    var isModified: Bool {
        self != .default
    }
    
    func toFFmpegFilter() -> String? {
        guard isModified else { return nil }
        
        var filters: [String] = []
        
        func fmt(_ value: Double) -> String {
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        
        // Match CIColorControls saturation via RGB luma mix (Rec.709)
        if saturation != 1.0 {
            let s = saturation
            let lr = 0.2126
            let lg = 0.7152
            let lb = 0.0722
            
            let a = (1.0 - s) * lr
            let b = (1.0 - s) * lg
            let c = (1.0 - s) * lb
            
            let rr = a + s
            let rg = b
            let rb = c
            
            let gr = a
            let gg = b + s
            let gb = c
            
            let br = a
            let bg = b
            let bb = c + s
            
            filters.append(
                "colorchannelmixer=" +
                "rr=\(fmt(rr)):rg=\(fmt(rg)):rb=\(fmt(rb)):" +
                "gr=\(fmt(gr)):gg=\(fmt(gg)):gb=\(fmt(gb)):" +
                "br=\(fmt(br)):bg=\(fmt(bg)):bb=\(fmt(bb))"
            )
        }
        
        if brightness != 0.0 || contrast != 1.0 || gamma != 1.0 {
            let expr = "clip(pow(clip(((val/maxval-0.5)*\(fmt(contrast))+0.5+\(fmt(brightness))),0,1),\(fmt(gamma)))*maxval,0,maxval)"
            let escaped = expr.replacingOccurrences(of: ",", with: "\\,")
            filters.append("lutrgb=r='\(escaped)':g='\(escaped)':b='\(escaped)'")
        }
        
        return filters.joined(separator: ",")
    }
    
    // Conversión para Core Image (para que coincida con FFmpeg)
    var ciColorControlsValues: (brightness: Double, contrast: Double, saturation: Double) {
        return (
            brightness: brightness,
            contrast: contrast,
            saturation: saturation
        )
    }
    
    var ciGammaValue: Double {
        return gamma  // Core Image y FFmpeg usan el mismo rango
    }
}
