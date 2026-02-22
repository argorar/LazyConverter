//
//  VideoPreviewPanel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//


import SwiftUI
import AVKit
import AVFoundation

struct VideoPreviewPanel: View {
    @ObservedObject var viewModel: VideoConversionViewModel
    @EnvironmentObject var lang: LanguageManager
    @Binding var player: AVPlayer?
    let videoInfo: VideoInfo?
    @State private var timeObserver: Any?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timer: Timer? = nil
    @State private var isSeekingToTrimBound = false
    
    var body: some View {
        VStack(spacing: 12) {
            
            // Player
            if let unwrappedPlayer = player, unwrappedPlayer.currentItem != nil {
                VideoPlayer(player: unwrappedPlayer)
                    .frame(height: 500)
                    .cornerRadius(8)
                    .overlay {
                    if viewModel.cropEnabled {
                        GeometryReader { geo in
                            CropOverlayView(cropRect: $viewModel.cropRect,
                                videoSize: CGSize(width: Double(abs(videoInfo?.videoSize.width ?? 200)), height: Double(abs(videoInfo?.videoSize.height ?? 500))),
                                playerFrame: CGRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height),
                                showTrackerTarget: viewModel.cropTrackerEnabled,
                                onCropDragged: { cropRect in
                                    let playerTime = player?.currentTime().seconds
                                    let currentFrameTime: Double
                                    if let playerTime, playerTime.isFinite {
                                        currentFrameTime = playerTime
                                    } else {
                                        currentFrameTime = currentTime
                                    }
                                    viewModel.recordDynamicCrop(
                                        at: max(0, currentFrameTime),
                                        frameRate: videoInfo?.frameRate,
                                        cropRect: cropRect
                                    )
                                }
                            )
                        }
                    }
                }
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    Text(lang.t("player.waiting"))
                }
                .frame(height: 300)
                .cornerRadius(8)
            }
            
            // BOTÓN + KEYFRAME LIVE
            HStack(spacing: 12) {
                // KEYFRAME EN VIVO (Actualiza cada 0.1s)
                HStack(spacing: 4) {
                    Text(lang.t("frame.current"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(formatTime(currentTime))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.accentColor)
                    
                    if duration > 0 {
                        Text("/ \(formatTime(duration))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("\(Int((currentTime/duration)*100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentColor.opacity(0.8))
                    }
                }
            }
            
            if let info = videoInfo {
                VideoPreviewView(videoInfo: info)
            }
            
        }
        .cornerRadius(12)
        .onAppear {
            startLiveTimer()
            setupPlayerObserver()
            applyVideoFilters()
        }
        .onDisappear {
            stopLiveTimer()
            removePlayerObserver()
            player?.pause()
            player = nil
        }
        .onChange(of: player) { oldValue, newValue in
            updateDuration(newValue)
            removePlayerObserver()
            setupPlayerObserver()
        }
        .onChange(of: viewModel.speedPercent) { oldValue, newValue in
            updatePlayerRate(newValue, allowStartPlayback: false)
        }
        .onChange(of: viewModel.colorAdjustments){ oldValue, newValue in
            applyVideoFilters()
        }
        .onChange(of: viewModel.trimStart) { oldValue, newValue in
            if let player = player {
                enforceTrimBoundsIfNeeded(for: player)
            }
        }
        .onChange(of: viewModel.trimEnd) { oldValue, newValue in
            if let player = player {
                enforceTrimBoundsIfNeeded(for: player)
            }
        }
        .onChange(of: viewModel.cropDynamicEnabled) { oldValue, newValue in
            guard newValue, let player = player else { return }
            let start = max(0, viewModel.trimStart ?? 0)
            seekToTrimBound(player: player, seconds: start, keepPlaying: false)
        }
    }
    
    private func closePlayer(_ fileURL: String?) {
        if fileURL == nil {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayerObserver() {
        guard let player = player else { return }

        // Observer cada 0.1s en el AVPlayer (no en AVPlayerItem)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: DispatchQueue.main
        ) { time in
            onPlayerTimeChanged(time)
        }
    }
    
    private func removePlayerObserver() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func onPlayerTimeChanged(_ time: CMTime) {
            guard let player = player else { return }
            let rate = player.rate
            
            // Detectar PLAY (rate > 0)
            if rate > 0.01 {
                enforceTrimBoundsIfNeeded(for: player)
                updatePlayerRate(viewModel.speedPercent)
            }
        }
    
    
    private func updatePlayerRate(_ speedPercent: Double, allowStartPlayback: Bool = true) {
        guard let player = player else { return }
        
        let isPlaying = player.rate > 0.01
        if !allowStartPlayback && !isPlaying {
            return
        }
        
        let rate = Float(speedPercent / 100.0)  // 50% = 0.5x, 200% = 2.0x
        player.rate = rate
    }
    
    private func startLiveTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateLiveTime()
        }
    }
    
    private func stopLiveTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateLiveTime() {
        if let player = player {
            enforceTrimBoundsIfNeeded(for: player)
            if isSeekingToTrimBound { return }
            
            let newTime = player.currentTime().seconds
            if !newTime.isNaN && newTime >= 0 {
                currentTime = newTime
                viewModel.liveCurrentTime = newTime
            }
        }
    }
    
    private func enforceTrimBoundsIfNeeded(for player: AVPlayer) {
        guard !isSeekingToTrimBound else { return }
        
        let currentSeconds = player.currentTime().seconds
        guard !currentSeconds.isNaN && !currentSeconds.isInfinite else { return }
        
        let tolerance = 0.02
        let start = viewModel.trimStart
        let end = viewModel.trimEnd
        
        if let start, currentSeconds < (start - tolerance) {
            seekToTrimBound(player: player, seconds: start, keepPlaying: player.rate > 0.01)
            return
        }
        
        if let end, currentSeconds > (end + tolerance) {
            seekToTrimBound(player: player, seconds: end, keepPlaying: false)
        }
    }
    
    private func seekToTrimBound(player: AVPlayer, seconds: Double, keepPlaying: Bool) {
        isSeekingToTrimBound = true
        
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                self.currentTime = max(0, seconds)
                self.viewModel.liveCurrentTime = max(0, seconds)
                
                if keepPlaying {
                    self.updatePlayerRate(self.viewModel.speedPercent)
                } else {
                    player.pause()
                }
                
                self.isSeekingToTrimBound = false
            }
        }
    }


    
    private func updateDuration(_ player: AVPlayer?) {
        if let player = player, let duration = player.currentItem?.duration.seconds {
            self.duration = duration
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time * 100).truncatingRemainder(dividingBy: 100))
        return String(format: "%d:%02d.%02d", minutes, seconds, ms)
    }
    
    private func applyVideoFilters() {
        guard let player = player,
              let playerItem = player.currentItem else { return }
        
        let adjustments = viewModel.colorAdjustments
        
        // Solo aplicar si hay modificaciones
        if !adjustments.isModified {
            playerItem.videoComposition = nil
            return
        }

        let asset = playerItem.asset
        AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
            var outputImage = request.sourceImage

            let ciValues = adjustments.ciColorControlsValues

            // 1. Color controls (brightness, contrast, saturation)
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(outputImage, forKey: kCIInputImageKey)
                colorControls.setValue(ciValues.brightness, forKey: kCIInputBrightnessKey)
                colorControls.setValue(ciValues.contrast, forKey: kCIInputContrastKey)
                colorControls.setValue(ciValues.saturation, forKey: kCIInputSaturationKey)

                if let output = colorControls.outputImage {
                    outputImage = output
                }
            }

            // 2. Gamma adjustment
            if adjustments.gamma != 1.0 {
                if let gammaAdjust = CIFilter(name: "CIGammaAdjust") {
                    gammaAdjust.setValue(outputImage, forKey: kCIInputImageKey)
                    gammaAdjust.setValue(adjustments.ciGammaValue, forKey: "inputPower")

                    if let output = gammaAdjust.outputImage {
                        outputImage = output
                    }
                }
            }

            request.finish(with: outputImage, context: nil)
        }) { composition, error in
            // Assign on main thread to be safe with KVO/UI interactions
            DispatchQueue.main.async {
                if let composition = composition {
                    playerItem.videoComposition = composition
                } else {
                    // If composition failed, clear any previous composition
                    playerItem.videoComposition = nil
                }
            }
        }
    }
}
