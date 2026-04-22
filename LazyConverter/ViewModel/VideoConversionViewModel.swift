//
//  VideoConversionViewModel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 23/12/25.
//

import Combine
import AVFoundation
import AppKit
import SwiftUI
import Foundation

class VideoConversionViewModel: NSObject, ObservableObject {
    @AppStorage("selectedOutputDirectory") private var storedOutputDirectory: String = OutputDirectory.downloads.rawValue
    
    @Published var selectedFileName: String?
    @Published var selectedFormat: VideoFormat = .mp4
    @Published var selectedResolution: VideoResolution = .original
    @Published var quality: Double = 18
    @Published var maxOutputSizeMBInput: String = ""
    @Published var useGPU: Bool = false
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var errorLog: String?
    @Published var speedPercent: Double = 100.0 // 0.0 - 200.0
    @Published var dynamicSpeedEnabled: Bool = false {
        didSet {
            guard dynamicSpeedEnabled else { return }
            ensureDynamicSpeedBoundaryPoints()
        }
    }
    @Published private(set) var dynamicSpeedPoints: [SpeedMapPoint] = []
    @Published var videoInfo: VideoInfo?
    @Published var cropEnabled: Bool = false {
        didSet {
            if !cropEnabled {
                cropTrackerEnabled = false
                cropDynamicEnabled = false
            }
        }
    }
    @Published var cropDynamicEnabled: Bool = false {
        didSet {
            if cropDynamicEnabled == false {
                cropDynamicKeyframes.removeAll()
                dynamicStartFrameIndex = nil
                dynamicAutoEndFrameIndex = nil
                cropTrackerEnabled = false
                cropDynamicLockedAspectRatio = nil
            } else {
                captureDynamicCropAspectRatioIfNeeded()
                ensureStartDynamicKeyframe()
            }
        }
    }
    @Published var cropTrackerEnabled: Bool = false {
        didSet {
            if cropTrackerEnabled {
                cropDynamicEnabled = true
            }
        }
    }
    @Published var isTrackingCrop: Bool = false
    @Published private(set) var cropDynamicKeyframes: [Int: CropDynamicKeyframe] = [:]
    @Published private(set) var cropDynamicLockedAspectRatio: CGFloat?
    @Published var cropRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) // valores en 0–1
    @Published var cropAspectRatio: CropAspectRatioOption = .free {
        didSet {
            applyCropAspectRatio(cropAspectRatio)
        }
    }
    
    var effectiveLockedNormalizedAspectRatio: CGFloat? {
        guard let targetRatio = cropAspectRatio.ratio else { return nil }
        guard let size = videoInfo?.videoSize, size.width > 0, size.height > 0 else { return nil }
        return targetRatio * (CGFloat(size.height) / CGFloat(size.width))
    }
    
    private func applyCropAspectRatio(_ option: CropAspectRatioOption) {
        guard let targetRatio = option.ratio else { return }
        guard let size = videoInfo?.videoSize, size.width > 0, size.height > 0 else { return }
        
        let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
        var pixelW = cropRect.width * CGFloat(size.width)
        var pixelH = cropRect.height * CGFloat(size.height)
        
        if pixelW / pixelH > targetRatio {
            pixelW = pixelH * targetRatio
        } else {
            pixelH = pixelW / targetRatio
        }
        
        var newNormW = pixelW / CGFloat(size.width)
        var newNormH = pixelH / CGFloat(size.height)
        let normAspect = targetRatio * (CGFloat(size.height) / CGFloat(size.width))
        
        if newNormW > 1.0 {
            newNormW = 1.0
            newNormH = newNormW / normAspect
        }
        if newNormH > 1.0 {
            newNormH = 1.0
            newNormW = newNormH * normAspect
        }
        
        var newX = center.x - newNormW / 2
        var newY = center.y - newNormH / 2
        
        if newX < 0 { newX = 0 }
        if newY < 0 { newY = 0 }
        if newX + newNormW > 1 { newX = 1 - newNormW; if newX < 0 { newX = 0 } }
        if newY + newNormH > 1 { newY = 1 - newNormH; if newY < 0 { newY = 0 } }
        
        cropRect = CGRect(x: newX, y: newY, width: newNormW, height: newNormH)
    }
    @Published var cropTrackerPivot: CGPoint = CropTrackerTarget.defaultPivot
    @Published var stabilizationEnabled: Bool = false
    @Published var stabilizationLevel: VideoStabilizationLevel = .medium
    @Published var loopEnabled: Bool = false
    @Published var liveCurrentTime: Double = 0
    @Published var trimSegments: [TrimSegment] = [] {
        didSet {
            if cropDynamicEnabled {
                ensureStartDynamicKeyframe()
            }
            if dynamicSpeedEnabled {
                ensureDynamicSpeedBoundaryPoints()
            }
        }
    }
    @Published var activeTrimSegmentID: UUID? = nil
    @Published var showUpdateDialog = false
    @Published var latestDownloadURL: String? = nil
    @Published var hasUpdateAvailable = false
    @Published var colorAdjustments = ColorAdjustments.default
    @Published var queueManager = QueueManager()
    @Published var showQueueWindow = false
    @Published var superCompression: Bool = false {
        didSet {
            if superCompression {
                cropEnabled = false
                dynamicSpeedEnabled = false
                stabilizationEnabled = false
                colorAdjustments = ColorAdjustments.default
            }
        }
    }
    @Published var superCompressionGPU: Bool = false
    @Published var frameRateSettings = FrameRateSettings()
    @Published var watermarkConfig = WatermarkConfig()
    @Published var showWatermarkSheet = false
    @Published var outputDirectory: OutputDirectory = .downloads
    @Published var isYtDlpInstalled: Bool = false
    @Published var ytDlpURLInput: String = ""
    @Published var isYtDlpDownloading: Bool = false
    @Published var ytDlpDownloadProgress: Double = 0.0
    @Published var ytDlpDownloadedFileURL: URL?
    @Published var ytDlpErrorMessage: String?
    @Published var ytDlpErrorLog: String?
    private var dynamicStartFrameIndex: Int?
    private var dynamicAutoEndFrameIndex: Int?
    private var activeTrackerJobID: UUID?
    
    @Published var selectedFileURL: URL? {
        didSet {
            if selectedFileURL != nil {
                errorMessage = nil
            }
        }
    }

    var lang: LanguageManager?
    override init() {
        super.init()
        outputDirectory = OutputDirectory(rawValue: storedOutputDirectory) ?? .downloads
        checkYtDlpAvailability()
    }
    
    var brightness: Binding<Double> {
        Binding(
            get: { self.colorAdjustments.brightness },
            set: { self.colorAdjustments.brightness = $0 }
        )
    }

    var contrast: Binding<Double> {
        Binding(
            get: { self.colorAdjustments.contrast },
            set: { self.colorAdjustments.contrast = $0 }
        )
    }

    var gamma: Binding<Double> {
        Binding(
            get: { self.colorAdjustments.gamma },
            set: { self.colorAdjustments.gamma = $0 }
        )
    }

    var saturation: Binding<Double> {
        Binding(
            get: { self.colorAdjustments.saturation },
            set: { self.colorAdjustments.saturation = $0 }
        )
    }
    
    func resetColorAdjustments() {
        colorAdjustments = .default
    }

    func resetWatermark() {
        watermarkConfig = .default
    }
    
    func resetCrop() {
        cropRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        cropTrackerPivot = CropTrackerTarget.defaultPivot
        cropTrackerEnabled = false
        cropDynamicKeyframes.removeAll()
        dynamicStartFrameIndex = nil
        dynamicAutoEndFrameIndex = nil
        isTrackingCrop = false
        activeTrackerJobID = nil
    }
    
    func addCurrentVideoToQueue() {
        guard let url = selectedFileURL else { return }
        
        let settings = ConversionSettings(
            format: selectedFormat,
            resolution: selectedResolution,
            quality: Int(quality),
            speedPercent: speedPercent,
            maxOutputSizeMB: maxOutputSizeMB,
            useGPU: useGPU,
            loopEnabled: loopEnabled,
            superCompression: superCompression,
            superCompressionGPU: superCompressionGPU,
            outputDirectory: outputDirectory,
            trimStart: trimSegments.map { $0.start }.min(),
            trimEnd: trimSegments.map { $0.end }.max(),
            cropEnabled: cropEnabled,
            cropRect: cropEnabled ? cropRect : nil,
            colorAdjustments: colorAdjustments,
            frameRateSettings: frameRateSettings,
            watermarkConfig: watermarkConfig.isEnabled ? watermarkConfig : nil
        )
        
        queueManager.addToQueue(url: url, settings: settings)
    }
    
    func setLanguageManager(_ lang: LanguageManager) {
        self.lang = lang
    }
    
    private var clearStatusTask: DispatchWorkItem?
    
    var canConvert: Bool {
        selectedFileURL != nil && !isProcessing
    }

    func selectFile(url: URL) {
        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        errorMessage = nil
        dynamicSpeedEnabled = false
        dynamicSpeedPoints.removeAll()
        cropTrackerPivot = CropTrackerTarget.defaultPivot
        cropDynamicKeyframes.removeAll()
        dynamicStartFrameIndex = nil
        dynamicAutoEndFrameIndex = nil
        isTrackingCrop = false
        activeTrackerJobID = nil
        watermarkConfig = .default
    }
    
    func clearSelection() {
        selectedFileURL = nil
        selectedFileName = nil
        videoInfo = nil
        liveCurrentTime = 0
        trimSegments.removeAll()
        activeTrimSegmentID = nil
        speedPercent = 100.0
        maxOutputSizeMBInput = ""
        dynamicSpeedEnabled = false
        dynamicSpeedPoints.removeAll()
        progress = 0
        statusMessage = ""
        errorMessage = nil
        errorLog = nil
        isProcessing = false
        cropEnabled = false
        cropDynamicEnabled = false
        cropTrackerEnabled = false
        cropTrackerPivot = CropTrackerTarget.defaultPivot
        cropDynamicKeyframes.removeAll()
        dynamicStartFrameIndex = nil
        dynamicAutoEndFrameIndex = nil
        loopEnabled = false
        stabilizationEnabled = false
        stabilizationLevel = .medium
        isTrackingCrop = false
        activeTrackerJobID = nil
        resetColorAdjustments()
        resetWatermark()
    }

    func checkYtDlpAvailability() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installed = YtDlpService.shared.isInstalled()
            DispatchQueue.main.async {
                self?.isYtDlpInstalled = installed
            }
        }
    }

    func startYtDlpDownload() {
        let input = ytDlpURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            ytDlpErrorMessage = lang?.t("ytdlp.error.empty") ?? "Enter a video URL"
            return
        }

        isYtDlpDownloading = true
        ytDlpDownloadProgress = 0
        ytDlpDownloadedFileURL = nil
        ytDlpErrorMessage = nil
        ytDlpErrorLog = nil

        YtDlpService.shared.download(
            videoURLString: input,
            progress: { [weak self] progress in
                self?.ytDlpDownloadProgress = progress
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isYtDlpDownloading = false
                switch result {
                case .success(let fileURL):
                    self.ytDlpDownloadProgress = 100
                    self.ytDlpDownloadedFileURL = fileURL
                    self.ytDlpErrorLog = nil
                case .failure(let error):
                    self.ytDlpErrorMessage = error.localizedDescription
                    self.ytDlpErrorLog = YtDlpService.shared.lastErrorLog
                }
            }
        )
    }

    func recordDynamicCrop(at time: Double, frameRate: Double?, cropRect: CGRect) {
        guard cropDynamicEnabled else { return }
        
        let resolvedFrameRate = max(1.0, frameRate ?? videoInfo?.frameRate ?? 30.0)
        let boundaryTolerance = 0.5 / resolvedFrameRate
        
        var capturedTime = max(0, time)
        
        if !trimSegments.isEmpty {
            let fallbackEnd = max(capturedTime, videoInfo?.duration ?? capturedTime)
            
            // Allow crop if the time falls inside of ANY segment
            var isInsideAny = false
            for seg in trimSegments {
                let lowerBound = seg.start
                let upperBound = seg.end
                if capturedTime >= (lowerBound - boundaryTolerance) && capturedTime <= (upperBound + boundaryTolerance) {
                    isInsideAny = true
                    capturedTime = min(max(capturedTime, lowerBound), upperBound)
                    break
                }
            }
            if !isInsideAny { return }
        }
        
        let frameIndex = max(0, Int(round(capturedTime * resolvedFrameRate)))
        let targetFrameIndex: Int
        if let existingFrameIndex = nearestDynamicKeyframe(to: frameIndex, toleranceFrames: 1) {
            targetFrameIndex = existingFrameIndex
        } else {
            targetFrameIndex = frameIndex
        }
        
        let storedTime: Double
        if let existing = cropDynamicKeyframes[targetFrameIndex] {
            storedTime = existing.time
        } else {
            storedTime = capturedTime
        }

        guard let cropValue = cropString(from: cropRect) else { return }
        cropDynamicKeyframes[targetFrameIndex] = CropDynamicKeyframe(
            time: storedTime,
            crop: cropValue
        )

    }

    private func nearestDynamicKeyframe(to frameIndex: Int, toleranceFrames: Int) -> Int? {
        guard !cropDynamicKeyframes.isEmpty else { return nil }
        
        var bestIndex: Int?
        var bestDistance = Int.max
        
        for existingIndex in cropDynamicKeyframes.keys {
            let distance = abs(existingIndex - frameIndex)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = existingIndex
            }
        }
        
        guard let bestIndex, bestDistance <= toleranceFrames else { return nil }
        return bestIndex
    }

    private func ensureStartDynamicKeyframe() {
        guard cropDynamicEnabled else { return }

        let fps = max(1.0, videoInfo?.frameRate ?? 30.0)
        let bounds = resolvedDynamicBoundsTimes()
        let startTime = bounds.start
        let startFrame = max(0, Int(round(startTime * fps)))

        if let previousStartFrame = dynamicStartFrameIndex, previousStartFrame != startFrame {
            cropDynamicKeyframes.removeValue(forKey: previousStartFrame)
        }

        upsertBoundaryDynamicKeyframe(frameIndex: startFrame, time: startTime)
        dynamicStartFrameIndex = startFrame

    }

    private func ensureEndDynamicKeyframeForConversion() {
        guard cropDynamicEnabled else { return }

        let fps = max(1.0, videoInfo?.frameRate ?? 30.0)
        let bounds = resolvedDynamicBoundsTimes()
        let endTime = bounds.end
        let endFrame = max(0, Int(round(endTime * fps)))

        if let previousEndFrame = dynamicAutoEndFrameIndex, previousEndFrame != endFrame {
            cropDynamicKeyframes.removeValue(forKey: previousEndFrame)
        }

        guard let cropValue = cropString(from: cropRect) else { return }
        cropDynamicKeyframes[endFrame] = CropDynamicKeyframe(
            time: endTime,
            crop: cropValue
        )
        dynamicAutoEndFrameIndex = endFrame

    }

    private func resolvedDynamicBoundsTimes() -> (start: Double, end: Double) {
        let sourceDuration = max(0.0, videoInfo?.duration ?? 0.0)
        let minStart = trimSegments.map { $0.start }.min()
        let maxEnd = trimSegments.map { $0.end }.max()
        let rawStart = max(0.0, minStart ?? 0.0)
        let defaultEnd = sourceDuration > 0 ? sourceDuration : rawStart
        let rawEnd = max(0.0, maxEnd ?? defaultEnd)

        return (start: min(rawStart, rawEnd), end: max(rawStart, rawEnd))
    }
    
    private func upsertBoundaryDynamicKeyframe(frameIndex: Int, time: Double) {
        if let existing = cropDynamicKeyframes[frameIndex] {
            cropDynamicKeyframes[frameIndex] = CropDynamicKeyframe(
                time: time,
                crop: existing.crop
            )
            return
        }

        guard let cropValue = cropString(from: cropRect) else { return }
        cropDynamicKeyframes[frameIndex] = CropDynamicKeyframe(
            time: time,
            crop: cropValue
        )
    }

    private func captureDynamicCropAspectRatioIfNeeded() {
        let width = max(0.0001, cropRect.width)
        let height = max(0.0001, cropRect.height)
        cropDynamicLockedAspectRatio = width / height
    }

    private func cropString(from normalizedRect: CGRect) -> String? {
        guard let videoSize = videoInfo?.videoSize else { return nil }
        let rect = clampNormalizedRect(normalizedRect)
        let width = abs(videoSize.width)
        let height = abs(videoSize.height)

        let x = Int(rect.origin.x * width)
        let y = Int(rect.origin.y * height)
        let w = Int(rect.size.width * width)
        let h = Int(rect.size.height * height)
        return "\(x):\(y):\(w):\(h)"
    }

    private func clampNormalizedRect(_ rect: CGRect) -> CGRect {
        var normalized = rect
        normalized.origin.x = max(0, min(1, normalized.origin.x))
        normalized.origin.y = max(0, min(1, normalized.origin.y))
        normalized.size.width = max(0.0001, min(1 - normalized.origin.x, normalized.size.width))
        normalized.size.height = max(0.0001, min(1 - normalized.origin.y, normalized.size.height))
        return normalized
    }

    var dynamicSpeedPointsSorted: [SpeedMapPoint] {
        dynamicSpeedPoints.sorted { $0.time < $1.time }
    }

    func resolvedDynamicSpeedBoundsTimes() -> (start: Double, end: Double) {
        let sourceDuration = max(0.0, videoInfo?.duration ?? 0.0)
        let minStart = trimSegments.map { $0.start }.min()
        let maxEnd = trimSegments.map { $0.end }.max()
        let rawStart = max(0.0, minStart ?? 0.0)
        let defaultEnd: Double
        if let maxEnd {
            defaultEnd = max(0.0, maxEnd)
        } else if sourceDuration > 0 {
            defaultEnd = sourceDuration
        } else {
            defaultEnd = max(rawStart, liveCurrentTime)
        }
        let rawEnd = max(0.0, maxEnd ?? defaultEnd)
        return (start: min(rawStart, rawEnd), end: max(rawStart, rawEnd))
    }

    func upsertDynamicSpeedPoint(at time: Double, speedPercent: Double) {
        guard dynamicSpeedEnabled else { return }

        let bounds = resolvedDynamicSpeedBoundsTimes()
        guard bounds.end >= bounds.start else { return }

        let clampedTime = min(max(time, bounds.start), bounds.end)
        let clampedSpeedPercent = min(max(speedPercent, 1.0), 100.0)
        let speedFactor = clampedSpeedPercent / 100.0
        let point = SpeedMapPoint(time: clampedTime, speed: speedFactor)

        let tolerance = max(0.05, (bounds.end - bounds.start) / 200.0)
        if let existingIndex = nearestDynamicSpeedPointIndex(to: clampedTime, tolerance: tolerance) {
            dynamicSpeedPoints[existingIndex] = point
        } else {
            dynamicSpeedPoints.append(point)
        }

        dynamicSpeedPoints = normalizedDynamicSpeedPoints(
            dynamicSpeedPoints,
            bounds: bounds,
            includeBoundaries: true
        )
    }

    func updateDynamicSpeedPoint(time: Double, speedPercent: Double) {
        guard dynamicSpeedEnabled else { return }

        let bounds = resolvedDynamicSpeedBoundsTimes()
        guard bounds.end >= bounds.start else { return }

        let clampedSpeedPercent = min(max(speedPercent, 1.0), 100.0)
        let speedFactor = clampedSpeedPercent / 100.0
        let tolerance = max(0.05, (bounds.end - bounds.start) / 200.0)

        guard let index = nearestDynamicSpeedPointIndex(to: time, tolerance: tolerance) else {
            upsertDynamicSpeedPoint(at: time, speedPercent: speedPercent)
            return
        }

        let current = dynamicSpeedPoints[index]
        dynamicSpeedPoints[index] = SpeedMapPoint(time: current.time, speed: speedFactor)
        dynamicSpeedPoints = normalizedDynamicSpeedPoints(
            dynamicSpeedPoints,
            bounds: bounds,
            includeBoundaries: true
        )
    }

    func resetDynamicSpeedPoints() {
        dynamicSpeedPoints.removeAll()
        if dynamicSpeedEnabled {
            ensureDynamicSpeedBoundaryPoints()
        }
    }

    func deleteDynamicSpeedPoint(near time: Double) {
        guard !dynamicSpeedPoints.isEmpty else { return }

        let bounds = resolvedDynamicSpeedBoundsTimes()
        let tolerance = max(0.05, (bounds.end - bounds.start) / 200.0)
        guard let index = nearestDynamicSpeedPointIndex(to: time, tolerance: tolerance) else { return }
        dynamicSpeedPoints.remove(at: index)
        dynamicSpeedPoints = normalizedDynamicSpeedPoints(
            dynamicSpeedPoints,
            bounds: bounds,
            includeBoundaries: true
        )
    }

    private func nearestDynamicSpeedPointIndex(to time: Double, tolerance: Double) -> Int? {
        guard !dynamicSpeedPoints.isEmpty else { return nil }

        var bestIndex: Int?
        var bestDistance = Double.greatestFiniteMagnitude

        for (index, point) in dynamicSpeedPoints.enumerated() {
            let distance = abs(point.time - time)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        guard let bestIndex, bestDistance <= tolerance else { return nil }
        return bestIndex
    }

    private func ensureDynamicSpeedBoundaryPoints() {
        let bounds = resolvedDynamicSpeedBoundsTimes()
        dynamicSpeedPoints = normalizedDynamicSpeedPoints(
            dynamicSpeedPoints,
            bounds: bounds,
            includeBoundaries: true
        )
    }

    private func normalizedDynamicSpeedPoints(
        _ points: [SpeedMapPoint],
        bounds: (start: Double, end: Double),
        includeBoundaries: Bool
    ) -> [SpeedMapPoint] {
        guard bounds.end >= bounds.start else { return [] }

        let epsilon = 0.000001
        let normalized = points
            .filter { point in
                point.time.isFinite && point.speed.isFinite &&
                point.time >= (bounds.start - epsilon) &&
                point.time <= (bounds.end + epsilon)
            }
            .map { point in
                SpeedMapPoint(
                    time: min(max(point.time, bounds.start), bounds.end),
                    speed: min(max(point.speed, 0.01), 1.0)
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.time - rhs.time) < epsilon {
                    return lhs.speed < rhs.speed
                }
                return lhs.time < rhs.time
            }

        if normalized.isEmpty, includeBoundaries {
            if bounds.end > bounds.start {
                return [
                    SpeedMapPoint(time: bounds.start, speed: 1.0),
                    SpeedMapPoint(time: bounds.end, speed: 1.0)
                ]
            }
            return [SpeedMapPoint(time: bounds.start, speed: 1.0)]
        }

        var deduped: [SpeedMapPoint] = []
        deduped.reserveCapacity(normalized.count)
        for point in normalized {
            if let last = deduped.last, abs(last.time - point.time) < epsilon {
                deduped[deduped.count - 1] = point
            } else {
                deduped.append(point)
            }
        }

        guard includeBoundaries else { return deduped }
        guard !deduped.isEmpty else { return [] }

        if bounds.end > bounds.start {
            if let first = deduped.first, first.time > (bounds.start + epsilon) {
                deduped.insert(
                    SpeedMapPoint(time: bounds.start, speed: first.speed),
                    at: 0
                )
            } else if let first = deduped.first, abs(first.time - bounds.start) >= epsilon {
                deduped[0] = SpeedMapPoint(time: bounds.start, speed: first.speed)
            }

            if let last = deduped.last, last.time < (bounds.end - epsilon) {
                deduped.append(SpeedMapPoint(time: bounds.end, speed: last.speed))
            } else if let last = deduped.last, abs(last.time - bounds.end) >= epsilon {
                deduped[deduped.count - 1] = SpeedMapPoint(time: bounds.end, speed: last.speed)
            }
        } else if let first = deduped.first {
            deduped = [SpeedMapPoint(time: bounds.start, speed: first.speed)]
        }

        return deduped
    }

    func persistOutputDirectory() {
        storedOutputDirectory = outputDirectory.rawValue
    }
    
    func startConversion() {
        guard let inputURL = selectedFileURL else {
            errorMessage = lang?.t("error.no_file_selected") ?? "No file selected"
            return
        }

        prepareConversionState()

        if cropEnabled && cropTrackerEnabled {
            runTrackerAndConvert(inputURL: inputURL)
            return
        }

        continueConversion(using: inputURL)
    }

    var maxOutputSizeMB: Int? {
        let trimmed = maxOutputSizeMBInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func prepareConversionState() {
        isProcessing = true
        progress = 0
        statusMessage = lang?.t("status.preparing_conversion") ?? "Preparing conversion..."
        errorMessage = nil
        errorLog = nil
    }

    private func runTrackerAndConvert(inputURL: URL) {
        isTrackingCrop = true
        statusMessage = lang?.t("status.tracking_crop") ?? "Tracking selected area..."
        let jobID = UUID()
        activeTrackerJobID = jobID

        let initialRect = cropRect
        let trackerPivot = cropTrackerPivot
        let trimStartValue = trimSegments.map { $0.start }.min()
        let trimEndValue = trimSegments.map { $0.end }.max()
        let info = videoInfo

        Task(priority: .userInitiated) { [weak self] in
            do {
                let trackedKeyframes = try await CropTrackerService.track(
                    inputURL: inputURL,
                    initialCropRect: initialRect,
                    trackerPivot: trackerPivot,
                    trimStart: trimStartValue,
                    trimEnd: trimEndValue,
                    videoInfo: info
                )

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeTrackerJobID == jobID, self.isProcessing else { return }
                    self.activeTrackerJobID = nil
                    self.isTrackingCrop = false
                    self.cropDynamicEnabled = true
                    self.applyTrackedKeyframes(trackedKeyframes)
                    self.continueConversion(using: inputURL)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeTrackerJobID == jobID else { return }
                    self.activeTrackerJobID = nil
                    self.isTrackingCrop = false
                    self.isProcessing = false
                    self.statusMessage = self.lang?.t("status.conversion_error") ?? "Conversion error"
                    self.errorMessage = self.lang?.t("error.tracker_failed") ?? "Unable to track selected area"
                    self.errorLog = error.localizedDescription
                }
            }
        }
    }

    private func continueConversion(using inputURL: URL) {
        activeTrackerJobID = nil

        if cropDynamicEnabled && (!cropTrackerEnabled || cropDynamicKeyframes.isEmpty) {
            ensureStartDynamicKeyframe()
            ensureEndDynamicKeyframeForConversion()
        }
        if dynamicSpeedEnabled {
            ensureDynamicSpeedBoundaryPoints()
        }

        // Crear ruta de salida
        let outputDir = outputDirectory.resolveURL()
        let outputURL = OutputFileNameGenerator.nextAvailableOutputURL(
            inputURL: inputURL,
            outputDirectory: outputDir,
            format: selectedFormat
        )
        self.outputFileURL = outputURL
        
        print("🔹 FFmpeg TRIM SEGMENTS: \(trimSegments.count)")

        let request = FFmpegConversionRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            format: selectedFormat,
            resolution: selectedResolution,
            quality: Int(quality),
            speedPercent: speedPercent,
            maxOutputSizeMB: maxOutputSizeMB,
            dynamicSpeedEnabled: dynamicSpeedEnabled,
            dynamicSpeedPoints: dynamicSpeedPointsSorted,
            useGPU: useGPU,
            stabilizationLevel: stabilizationEnabled ? stabilizationLevel : nil,
            loopEnabled: loopEnabled,
            superCompression: superCompression,
            superCompressionGPU: superCompressionGPU,
            trimSegments: trimSegments,
            videoInfo: videoInfo,
            cropEnable: cropEnabled,
            cropDynamicEnabled: cropDynamicEnabled,
            cropDynamicKeyframes: Array(cropDynamicKeyframes.values),
            cropRec: cropRect,
            colorAdjustments: colorAdjustments,
            frameRateSettings: frameRateSettings,
            watermarkConfig: watermarkConfig.isEnabled ? watermarkConfig : nil,
            progressCallback: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.progress = progress
                    self?.updateStatusMessage(progress: progress)
                }
            },
            completionCallback: { [weak self] result in
                DispatchQueue.main.async {
                    self?.handleConversionResult(result)
                }
            }
        )
        
        FFmpegConverter.shared.convert(request)
    }

    private func applyTrackedKeyframes(_ keyframes: [CropDynamicKeyframe]) {
        let fps = max(1.0, videoInfo?.frameRate ?? 30.0)
        var mapped: [Int: CropDynamicKeyframe] = [:]

        for keyframe in keyframes {
            let index = max(0, Int(round(keyframe.time * fps)))
            mapped[index] = keyframe
        }

        cropDynamicKeyframes = mapped
        dynamicStartFrameIndex = mapped.keys.min()
        dynamicAutoEndFrameIndex = mapped.keys.max()
    }

    
    func stopConversion() {
        FFmpegConverter.shared.cancel()
        isProcessing = false
        isTrackingCrop = false
        activeTrackerJobID = nil
        statusMessage = lang?.t("status.conversion_cancelled") ?? "Conversion cancelled"
    }

    private func updateStatusMessage(progress: Double) {
        let time = formatTime(secondsElapsed: progress * 100.0 / estimatedDuration)
        statusMessage = "\(lang?.t("status.processing_progress_time") ?? "Processing") \(Int(progress))% - \(time)"
    }
    
    private func handleConversionResult(_ result: Result<URL, FFmpegError>) {
        switch result {
        case .success(let outputURL):
            isProcessing = false
            isTrackingCrop = false
            progress = 100
            statusMessage = lang?.t("status.conversion_completed") ?? "Conversion completed"
            
            clearStatusTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                
                // Solo borrar si NO volvió a iniciar otra conversión
                if self.isProcessing == false {
                    self.statusMessage = ""
                    self.progress = 0
                }
            }
                
            clearStatusTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
            openInFinder(outputURL)
            
        case .failure(let error):
            isProcessing = false
            isTrackingCrop = false
            errorMessage = error.errorDescription
            errorLog = FFmpegConverter.shared.lastErrorLog
            statusMessage = lang?.t("status.conversion_error") ?? "Conversion error"
        }
    }
    
    private func openInFinder(_ fileURL: URL) {
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }
    
    private func formatTime(secondsElapsed: Double) -> String {
        let hours = Int(secondsElapsed / 3600)
        let minutes = Int((secondsElapsed / 60).truncatingRemainder(dividingBy: 60))
        let seconds = Int(secondsElapsed.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private var estimatedDuration: Double {
        // Esto se podrá mejorar obteniendo la duración real del video
        return 300 // 5 minutos por defecto
    }
    
    private var outputFileURL: URL?
    
    func checkForUpdates() async {
        do {
            let latest = try await fetchLatestInfo()
            let currentVersion = getCurrentVersion()
            
            if isNewerVersion(latest.version, than: currentVersion) {
                await MainActor.run {
                    self.hasUpdateAvailable = true
                    self.latestDownloadURL = latest.downloads?.macosUniversal.url
                }
            } else {
                await MainActor.run {
                    self.hasUpdateAvailable = false
                }
            }
        } catch {
            print("Error checking updates: \(error)")
        }
    }
    
    private func getCurrentVersion() -> String {
        Bundle.main.appVersion
    }
    
    private func fetchLatestInfo() async throws -> LatestInfo {
        guard let url = URL(string: "https://raw.githubusercontent.com/argorar/LazyConverter/main/latest.json") else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(LatestInfo.self, from: data)
    }

    
    private func isNewerVersion(_ remote: String, than current: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        for (i, remoteVer) in remoteComponents.enumerated() where i < currentComponents.count {
            if remoteVer > currentComponents[i] { return true }
            if remoteVer < currentComponents[i] { return false }
        }
        return remoteComponents.count > currentComponents.count
    }
    
    @MainActor
    func openUpdateDialog() {
        guard hasUpdateAvailable else { return }
        self.showUpdateDialog = true
    }
}
