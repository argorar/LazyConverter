//
//  VideoPreviewPanel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//


import SwiftUI
import AVFoundation
import AppKit

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
    @State private var isUserScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var isPlayerPlaying = false
    @State private var isPlayerMuted = false
    @State private var scrubPosition: Double = 0
    @State private var isLoadingAssetDuration = false
    @State private var keyEventMonitor: Any?
    @State private var scrollEventMonitor: Any?
    @State private var isHoveringSeekSlider = false
    @State private var isPointerDragScrubbing = false
    private let playerControlButtonSize: CGFloat = 28
    private let trimJumpButtonWidth: CGFloat = 84
    private let trimJumpButtonHeight: CGFloat = 28
    
    var body: some View {
        VStack(spacing: 12) {
            
            // Player
            if let unwrappedPlayer = player, unwrappedPlayer.currentItem != nil {
                PlayerSurfaceView(player: unwrappedPlayer)
                    .frame(height: 500)
                    .cornerRadius(8)
                    .overlay {
                    if viewModel.cropEnabled {
                        GeometryReader { geo in
                            CropOverlayView(cropRect: $viewModel.cropRect,
                                trackerPivot: $viewModel.cropTrackerPivot,
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

            if player?.currentItem != nil {
                HStack(spacing: 8) {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlayerPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(width: playerControlButtonSize, height: playerControlButtonSize)

                    Slider(
                        value: $scrubPosition,
                        in: sliderRange,
                        onEditingChanged: handleScrubbingChanged
                    )
                    .tint(.accentColor)
                    .onHover { hovering in
                        isHoveringSeekSlider = hovering
                    }
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard isHoveringSeekSlider || isPointerDragScrubbing else { return }
                                            if !isPointerDragScrubbing {
                                                isPointerDragScrubbing = true
                                                startScrubbingSession()
                                            }

                                            let width = max(1.0, geo.size.width)
                                            let clampedX = min(max(0.0, value.location.x), width)
                                            let progress = Double(clampedX / width)
                                            let range = sliderRange
                                            scrubPosition = range.lowerBound + (range.upperBound - range.lowerBound) * progress
                                        }
                                        .onEnded { _ in
                                            guard isPointerDragScrubbing else { return }
                                            isPointerDragScrubbing = false
                                            finishScrubbingSession()
                                        }
                                )
                        }
                    }

                    Button(action: toggleMute) {
                        Image(systemName: muteButtonIconName)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: playerControlButtonSize, height: playerControlButtonSize)
                    .disabled(!hasAudioInCurrentVideo)

                    Text(formatTime(scrubPosition))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
            
            HStack(spacing: 12) {
                if let trimStart = viewModel.trimStart {
                    Button(lang.t("button.start")) {
                        guard let player = player else { return }
                        seekToTrimBound(player: player, seconds: trimStart, keepPlaying: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: trimJumpButtonWidth, height: trimJumpButtonHeight)
                }

                if let trimEnd = viewModel.trimEnd {
                    Button(lang.t("button.end")) {
                        guard let player = player else { return }
                        seekToTrimBound(player: player, seconds: trimEnd, keepPlaying: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: trimJumpButtonWidth, height: trimJumpButtonHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            if let info = videoInfo {
                VideoPreviewView(videoInfo: info)
            }
            
        }
        .cornerRadius(12)
        .onAppear {
            startLiveTimer()
            updateDuration(player)
            setupPlayerObserver()
            applyVideoFilters()
            isPlayerMuted = player?.isMuted ?? false
            syncMuteButtonState()
            installKeyboardMonitor()
            installScrollMonitor()
        }
        .onDisappear {
            stopLiveTimer()
            removePlayerObserver()
            removeKeyboardMonitor()
            removeScrollMonitor()
            player?.pause()
            player = nil
        }
        .onChange(of: player) { oldValue, newValue in
            updateDuration(newValue)
            isPlayerPlaying = false
            isPlayerMuted = newValue?.isMuted ?? false
            syncMuteButtonState()
            removePlayerObserver()
            setupPlayerObserver()
        }
        .onChange(of: videoInfo?.duration) { _, _ in
            updateDuration(player)
        }
        .onChange(of: videoInfo?.hasAudio) { _, _ in
            syncMuteButtonState()
        }
        .onChange(of: viewModel.speedPercent) { oldValue, newValue in
            updatePlayerRate(newValue, allowStartPlayback: false)
        }
        .onChange(of: scrubPosition) { _, newValue in
            handleScrubPositionChanged(newValue)
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

    private var hasAudioInCurrentVideo: Bool {
        videoInfo?.hasAudio ?? true
    }

    private var muteButtonIconName: String {
        if !hasAudioInCurrentVideo {
            return "speaker.slash.fill"
        }
        return isPlayerMuted ? "speaker.slash.fill" : "speaker.2.fill"
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    private func installScrollMonitor() {
        removeScrollMonitor()
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleScrollWheel(event)
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
            scrollEventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard player?.currentItem != nil else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) {
            return event
        }

        switch event.keyCode {
        case 49: // Space
            if modifiers.contains(.shift) {
                return event
            }
            togglePlayback()
            return nil
        case 123: // Left arrow
            if modifiers.contains(.shift) {
                return event
            }
            stepByFrame(direction: -1)
            return nil
        case 124: // Right arrow
            if modifiers.contains(.shift) {
                return event
            }
            stepByFrame(direction: 1)
            return nil
        default:
            return event
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard isHoveringSeekSlider, let player else { return event }
        guard player.currentItem != nil else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) {
            return event
        }

        let dominantDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY

        if abs(dominantDelta) < 0.0001 {
            return nil
        }

        let fps = max(1.0, videoInfo?.frameRate ?? 30.0)
        let frameStep = 1.0 / fps
        let sensitivity = event.hasPreciseScrollingDeltas ? 2.0 : 4.0
        let deltaSeconds = -Double(dominantDelta) * frameStep * sensitivity
        let targetSeconds = boundedPlaybackTime(scrubPosition + deltaSeconds)

        player.pause()
        isPlayerPlaying = false

        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        scrubPosition = targetSeconds
        currentTime = targetSeconds
        viewModel.liveCurrentTime = targetSeconds

        // Consume event so parent ScrollView does not move while seeking.
        return nil
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
        isPlayerPlaying = rate > 0.01
        
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
            isPlayerPlaying = player.rate > 0.01
            if duration <= 0 {
                updateDuration(player)
            }
            
            let newTime = player.currentTime().seconds
            if !newTime.isNaN && newTime >= 0 {
                currentTime = newTime
                viewModel.liveCurrentTime = newTime
                if !isUserScrubbing {
                    scrubPosition = boundedPlaybackTime(newTime)
                }
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
        let boundedSeconds = boundedPlaybackTime(seconds)
        let target = CMTime(seconds: boundedSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                self.currentTime = boundedSeconds
                self.scrubPosition = boundedSeconds
                self.viewModel.liveCurrentTime = boundedSeconds
                
                if keepPlaying {
                    self.updatePlayerRate(self.viewModel.speedPercent)
                    self.isPlayerPlaying = true
                } else {
                    player.pause()
                    self.isPlayerPlaying = false
                }
                
                self.isSeekingToTrimBound = false
            }
        }
    }

    private func togglePlayback() {
        guard let player = player else { return }

        if player.rate > 0.01 {
            player.pause()
            isPlayerPlaying = false
            return
        }

        let currentSeconds = player.currentTime().seconds
        let bounds = playbackBounds
        if currentSeconds.isFinite && currentSeconds >= (bounds.upper - 0.02) {
            seekToTrimBound(player: player, seconds: bounds.lower, keepPlaying: true)
            return
        }

        updatePlayerRate(viewModel.speedPercent)
        isPlayerPlaying = true
    }

    private func toggleMute() {
        guard let player = player else { return }
        guard hasAudioInCurrentVideo else {
            player.isMuted = true
            isPlayerMuted = true
            return
        }
        player.isMuted.toggle()
        isPlayerMuted = player.isMuted
    }

    private func syncMuteButtonState() {
        guard let player = player else { return }
        if hasAudioInCurrentVideo {
            isPlayerMuted = player.isMuted
            return
        }
        player.isMuted = true
        isPlayerMuted = true
    }

    private func stepByFrame(direction: Int) {
        guard let player = player else { return }
        let fps = max(1.0, videoInfo?.frameRate ?? 30.0)
        let frameStep = 1.0 / fps
        let sourceTime = player.currentTime().seconds
        let base = sourceTime.isFinite ? sourceTime : currentTime
        seekToTrimBound(player: player, seconds: base + (frameStep * Double(direction)), keepPlaying: false)
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        if editing {
            startScrubbingSession()
            return
        }

        guard !isPointerDragScrubbing else { return }
        finishScrubbingSession()
    }

    private func handleScrubPositionChanged(_ newValue: Double) {
        guard isUserScrubbing, let player = player else { return }
        let bounded = boundedPlaybackTime(newValue)
        let target = CMTime(seconds: bounded, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = bounded
        viewModel.liveCurrentTime = bounded
    }

    private func startScrubbingSession() {
        guard let player = player else { return }
        guard !isUserScrubbing else { return }

        isUserScrubbing = true
        wasPlayingBeforeScrub = player.rate > 0.01
        player.pause()
        isPlayerPlaying = false
    }

    private func finishScrubbingSession() {
        guard let player = player else { return }
        guard isUserScrubbing else { return }

        isUserScrubbing = false
        let keepPlaying = wasPlayingBeforeScrub
        wasPlayingBeforeScrub = false
        seekToTrimBound(player: player, seconds: scrubPosition, keepPlaying: keepPlaying)
    }

    private var playbackBounds: (lower: Double, upper: Double) {
        let lowerBound = max(0.0, viewModel.trimStart ?? 0.0)

        var upperBound: Double
        if let trimEnd = viewModel.trimEnd {
            upperBound = trimEnd
        } else if duration > 0 {
            upperBound = duration
        } else {
            upperBound = max(lowerBound, currentTime)
        }

        if duration > 0 {
            upperBound = min(upperBound, duration)
        }

        upperBound = max(lowerBound, upperBound)
        return (lowerBound, upperBound)
    }

    private var sliderRange: ClosedRange<Double> {
        let bounds = playbackBounds
        let upper = max(bounds.upper, bounds.lower + 0.01)
        return bounds.lower...upper
    }

    private func boundedPlaybackTime(_ seconds: Double) -> Double {
        let bounds = playbackBounds
        return min(max(seconds, bounds.lower), bounds.upper)
    }

    
    private func updateDuration(_ player: AVPlayer?) {
        guard let player else { return }

        let resolvedDuration = resolvedDurationSeconds(player: player)
        guard resolvedDuration > 0 else {
            loadAssetDurationIfNeeded(from: player)
            return
        }

        self.duration = resolvedDuration
        let boundedCurrent = boundedPlaybackTime(currentTime)
        self.currentTime = boundedCurrent
        self.scrubPosition = boundedCurrent
    }

    private func resolvedDurationSeconds(player: AVPlayer) -> Double {
        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite,
           itemDuration > 0 {
            return itemDuration
        }

        if let infoDuration = videoInfo?.duration,
           infoDuration.isFinite,
           infoDuration > 0 {
            return infoDuration
        }

        return 0
    }

    private func loadAssetDurationIfNeeded(from player: AVPlayer) {
        guard !isLoadingAssetDuration else { return }
        guard let asset = player.currentItem?.asset else { return }

        isLoadingAssetDuration = true
        Task { [asset] in
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds ?? 0
            await MainActor.run {
                self.isLoadingAssetDuration = false
                guard seconds.isFinite, seconds > 0 else { return }

                self.duration = seconds
                let boundedCurrent = self.boundedPlaybackTime(self.currentTime)
                self.currentTime = boundedCurrent
                self.scrubPosition = boundedCurrent
            }
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

private struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerSurfaceNSView {
        let view = PlayerSurfaceNSView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerSurfaceNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class PlayerSurfaceNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
