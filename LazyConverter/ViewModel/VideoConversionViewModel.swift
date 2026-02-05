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
    
    @Published var selectedFileName: String?
    @Published var selectedFormat: VideoFormat = .mp4
    @Published var selectedResolution: VideoResolution = .original
    @Published var quality: Double = 18
    @Published var useGPU: Bool = false
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var speedPercent: Double = 100.0 // 0.0 - 200.0
    @Published var videoInfo: VideoInfo?
    @Published var cropEnabled: Bool = false
    @Published var cropRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) // valores en 0–1
    @Published var liveCurrentTime: Double = 0
    @Published var trimStart: Double? = nil
    @Published var trimEnd: Double? = nil
    @Published var showUpdateDialog = false
    @Published var latestDownloadURL: String? = nil
    @Published var colorAdjustments = ColorAdjustments.default
    @Published var queueManager = QueueManager()
    @Published var showQueueWindow = false
    @Published var frameRateSettings = FrameRateSettings()
    
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
    
    func addCurrentVideoToQueue() {
        guard let url = selectedFileURL else { return }
        
        let settings = ConversionSettings(
            format: selectedFormat,
            resolution: selectedResolution,
            quality: Int(quality),
            speedPercent: speedPercent,
            useGPU: useGPU,
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
        isProcessing = false
        cropEnabled = false
        resetColorAdjustments()
    }
    
    func startConversion() {
        guard let inputURL = selectedFileURL else {
            errorMessage = lang?.t("error.no_file_selected") ?? "No file selected"
            return
        }
        
        isProcessing = true
        progress = 0
        statusMessage = lang?.t("status.preparing_conversion") ?? "Preparing conversion..."
        errorMessage = nil
        
        // Crear ruta de salida
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
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
        let outputURL = tempDir.appendingPathComponent(outputFileName)
        self.outputFileURL = outputURL
        
        let trimStartSeconds: Double? = trimStart
        let trimEndSeconds: Double? = trimEnd
        
        print("🔹 FFmpeg TRIM:")
        print("  📍 Start: \(trimStartSeconds != nil ? "\(trimStartSeconds!)s" : "NONE")")
        print("  🎯 End:   \(trimEndSeconds != nil ? "\(trimEndSeconds!)s" : "NONE")")

        FFmpegConverter.shared.convert(
            inputURL: inputURL,
            outputURL: outputURL,
            format: selectedFormat,
            resolution: selectedResolution,
            quality: Int(quality),
            speedPercent: speedPercent,
            useGPU: useGPU,
            trimStart: trimStartSeconds,
            trimEnd: trimEndSeconds,
            videoInfo: videoInfo,
            cropEnable: cropEnabled,
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
        await MainActor.run {
            self.statusMessage = self.lang?.t("status.checking_updates") ?? "Checking for updates..."
        }
        
        do {
            let latest = try await fetchLatestInfo()
            let currentVersion = getCurrentVersion()
            
            if isNewerVersion(latest.version, than: currentVersion) {
                showUpdateAlert(latest: latest)
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
    private func showUpdateAlert(latest: LatestInfo) {
        self.showUpdateDialog = true
        self.latestDownloadURL = latest.downloads?.macosUniversal.url
    }
}

