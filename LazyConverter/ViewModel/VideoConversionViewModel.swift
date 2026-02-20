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
    @Published var useGPU: Bool = false
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var errorLog: String?
    @Published var speedPercent: Double = 100.0 // 0.0 - 200.0
    @Published var videoInfo: VideoInfo?
    @Published var cropEnabled: Bool = false
    @Published var cropDynamicEnabled: Bool = false {
        didSet {
            if cropDynamicEnabled == false {
                cropDynamicKeyframes.removeAll()
                dynamicStartFrameIndex = nil
                dynamicAutoEndFrameIndex = nil
            } else {
                ensureStartDynamicKeyframe()
            }
        }
    }
    @Published private(set) var cropDynamicKeyframes: [Int: CropDynamicKeyframe] = [:]
    @Published var cropRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) // valores en 0–1
    @Published var loopEnabled: Bool = false
    @Published var liveCurrentTime: Double = 0
    @Published var trimStart: Double? = nil {
        didSet {
            if cropDynamicEnabled {
                ensureStartDynamicKeyframe()
            }
        }
    }
    @Published var trimEnd: Double? = nil {
        didSet {
            if cropDynamicEnabled {
                ensureStartDynamicKeyframe()
            }
        }
    }
    @Published var showUpdateDialog = false
    @Published var latestDownloadURL: String? = nil
    @Published var hasUpdateAvailable = false
    @Published var colorAdjustments = ColorAdjustments.default
    @Published var queueManager = QueueManager()
    @Published var showQueueWindow = false
    @Published var frameRateSettings = FrameRateSettings()
    @Published var outputDirectory: OutputDirectory = .downloads
    private var dynamicStartFrameIndex: Int?
    private var dynamicAutoEndFrameIndex: Int?
    
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
    
    func resetCrop() {
        cropRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        cropDynamicKeyframes.removeAll()
        dynamicStartFrameIndex = nil
        dynamicAutoEndFrameIndex = nil
    }
    
    func addCurrentVideoToQueue() {
        guard let url = selectedFileURL else { return }
        
        let settings = ConversionSettings(
            format: selectedFormat,
            resolution: selectedResolution,
            quality: Int(quality),
            speedPercent: speedPercent,
            useGPU: useGPU,
            loopEnabled: loopEnabled,
            outputDirectory: outputDirectory,
            trimStart: trimStart,
            trimEnd: trimEnd,
            cropEnabled: cropEnabled,
            cropRect: cropEnabled ? cropRect : nil,
            colorAdjustments: colorAdjustments,
            frameRateSettings: frameRateSettings
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
        cropDynamicKeyframes.removeAll()
        dynamicStartFrameIndex = nil
        dynamicAutoEndFrameIndex = nil
    }
    
    func clearSelection() {
        selectedFileURL = nil
        selectedFileName = nil
        videoInfo = nil
        liveCurrentTime = 0
        trimStart = nil
        trimEnd = nil
        speedPercent = 100.0
        progress = 0
        statusMessage = ""
        errorMessage = nil
        errorLog = nil
        isProcessing = false
        cropEnabled = false
        cropDynamicEnabled = false
        cropDynamicKeyframes.removeAll()
        dynamicStartFrameIndex = nil
        dynamicAutoEndFrameIndex = nil
        loopEnabled = false
        resetColorAdjustments()
    }

    func recordDynamicCrop(at time: Double, frameRate: Double?, cropRect: CGRect) {
        guard cropDynamicEnabled else { return }
        
        let resolvedFrameRate = max(1.0, frameRate ?? videoInfo?.frameRate ?? 30.0)
        let boundaryTolerance = 0.5 / resolvedFrameRate
        
        let trimStartValue = trimStart
        let trimEndValue = trimEnd
        let hasTrim = trimStartValue != nil || trimEndValue != nil
        
        var capturedTime = max(0, time)
        
        if hasTrim {
            let fallbackEnd = max(capturedTime, videoInfo?.duration ?? capturedTime)
            let rawLowerBound = trimStartValue ?? 0.0
            let rawUpperBound = trimEndValue ?? fallbackEnd
            let lowerBound = min(rawLowerBound, rawUpperBound)
            let upperBound = max(rawLowerBound, rawUpperBound)
            
            if capturedTime < (lowerBound - boundaryTolerance) || capturedTime > (upperBound + boundaryTolerance) {

                return
            }
            
            capturedTime = min(max(capturedTime, lowerBound), upperBound)
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
        
        cropDynamicKeyframes[targetFrameIndex] = CropDynamicKeyframe(
            frameIndex: targetFrameIndex,
            time: storedTime,
            cropRect: cropRect
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

        cropDynamicKeyframes[endFrame] = CropDynamicKeyframe(
            frameIndex: endFrame,
            time: endTime,
            cropRect: cropRect
        )
        dynamicAutoEndFrameIndex = endFrame

    }

    private func resolvedDynamicBoundsTimes() -> (start: Double, end: Double) {
        let sourceDuration = max(0.0, videoInfo?.duration ?? 0.0)
        let rawStart = max(0.0, trimStart ?? 0.0)
        let defaultEnd = sourceDuration > 0 ? sourceDuration : rawStart
        let rawEnd = max(0.0, trimEnd ?? defaultEnd)

        return (start: min(rawStart, rawEnd), end: max(rawStart, rawEnd))
    }
    
    private func upsertBoundaryDynamicKeyframe(frameIndex: Int, time: Double) {
        if let existing = cropDynamicKeyframes[frameIndex] {
            cropDynamicKeyframes[frameIndex] = CropDynamicKeyframe(
                frameIndex: frameIndex,
                time: time,
                cropRect: existing.cropRect
            )
            return
        }
        
        cropDynamicKeyframes[frameIndex] = CropDynamicKeyframe(
            frameIndex: frameIndex,
            time: time,
            cropRect: cropRect
        )
    }

    func persistOutputDirectory() {
        storedOutputDirectory = outputDirectory.rawValue
    }
    
    func startConversion() {
        guard let inputURL = selectedFileURL else {
            errorMessage = lang?.t("error.no_file_selected") ?? "No file selected"
            return
        }

        if cropDynamicEnabled {
            ensureStartDynamicKeyframe()
            ensureEndDynamicKeyframeForConversion()
        }
        
        isProcessing = true
        progress = 0
        statusMessage = lang?.t("status.preparing_conversion") ?? "Preparing conversion..."
        errorMessage = nil
        errorLog = nil
        
        // Crear ruta de salida
        let outputDir = outputDirectory.resolveURL()
        let timestamp = Int(Date().timeIntervalSince1970)
    
        var extention = "mp4"
        switch selectedFormat {
        case .webm:
            extention = "webm"
        case .av1:
            extention = "mp4"
        default:
            extention = selectedFormat.rawValue
        }
        let outputFileName = "converted_\(timestamp).\(extention)"
        let outputURL = outputDir.appendingPathComponent(outputFileName)
        self.outputFileURL = outputURL
        
        let trimStartSeconds: Double? = trimStart
        let trimEndSeconds: Double? = trimEnd
        
        print("🔹 FFmpeg TRIM:")
        print("  📍 Start: \(trimStartSeconds != nil ? "\(trimStartSeconds!)s" : "NONE")")
        print("  🎯 End:   \(trimEndSeconds != nil ? "\(trimEndSeconds!)s" : "NONE")")

        let request = FFmpegConversionRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            format: selectedFormat,
            resolution: selectedResolution,
            quality: Int(quality),
            speedPercent: speedPercent,
            useGPU: useGPU,
            loopEnabled: loopEnabled,
            trimStart: trimStartSeconds,
            trimEnd: trimEndSeconds,
            videoInfo: videoInfo,
            cropEnable: cropEnabled,
            cropDynamicEnabled: cropDynamicEnabled,
            cropDynamicKeyframes: Array(cropDynamicKeyframes.values),
            cropRec: cropRect,
            colorAdjustments: colorAdjustments,
            frameRateSettings: frameRateSettings,
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

    
    func stopConversion() {
        FFmpegConverter.shared.cancel()
        isProcessing = false
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
