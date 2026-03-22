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
    @State private var showYtDlpErrorLog = false
    @State private var isHoveringYtDlp = false
    
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
                VStack(spacing: 12) {
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
                    .frame(maxWidth: .infinity, minHeight: 280)
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

                    if viewModel.isYtDlpInstalled {
                        ytDlpDownloadSection
                    }
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

    @ViewBuilder
    private var ytDlpDownloadSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text(lang.t("ytdlp.title"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                Text(lang.t("ytdlp.subtitle"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                Text(lang.t("ytdlp.hint"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.accentColor)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField(lang.t("ytdlp.placeholder"), text: $viewModel.ytDlpURLInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isYtDlpDownloading)

                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button(lang.t("ytdlp.download")) {
                            viewModel.startYtDlpDownload()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isYtDlpDownloading || viewModel.ytDlpURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }

                    if viewModel.isYtDlpDownloading {
                        HStack(spacing: 8) {
                            ProgressView(value: viewModel.ytDlpDownloadProgress, total: 100)
                                .frame(maxWidth: .infinity)
                            Text("\(Int(viewModel.ytDlpDownloadProgress))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let error = viewModel.ytDlpErrorMessage, !error.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        Spacer()
                        if let log = viewModel.ytDlpErrorLog, !log.isEmpty {
                            Button(lang.t("error.view_log")) {
                                showYtDlpErrorLog = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                        }
                    }
                }

                if let downloadedURL = viewModel.ytDlpDownloadedFileURL {
                    HStack(spacing: 8) {
                        Button(lang.t("ytdlp.play")) {
                            NSWorkspace.shared.open(downloadedURL)
                        }
                        .buttonStyle(.bordered)

                        Button(lang.t("ytdlp.load")) {
                            handleSingleFile(downloadedURL)
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }
                }
            }
            .frame(maxWidth: 560)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8]),
                    antialiased: true
                )
                .foregroundColor(isHoveringYtDlp ? .accentColor : .secondary)
        )
        .onHover { hovering in
            isHoveringYtDlp = hovering
        }
        .sheet(isPresented: $showYtDlpErrorLog) {
            VStack(alignment: .leading, spacing: 12) {
                Text(lang.t("error.log_title"))
                    .font(.system(size: 14, weight: .semibold))
                ScrollView {
                    Text(viewModel.ytDlpErrorLog ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)

                HStack {
                    Spacer()
                    Button(lang.t("error.log_close")) {
                        showYtDlpErrorLog = false
                    }
                }
            }
            .padding(16)
            .frame(minWidth: 520, minHeight: 300)
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
            maxOutputSizeMB: viewModel.maxOutputSizeMB,
            useGPU: viewModel.useGPU,
            loopEnabled: viewModel.loopEnabled,
            outputDirectory: viewModel.outputDirectory,
            trimStart: viewModel.trimStart,
            trimEnd: viewModel.trimEnd,
            cropEnabled: viewModel.cropEnabled,
            cropRect: viewModel.cropEnabled ? viewModel.cropRect : nil,
            colorAdjustments: viewModel.colorAdjustments,
            frameRateSettings: viewModel.frameRateSettings,
            watermarkConfig: viewModel.watermarkConfig.isEnabled ? viewModel.watermarkConfig : nil
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
