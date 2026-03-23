//
//  GlassCardStyle.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 22/03/26.
//

import SwiftUI
import AppKit

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    var material: NSVisualEffectView.Material = .hudWindow
    var strokeOpacity: Double = 0.22

    func body(content: Content) -> some View {
        content
            .background(
                LiquidGlassBackgroundView(material: material, blendingMode: .withinWindow, emphasized: false)
                    .opacity(0.62)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(min(strokeOpacity, 0.10)), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = 12,
        material: NSVisualEffectView.Material = .hudWindow,
        strokeOpacity: Double = 0.22
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, material: material, strokeOpacity: strokeOpacity))
    }

    @ViewBuilder
    func adaptiveCard(
        useGlass: Bool,
        cornerRadius: CGFloat = 12,
        material: NSVisualEffectView.Material = .hudWindow,
        strokeOpacity: Double = 0.22,
        fallbackColor: Color = Color(nsColor: .controlBackgroundColor),
        fallbackOpacity: Double = 1.0
    ) -> some View {
        if useGlass {
            self.glassCard(cornerRadius: cornerRadius, material: material, strokeOpacity: strokeOpacity)
        } else {
            self
                .background(fallbackColor.opacity(fallbackOpacity))
                .cornerRadius(cornerRadius)
        }
    }
}
