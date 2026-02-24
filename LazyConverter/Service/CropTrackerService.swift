//
//  CropTrackerService.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 21/02/26.
//

import Foundation
import AVFoundation
import CoreGraphics
import Vision

enum CropTrackerServiceError: LocalizedError {
    case noVideoTrack
    case invalidRange
    case noFrames
    case noKeyframes

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track available for tracking"
        case .invalidRange:
            return "Invalid tracking time range"
        case .noFrames:
            return "Could not read frames for tracking"
        case .noKeyframes:
            return "Tracking did not produce keyframes"
        }
    }
}

enum CropTrackerService {
    private static let trackingSampleFactor: Double = 0.70

    static func track(
        inputURL: URL,
        initialCropRect: CGRect,
        trackerPivot: CGPoint = CropTrackerTarget.defaultPivot,
        trimStart: Double?,
        trimEnd: Double?,
        videoInfo: VideoInfo?
    ) async throws -> [CropDynamicKeyframe] {
        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = try await loadPrimaryVideoTrack(from: asset) else {
            throw CropTrackerServiceError.noVideoTrack
        }

        let duration = await resolvedDuration(asset: asset, videoInfo: videoInfo)
        let bounds = resolvedBounds(duration: duration, trimStart: trimStart, trimEnd: trimEnd)
        guard bounds.end > bounds.start else {
            throw CropTrackerServiceError.invalidRange
        }

        let normalizedInitial = clampNormalizedRect(initialCropRect)
        let normalizedPivot = CropTrackerTarget.clampUnitPoint(trackerPivot)
        let pixelSize = await resolvedPixelSize(videoTrack: videoTrack, videoInfo: videoInfo)
        let fixedCropSize = normalizedInitial.size
        let initialTargetRect = CropTrackerTarget.normalizedTargetRect(
            in: normalizedInitial,
            videoSize: pixelSize,
            pivot: normalizedPivot
        )
        let targetSizePixels = CropTrackerTarget.squareSizePixels(cropRect: normalizedInitial, videoSize: pixelSize)
        let sourceFPS = await resolvedSourceFPS(videoTrack: videoTrack, videoInfo: videoInfo)
        let sampleFPS = resolvedSampleFPS(sourceFPS: sourceFPS, duration: bounds.end - bounds.start)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = resolvedTimeTolerance()
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let visionInitial = toVisionRect(initialTargetRect)
        let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: visionInitial))
        request.trackingLevel = .accurate
        request.preferBackgroundProcessing = false
        let minimumConfidence = resolvedMinimumConfidence()

        var keyframesByFrame: [Int: CropDynamicKeyframe] = [:]
        var lastTargetRect = initialTargetRect
        var lastRect = normalizedInitial

        let startFrame = frameIndex(for: bounds.start, fps: sourceFPS)
        if let startCrop = cropString(from: lastRect, pixelSize: pixelSize) {
            keyframesByFrame[startFrame] = CropDynamicKeyframe(time: bounds.start, crop: startCrop)
        }

        let sampleTimes = makeSampleTimes(start: bounds.start, end: bounds.end, sampleFPS: sampleFPS)
        var processedFrames = 0

        for sample in sampleTimes {
            guard let frame = await copyFrame(at: sample, generator: generator) else { continue }
            processedFrames += 1

            let handler = VNImageRequestHandler(cgImage: frame.image, options: [:])
            do {
                try handler.perform([request])
                if let tracked = request.results?.first as? VNDetectedObjectObservation, tracked.confidence >= minimumConfidence {
                    request.inputObservation = tracked
                    let candidateTargetRect = targetRectFromVision(observation: tracked.boundingBox, fixedSize: initialTargetRect.size)
                    let stabilizedTargetRect = stabilizeTargetRect(
                        previous: lastTargetRect,
                        candidate: candidateTargetRect,
                        pixelSize: pixelSize,
                        targetSizePixels: targetSizePixels
                    )
                    lastTargetRect = stabilizedTargetRect
                    let targetCenter = CGPoint(x: stabilizedTargetRect.midX, y: stabilizedTargetRect.midY)
                    lastRect = cropRectAnchored(
                        on: targetCenter,
                        cropSize: fixedCropSize,
                        pivot: normalizedPivot
                    )
                }
            } catch {
                // Keep last tracked rect if Vision fails on this frame.
            }

            if let crop = cropString(from: lastRect, pixelSize: pixelSize) {
                let frameKey = frameIndex(for: frame.time, fps: sourceFPS)
                keyframesByFrame[frameKey] = CropDynamicKeyframe(time: frame.time, crop: crop)
            }
        }

        if processedFrames == 0 {
            throw CropTrackerServiceError.noFrames
        }

        let endFrame = frameIndex(for: bounds.end, fps: sourceFPS)
        if let endCrop = cropString(from: lastRect, pixelSize: pixelSize) {
            keyframesByFrame[endFrame] = CropDynamicKeyframe(time: bounds.end, crop: endCrop)
        }

        let keyframes = keyframesByFrame.values.sorted { $0.time < $1.time }
        guard !keyframes.isEmpty else {
            throw CropTrackerServiceError.noKeyframes
        }
        return keyframes
    }

    private static func loadPrimaryVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack? {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        return tracks.first
    }

    private static func resolvedDuration(asset: AVAsset, videoInfo: VideoInfo?) async -> Double {
        let fromAsset: Double
        if let duration = try? await asset.load(.duration) {
            fromAsset = duration.seconds
        } else {
            fromAsset = 0.0
        }
        let fromInfo = videoInfo?.duration ?? 0
        return max(0.0, fromAsset.isFinite && fromAsset > 0 ? fromAsset : fromInfo)
    }

    private static func resolvedBounds(duration: Double, trimStart: Double?, trimEnd: Double?) -> (start: Double, end: Double) {
        let start = max(0.0, trimStart ?? 0.0)
        var end = trimEnd ?? duration
        if duration > 0 {
            end = min(end, duration)
        }
        end = max(start, end)
        return (start, end)
    }

    private static func resolvedPixelSize(videoTrack: AVAssetTrack, videoInfo: VideoInfo?) async -> CGSize {
        if let infoSize = videoInfo?.videoSize, abs(infoSize.width) > 1, abs(infoSize.height) > 1 {
            return CGSize(width: abs(infoSize.width), height: abs(infoSize.height))
        }

        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let transformed = naturalSize.applying(preferredTransform)
        return CGSize(width: max(1.0, abs(transformed.width)), height: max(1.0, abs(transformed.height)))
    }

    private static func resolvedSourceFPS(videoTrack: AVAssetTrack, videoInfo: VideoInfo?) async -> Double {
        if let infoFPS = videoInfo?.frameRate, infoFPS > 0 {
            return max(1.0, infoFPS)
        }

        if let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate) {
            return max(1.0, Double(nominalFrameRate))
        }

        return 1.0
    }

    private static func resolvedSampleFPS(sourceFPS: Double, duration: Double) -> Double {
        let baseRaw = min(20.0, max(8.0, sourceFPS / 2.0))
        let base = max(1.0, baseRaw * trackingSampleFactor)
        let maxSamples = max(1.0, 5000.0 * trackingSampleFactor)

        guard duration > 0.000001 else { return base }
        let projectedSamples = duration * base
        if projectedSamples <= maxSamples {
            return base
        }
        return max(1.0, maxSamples / duration)
    }

    private static func resolvedTimeTolerance() -> CMTime {
        .zero
    }

    private static func resolvedMinimumConfidence() -> Float {
        0.15
    }

    private static func makeSampleTimes(start: Double, end: Double, sampleFPS: Double) -> [Double] {
        guard end > start else { return [start] }

        let step = 1.0 / max(1.0, sampleFPS)
        var times: [Double] = []
        var time = start
        while time < end {
            times.append(time)
            time += step
        }
        if let last = times.last {
            if abs(last - end) > 0.000001 {
                times.append(end)
            }
        } else {
            times.append(end)
        }
        return times
    }
    
    private static func copyFrame(at time: Double, generator: AVAssetImageGenerator) async -> (image: CGImage, time: Double)? {
        let requested = CMTime(seconds: max(0.0, time), preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: requested) { cgImage, actualTime, error in
                guard let cgImage = cgImage, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let actualSeconds = actualTime.seconds.isFinite ? actualTime.seconds : time
                continuation.resume(returning: (cgImage, max(0.0, actualSeconds)))
            }
        }
    }

    private static func targetRectFromVision(observation: CGRect, fixedSize: CGSize) -> CGRect {
        let topLeftRect = CGRect(
            x: observation.origin.x,
            y: 1.0 - observation.origin.y - observation.height,
            width: observation.width,
            height: observation.height
        )

        let centerX = topLeftRect.midX
        let centerY = topLeftRect.midY
        let rect = CGRect(
            x: centerX - fixedSize.width / 2.0,
            y: centerY - fixedSize.height / 2.0,
            width: fixedSize.width,
            height: fixedSize.height
        )
        return clampNormalizedRect(rect)
    }

    private static func stabilizeTargetRect(
        previous: CGRect,
        candidate: CGRect,
        pixelSize: CGSize,
        targetSizePixels: CGFloat
    ) -> CGRect {
        let previousCenter = CGPoint(x: previous.midX, y: previous.midY)
        let candidateCenter = CGPoint(x: candidate.midX, y: candidate.midY)
        let deltaX = candidateCenter.x - previousCenter.x
        let deltaY = candidateCenter.y - previousCenter.y

        let widthPixels = max(1.0, abs(pixelSize.width))
        let heightPixels = max(1.0, abs(pixelSize.height))
        let pixelDeltaX = deltaX * widthPixels
        let pixelDeltaY = deltaY * heightPixels

        let maxJumpX = resolvedMaxJumpPixels(targetSizePixels: targetSizePixels, axis: .horizontal)
        let maxJumpY = resolvedMaxJumpPixels(targetSizePixels: targetSizePixels, axis: .vertical)
        let clampedDeltaX = max(-maxJumpX, min(maxJumpX, pixelDeltaX))
        let clampedDeltaY = max(-maxJumpY, min(maxJumpY, pixelDeltaY))

        let clampedCenter = CGPoint(
            x: previousCenter.x + (clampedDeltaX / widthPixels),
            y: previousCenter.y + (clampedDeltaY / heightPixels)
        )

        let alphaX = resolvedSmoothingAlpha(axis: .horizontal)
        let alphaY = resolvedSmoothingAlpha(axis: .vertical)
        let smoothedCenter = CGPoint(
            x: previousCenter.x + (clampedCenter.x - previousCenter.x) * alphaX,
            y: previousCenter.y + (clampedCenter.y - previousCenter.y) * alphaY
        )

        let rect = CGRect(
            x: smoothedCenter.x - previous.width / 2.0,
            y: smoothedCenter.y - previous.height / 2.0,
            width: previous.width,
            height: previous.height
        )
        return clampNormalizedRect(rect)
    }

    private enum TrackerAxis {
        case horizontal
        case vertical
    }

    private static func resolvedMaxJumpPixels(
        targetSizePixels: CGFloat,
        axis: TrackerAxis
    ) -> CGFloat {
        let base = max(12.0, targetSizePixels * 1.8)

        // Vertical motion in real footage tends to be more abrupt; allow larger per-frame jump.
        return axis == .vertical ? base * 1.2 : base
    }

    private static func resolvedSmoothingAlpha(axis: TrackerAxis) -> CGFloat {
        axis == .vertical ? 0.90 : 0.82
    }

    private static func cropRectAnchored(on pivotPoint: CGPoint, cropSize: CGSize, pivot: CGPoint) -> CGRect {
        let clampedPivot = CropTrackerTarget.clampUnitPoint(pivot)
        let rect = CGRect(
            x: pivotPoint.x - cropSize.width * clampedPivot.x,
            y: pivotPoint.y - cropSize.height * clampedPivot.y,
            width: cropSize.width,
            height: cropSize.height
        )
        return clampNormalizedRect(rect)
    }

    private static func toVisionRect(_ topLeftRect: CGRect) -> CGRect {
        let clamped = clampNormalizedRect(topLeftRect)
        return CGRect(
            x: clamped.origin.x,
            y: 1.0 - clamped.origin.y - clamped.height,
            width: clamped.width,
            height: clamped.height
        )
    }

    private static func clampNormalizedRect(_ rect: CGRect) -> CGRect {
        var normalized = rect
        normalized.origin.x = max(0.0, min(1.0, normalized.origin.x))
        normalized.origin.y = max(0.0, min(1.0, normalized.origin.y))
        normalized.size.width = max(0.0001, min(1.0 - normalized.origin.x, normalized.size.width))
        normalized.size.height = max(0.0001, min(1.0 - normalized.origin.y, normalized.size.height))
        return normalized
    }

    private static func cropString(from rect: CGRect, pixelSize: CGSize) -> String? {
        let clamped = clampNormalizedRect(rect)
        let widthPixels = max(1, Int(round(abs(pixelSize.width))))
        let heightPixels = max(1, Int(round(abs(pixelSize.height))))
        let widthPixelsCGFloat = CGFloat(widthPixels)
        let heightPixelsCGFloat = CGFloat(heightPixels)

        var cropW = max(1, Int(round(clamped.width * widthPixelsCGFloat)))
        var cropH = max(1, Int(round(clamped.height * heightPixelsCGFloat)))
        var cropX = Int(round(clamped.origin.x * widthPixelsCGFloat))
        var cropY = Int(round(clamped.origin.y * heightPixelsCGFloat))

        cropW = min(cropW, widthPixels)
        cropH = min(cropH, heightPixels)
        cropX = max(0, min(widthPixels - cropW, cropX))
        cropY = max(0, min(heightPixels - cropH, cropY))

        guard cropW > 0, cropH > 0 else { return nil }
        return "\(cropX):\(cropY):\(cropW):\(cropH)"
    }

    private static func frameIndex(for time: Double, fps: Double) -> Int {
        max(0, Int(round(max(0.0, time) * max(1.0, fps))))
    }
}
