import SwiftUI
import AppKit

struct WatermarkOverlayView: View {
    @Binding var watermarkConfig: WatermarkConfig
    let videoSize: CGSize
    let playerFrame: CGRect
    /// Optional crop rect in normalized 0–1 coordinates. When present, watermark is constrained within the crop area.
    var cropRect: CGRect?

    @State private var isDragging = false

    var body: some View {
        GeometryReader { _ in
            let videoFrame = calculateVideoFrame(videoSize: videoSize, playerFrame: playerFrame)

            // If crop is active, compute the crop sub-frame within the video frame
            let effectiveFrame = effectiveBounds(videoFrame: videoFrame)

            let wmText = watermarkConfig.text
            let wmFontSize = scaledFontSize(baseFontSize: watermarkConfig.fontSize, videoFrame: videoFrame)

            // Calculate watermark size estimate for boundary clamping
            let textSize = estimateTextSize(text: wmText, fontSize: wmFontSize)

            // Convert normalized position to pixel position within the effective bounds
            let pixelX = watermarkConfig.position.x * (effectiveFrame.width - textSize.width) + effectiveFrame.minX
            let pixelY = watermarkConfig.position.y * (effectiveFrame.height - textSize.height) + effectiveFrame.minY

            Text(wmText)
                .font(.system(size: wmFontSize, weight: .bold))
                .foregroundColor(watermarkConfig.color.opacity(watermarkConfig.opacity))
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .position(
                    x: pixelX + textSize.width / 2,
                    y: pixelY + textSize.height / 2
                )
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isDragging = true
                            let dragX = value.location.x - textSize.width / 2
                            let dragY = value.location.y - textSize.height / 2

                            // Clamp within effective bounds (crop or full video)
                            let clampedX = max(effectiveFrame.minX, min(dragX, effectiveFrame.maxX - textSize.width))
                            let clampedY = max(effectiveFrame.minY, min(dragY, effectiveFrame.maxY - textSize.height))

                            // Normalize to 0–1 within effective bounds
                            let availableW = max(1, effectiveFrame.width - textSize.width)
                            let availableH = max(1, effectiveFrame.height - textSize.height)
                            let normX = (clampedX - effectiveFrame.minX) / availableW
                            let normY = (clampedY - effectiveFrame.minY) / availableH

                            watermarkConfig.position = CGPoint(
                                x: min(max(normX, 0), 1),
                                y: min(max(normY, 0), 1)
                            )
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
        }
    }

    /// Returns the effective bounding frame for the watermark.
    /// If a crop rect (normalized 0–1) is provided, maps it onto the video frame.
    /// Otherwise returns the full video frame.
    private func effectiveBounds(videoFrame: CGRect) -> CGRect {
        guard let crop = cropRect else { return videoFrame }

        let cropX = videoFrame.minX + crop.origin.x * videoFrame.width
        let cropY = videoFrame.minY + crop.origin.y * videoFrame.height
        let cropW = crop.width * videoFrame.width
        let cropH = crop.height * videoFrame.height
        return CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
    }

    /// Calculates the actual video frame within the player, accounting for aspect ratio (letterboxing/pillarboxing).
    private func calculateVideoFrame(videoSize: CGSize, playerFrame: CGRect) -> CGRect {
        let videoAspect = videoSize.width / videoSize.height
        let playerAspect = playerFrame.width / playerFrame.height

        let width, height: CGFloat
        if videoAspect > playerAspect {
            width = playerFrame.width
            height = width / videoAspect
        } else {
            height = playerFrame.height
            width = height * videoAspect
        }

        let x = (playerFrame.width - width) / 2
        let y = (playerFrame.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Scales the base font size relative to the video frame vs. actual video resolution.
    private func scaledFontSize(baseFontSize: CGFloat, videoFrame: CGRect) -> CGFloat {
        let scale = videoFrame.width / max(1, videoSize.width)
        return max(8, baseFontSize * scale)
    }

    /// Estimates the rendered size of text for a given font size.
    private func estimateTextSize(text: String, fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return CGSize(width: size.width + 8, height: size.height + 4) // padding
    }
}
