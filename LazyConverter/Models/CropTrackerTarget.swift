//
//  CropTrackerTarget.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 21/02/26.
//

import CoreGraphics

enum CropTrackerTarget {
    static let defaultPivot = CGPoint(x: 0.5, y: 0.5)

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

    static func normalizedTargetRect(
        in cropRect: CGRect,
        videoSize: CGSize,
        pivot: CGPoint = defaultPivot
    ) -> CGRect {
        let sizePixels = squareSizePixels(cropRect: cropRect, videoSize: videoSize)
        let width = max(1.0, abs(videoSize.width))
        let height = max(1.0, abs(videoSize.height))

        let targetWidthNorm = min(sizePixels / width, cropRect.width)
        let targetHeightNorm = min(sizePixels / height, cropRect.height)

        let clampedPivot = clampUnitPoint(pivot)
        let desiredCenterX = cropRect.minX + cropRect.width * clampedPivot.x
        let desiredCenterY = cropRect.minY + cropRect.height * clampedPivot.y
        let halfWidth = targetWidthNorm / 2.0
        let halfHeight = targetHeightNorm / 2.0

        let minCenterX = cropRect.minX + halfWidth
        let maxCenterX = cropRect.maxX - halfWidth
        let minCenterY = cropRect.minY + halfHeight
        let maxCenterY = cropRect.maxY - halfHeight

        let centerX = min(max(desiredCenterX, minCenterX), maxCenterX)
        let centerY = min(max(desiredCenterY, minCenterY), maxCenterY)

        let rect = CGRect(
            x: centerX - targetWidthNorm / 2.0,
            y: centerY - targetHeightNorm / 2.0,
            width: targetWidthNorm,
            height: targetHeightNorm
        )
        return clampNormalized(rect)
    }

    static func clampUnitPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0.0, min(1.0, point.x)),
            y: max(0.0, min(1.0, point.y))
        )
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
