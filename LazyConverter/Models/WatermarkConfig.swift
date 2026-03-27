//
//  WatermarkConfig.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 16/03/26.
//

import SwiftUI
import AppKit

struct WatermarkConfig: Equatable {
    static let systemFontToken = "__system__"

    var text: String = ""
    var fontName: String = WatermarkConfig.systemFontToken
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

    func resolvedNSFont(ofSize size: CGFloat) -> NSFont {
        if fontName == Self.systemFontToken {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: fontName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }

    func resolvedSwiftUIFont(ofSize size: CGFloat) -> Font {
        if fontName == Self.systemFontToken {
            return .system(size: size, weight: .bold)
        }
        return .custom(fontName, size: size)
    }

    static let `default` = WatermarkConfig()
}
