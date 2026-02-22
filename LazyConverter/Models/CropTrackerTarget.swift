//
//  CropTrackerTarget.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 21/02/26.
//

import CoreGraphics

enum CropTrackerTarget {
    static func squareSizePixels(cropRect: CGRect, videoSize: CGSize) -> CGFloat {
        let width = max(1.0, abs(videoSize.width))
        let height = max(1.0, abs(videoSize.height))
        let cropWidthPixels = max(1.0, cropRect.width * width)
        let cropHeightPixels = max(1.0, cropRect.height * height)

        let base = min(width, height) * 0.06
        let maxInsideCrop = min(cropWidthPixels, cropHeightPixels) * 0.45
        let clamped = min(max(24.0, base), maxInsideCrop)
        return max(8.0, clamped)
    }

    static func normalizedTargetRect(in cropRect: CGRect, videoSize: CGSize) -> CGRect {
        let sizePixels = squareSizePixels(cropRect: cropRect, videoSize: videoSize)
        let width = max(1.0, abs(videoSize.width))
        let height = max(1.0, abs(videoSize.height))

        let sizeNormX = sizePixels / width
        let sizeNormY = sizePixels / height
        let sizeNorm = min(sizeNormX, sizeNormY)

        let centerX = cropRect.midX
        let centerY = cropRect.midY

        let rect = CGRect(
            x: centerX - sizeNorm / 2.0,
            y: centerY - sizeNorm / 2.0,
            width: sizeNorm,
            height: sizeNorm
        )
        return clampNormalized(rect)
    }

    static func clampNormalized(_ rect: CGRect) -> CGRect {
        var normalized = rect
        normalized.origin.x = max(0.0, min(1.0, normalized.origin.x))
        normalized.origin.y = max(0.0, min(1.0, normalized.origin.y))
        normalized.size.width = max(0.0001, min(1.0 - normalized.origin.x, normalized.size.width))
        normalized.size.height = max(0.0001, min(1.0 - normalized.origin.y, normalized.size.height))
        return normalized
    }
}
