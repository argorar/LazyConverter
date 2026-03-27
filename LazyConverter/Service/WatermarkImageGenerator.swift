//
//  WatermarkImageGenerator.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 16/03/26.
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Generates a transparent PNG image containing the watermark text for FFmpeg overlay.
enum WatermarkImageGenerator {

    static func generate(config: WatermarkConfig, videoSize: CGSize, cropRect: CGRect? = nil) -> URL? {
        let fullW = abs(videoSize.width)
        let fullH = abs(videoSize.height)
        guard fullW > 0, fullH > 0 else { return nil }

        let text = config.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // When crop is active, the canvas matches the cropped video dimensions
        let canvasW: Int
        let canvasH: Int
        if let crop = cropRect {
            canvasW = Int(crop.width * fullW)
            canvasH = Int(crop.height * fullH)
        } else {
            canvasW = Int(fullW)
            canvasH = Int(fullH)
        }
        guard canvasW > 0, canvasH > 0 else { return nil }

        // Create a bitmap context with transparency
        guard let context = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip the context for correct text rendering (CoreGraphics has Y-up)
        context.translateBy(x: 0, y: CGFloat(canvasH))
        context.scaleBy(x: 1, y: -1)

        // Set up text attributes
        let nsColor = NSColor(config.color).withAlphaComponent(CGFloat(config.opacity))
        let font = config.resolvedNSFont(ofSize: config.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor
        ]

        // Measure text size
        let textSize = (text as NSString).size(withAttributes: attributes)

        // Position is normalized 0–1 within the canvas (which is already the cropped size)
        let availableW = max(1, CGFloat(canvasW) - textSize.width)
        let availableH = max(1, CGFloat(canvasH) - textSize.height)
        let x = config.position.x * availableW
        let y = config.position.y * availableH

        // Draw text
        let drawRect = CGRect(x: x, y: y, width: textSize.width + 4, height: textSize.height + 2)
        let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsGraphicsContext
        (text as NSString).draw(in: drawRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        // Create image from context
        guard let cgImage = context.makeImage() else { return nil }

        // Write to a temporary PNG file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watermark_\(Int(Date().timeIntervalSince1970)).png")

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: canvasW, height: canvasH))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        do {
            try pngData.write(to: tempURL)
            return tempURL
        } catch {
            print("❌ WatermarkImageGenerator: Failed to write PNG: \(error)")
            return nil
        }
    }
}
