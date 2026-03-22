//
//  WatermarkConfig.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 16/03/26.
//

import SwiftUI
import AppKit

struct WatermarkConfig: Equatable {
    var text: String = ""
    var fontSize: CGFloat = 48
    var color: Color = .white
    var opacity: Double = 1.0
    var position: CGPoint = CGPoint(x: 0.5, y: 0.5) // normalized 0–1

    var isEnabled: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nsColor: NSColor {
        NSColor(color).withAlphaComponent(CGFloat(opacity))
    }

    static let `default` = WatermarkConfig()
}
