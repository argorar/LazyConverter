//
//  ColorAdjustments.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 20/01/26.
//


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
        return "eq=brightness=\(brightness):contrast=\(contrast):gamma=\(gamma):saturation=\(saturation)"
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

