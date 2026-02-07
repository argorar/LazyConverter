//
//  VideoPanel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//


import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit

struct VideoPanel: View {
    @ObservedObject var viewModel: VideoConversionViewModel
    @EnvironmentObject var lang: LanguageManager
    @State private var isHovering = false
    @State private var videoInfo: VideoInfo?
    @State private var isAnalyzing = false
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack(spacing: 16) {
            // Drag & Drop zone O Preview
            if viewModel.selectedFileURL != nil {
                VideoPreviewPanel(viewModel: viewModel, player: $player, videoInfo: videoInfo)
                    .transition(.opacity.combined(with: .scale))
            } else if isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(lang.t("analyzing.video"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .background(Color(nsColor: .separatorColor).opacity(0.3))
                .cornerRadius(12)
            } else {
                // DRAG & DROP ZONE
                VStack(spacing: 16) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    VStack(spacing: 8) {
                        Text(lang.t("video.drag.title"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text(lang.t("video.drag.subtitle"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                        Text(lang.t("video.drag.multiple"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.accentColor)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [8]),
                            antialiased: true
                        )
                        .foregroundColor(isHovering ? .accentColor : .secondary)
                )
                .onHover { hovering in
                    isHovering = hovering
                }
                .onTapGesture {
                    selectFiles()
                }
                .dropDestination(for: URL.self) { urls, _ in
                    handleDroppedURLs(urls)
                    return !urls.isEmpty
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .task(id: viewModel.selectedFileURL) {
            await analyzeSelectedVideo()
        }
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .avi]
        panel.allowsMultipleSelection = true
        panel.message = lang.t("video.select.message")
        
        panel.begin { response in
            if response == .OK {
                let urls = panel.urls
                
                if urls.count == 1 {
                    // Un solo archivo → cargar en preview
                    handleSingleFile(urls[0])
                } else if urls.count > 1 {
                    // Múltiples archivos → agregar a cola
                    handleMultipleFiles(urls)
                }
            }
        }
    }
    
    private func handleDroppedURLs(_ urls: [URL]) {
        // Filtrar solo videos válidos
        let validExtensions = ["mov", "mp4", "avi", "m4v", "mkv", "webm"]
        let videoURLs = urls.filter { url in
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               [UTType.movie, .mpeg4Movie, .avi].contains(type) {
                return true
            }
            return validExtensions.contains(url.pathExtension.lowercased())
        }
        
        guard !videoURLs.isEmpty else { return }
        
        if videoURLs.count == 1 {
            // Un solo archivo → cargar en preview
            handleSingleFile(videoURLs[0])
        } else {
            // Múltiples archivos → agregar a cola
            handleMultipleFiles(videoURLs)
        }
    }
    
    private func handleSingleFile(_ url: URL) {
        self.player?.pause()
        self.player = nil
        viewModel.selectFile(url: url)
        self.player = AVPlayer(url: url)
    }
    
    private func handleMultipleFiles(_ urls: [URL]) {
        let settings = ConversionSettings(
            format: viewModel.selectedFormat,
            resolution: viewModel.selectedResolution,
            quality: Int(viewModel.quality),
            speedPercent: viewModel.speedPercent,
            useGPU: viewModel.useGPU,
            loopEnabled: viewModel.loopEnabled,
            trimStart: viewModel.trimStart,
            trimEnd: viewModel.trimEnd,
            cropEnabled: viewModel.cropEnabled,
            cropRect: viewModel.cropEnabled ? viewModel.cropRect : nil,
            colorAdjustments: viewModel.colorAdjustments,
            frameRateSettings: viewModel.frameRateSettings
        )
        
        viewModel.queueManager.addMultipleToQueue(urls: urls, settings: settings)
        
        // Mostrar ventana de cola automáticamente
        viewModel.showQueueWindow = true
        
        viewModel.statusMessage = String(format: lang.t("queue.added.multiple"), urls.count)
    }
    
    @MainActor
    private func analyzeSelectedVideo() async {
        guard let url = viewModel.selectedFileURL else {
            videoInfo = nil
            viewModel.videoInfo = nil
            return
        }
        
        isAnalyzing = true
        videoInfo = nil
        viewModel.videoInfo = nil
        
        Task {
            let info = await VideoAnalyzer.analyze(url)
            await MainActor.run {
                self.videoInfo = info
                self.viewModel.videoInfo = info
                self.isAnalyzing = false
            }
        }
    }
}
