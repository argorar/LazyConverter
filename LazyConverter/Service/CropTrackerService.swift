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
        trackerScale: CGFloat = CropTrackerTarget.defaultScale,
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
            pivot: normalizedPivot,
            scale: trackerScale
        )
        let targetSizePixels = CropTrackerTarget.squareSizePixels(
            cropRect: normalizedInitial,
            videoSize: pixelSize,
            scale: trackerScale
        )
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

        var rawSamples: [(time: Double, rect: CGRect)] = []
        var lastTargetRect = initialTargetRect
        var lastRect = normalizedInitial

        rawSamples.append((time: bounds.start, rect: lastRect))

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

            rawSamples.append((time: frame.time, rect: lastRect))
        }

        if processedFrames == 0 {
            throw CropTrackerServiceError.noFrames
        }

        rawSamples.append((time: bounds.end, rect: lastRect))

        let sortedSamples = rawSamples.sorted { $0.time < $1.time }
        let smoothedSamples = smoothSamples(sortedSamples)
        let optimizedSamples = optimizeKeyframes(samples: smoothedSamples, pixelSize: pixelSize)

        var keyframes: [CropDynamicKeyframe] = []
        for sample in optimizedSamples {
            if let crop = cropString(from: sample.rect, pixelSize: pixelSize) {
                keyframes.append(CropDynamicKeyframe(time: sample.time, crop: crop))
            }
        }

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

        // Deadband: avoid micro-jitter when object is stationary
        let jumpDistance = hypot(pixelDeltaX, pixelDeltaY)
        if jumpDistance < 2.0 {
            return previous
        }

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

    private static func smoothSamples(_ samples: [(time: Double, rect: CGRect)]) -> [(time: Double, rect: CGRect)] {
        guard samples.count > 2 else { return samples }
        let count = samples.count
        var smoothed = samples
        for i in 1..<(count - 1) {
            let p0 = samples[max(0, i - 1)].rect
            let p1 = samples[i].rect
            let p2 = samples[min(count - 1, i + 1)].rect
            let midX = p0.midX * 0.25 + p1.midX * 0.50 + p2.midX * 0.25
            let midY = p0.midY * 0.25 + p1.midY * 0.50 + p2.midY * 0.25
            let rect = CGRect(
                x: midX - p1.width / 2.0,
                y: midY - p1.height / 2.0,
                width: p1.width,
                height: p1.height
            )
            smoothed[i] = (time: samples[i].time, rect: clampNormalizedRect(rect))
        }
        return smoothed
    }

    private static func optimizeKeyframes(
        samples: [(time: Double, rect: CGRect)],
        pixelSize: CGSize,
        maxKeyframes: Int = 60
    ) -> [(time: Double, rect: CGRect)] {
        guard samples.count > 2 else { return samples }

        let widthPixels = max(1.0, abs(pixelSize.width))
        let heightPixels = max(1.0, abs(pixelSize.height))
        let baseTolerance = max(6.0, min(widthPixels, heightPixels) * 0.008)

        var tolerance = baseTolerance
        var selectedIndices: [Int] = []

        // ponytail: iterative tolerance scaling caps keyframe count to prevent bloated FFmpeg commands
        for _ in 0..<5 {
            var keep = Set<Int>()
            keep.insert(0)
            keep.insert(samples.count - 1)
            simplifyRange(
                start: 0,
                end: samples.count - 1,
                samples: samples,
                widthPixels: widthPixels,
                heightPixels: heightPixels,
                tolerance: tolerance,
                keep: &keep
            )
            selectedIndices = keep.sorted()
            if selectedIndices.count <= maxKeyframes {
                break
            }
            tolerance *= 1.4
        }

        var prunedIndices: [Int] = [selectedIndices[0]]
        for i in 1..<selectedIndices.count {
            let prevIdx = prunedIndices.last!
            let currIdx = selectedIndices[i]
            let isLast = (i == selectedIndices.count - 1)

            if isLast {
                prunedIndices.append(currIdx)
                break
            }

            let timeDelta = samples[currIdx].time - samples[prevIdx].time
            let prevRect = samples[prevIdx].rect
            let currRect = samples[currIdx].rect
            let dx = (currRect.midX - prevRect.midX) * widthPixels
            let dy = (currRect.midY - prevRect.midY) * heightPixels
            let dist = hypot(dx, dy)

            if timeDelta >= 0.25 || dist > tolerance {
                prunedIndices.append(currIdx)
            }
        }

        return prunedIndices.map { samples[$0] }
    }

    private static func simplifyRange(
        start: Int,
        end: Int,
        samples: [(time: Double, rect: CGRect)],
        widthPixels: CGFloat,
        heightPixels: CGFloat,
        tolerance: CGFloat,
        keep: inout Set<Int>
    ) {
        guard end > start + 1 else { return }

        let t0 = samples[start].time
        let t1 = samples[end].time
        let duration = t1 - t0
        guard duration > 0.000001 else { return }

        let x0 = samples[start].rect.midX * widthPixels
        let y0 = samples[start].rect.midY * heightPixels
        let x1 = samples[end].rect.midX * widthPixels
        let y1 = samples[end].rect.midY * heightPixels

        var maxDist: CGFloat = 0.0
        var maxIdx = start

        for i in (start + 1)..<end {
            let t = samples[i].time
            let alpha = CGFloat((t - t0) / duration)
            let expectedX = x0 + alpha * (x1 - x0)
            let expectedY = y0 + alpha * (y1 - y0)
            let actualX = samples[i].rect.midX * widthPixels
            let actualY = samples[i].rect.midY * heightPixels
            let dist = hypot(actualX - expectedX, actualY - expectedY)

            if dist > maxDist {
                maxDist = dist
                maxIdx = i
            }
        }

        if maxDist > tolerance {
            keep.insert(maxIdx)
            simplifyRange(start: start, end: maxIdx, samples: samples, widthPixels: widthPixels, heightPixels: heightPixels, tolerance: tolerance, keep: &keep)
            simplifyRange(start: maxIdx, end: end, samples: samples, widthPixels: widthPixels, heightPixels: heightPixels, tolerance: tolerance, keep: &keep)
        }
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
        axis == .vertical ? 0.32 : 0.28
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
        let totalW = max(2, (Int(round(abs(pixelSize.width))) / 2) * 2)
        let totalH = max(2, (Int(round(abs(pixelSize.height))) / 2) * 2)
        let widthPixelsCGFloat = CGFloat(totalW)
        let heightPixelsCGFloat = CGFloat(totalH)

        var cropW = max(2, (Int(round(clamped.width * widthPixelsCGFloat)) / 2) * 2)
        var cropH = max(2, (Int(round(clamped.height * heightPixelsCGFloat)) / 2) * 2)
        cropW = min(cropW, totalW)
        cropH = min(cropH, totalH)
        var cropX = (Int(round(clamped.origin.x * widthPixelsCGFloat)) / 2) * 2
        var cropY = (Int(round(clamped.origin.y * heightPixelsCGFloat)) / 2) * 2

        cropX = max(0, min(totalW - cropW, cropX))
        cropY = max(0, min(totalH - cropH, cropY))

        guard cropW > 0, cropH > 0 else { return nil }
        return "\(cropX):\(cropY):\(cropW):\(cropH)"
    }
}
