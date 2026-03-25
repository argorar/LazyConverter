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
    var material: NSVisualEffectView.Material = .sidebar
    var strokeOpacity: Double = 0.22

    func body(content: Content) -> some View {
        content
            .background(
                LiquidGlassBackgroundView(
                    material: material,
                    blendingMode: .withinWindow,
                    emphasized: false
                )
                .opacity(0.34)
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.01),
                                Color.white.opacity(0.01),
                                Color.black.opacity(0.01),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(min(strokeOpacity, 0.20)), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 6)
            .shadow(color: Color.white.opacity(0.05), radius: 1, x: 0, y: 1)
            .compositingGroup()
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = 12,
        material: NSVisualEffectView.Material = .sidebar,
        strokeOpacity: Double = 0.22
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, material: material, strokeOpacity: strokeOpacity))
    }

    @ViewBuilder
    func adaptiveCard(
        useGlass: Bool,
        cornerRadius: CGFloat = 12,
        material: NSVisualEffectView.Material = .sidebar,
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
