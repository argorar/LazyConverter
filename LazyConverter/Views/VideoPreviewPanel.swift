//
//  VideoPreviewPanel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import AVFoundation
import AppKit
import SwiftUI

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
                        GeometryReader { geo in
                            ZStack(alignment: .bottomLeading) {
                                if viewModel.cropEnabled {
                                    CropOverlayView(
                                        cropRect: $viewModel.cropRect,
                                        trackerPivot: $viewModel.cropTrackerPivot,
                                        videoSize: CGSize(
                                            width: Double(abs(videoInfo?.videoSize.width ?? 200)),
                                            height: Double(abs(videoInfo?.videoSize.height ?? 500))),
                                        playerFrame: CGRect(
                                            x: 0, y: 0, width: geo.size.width,
                                            height: geo.size.height),
                                        showTrackerTarget: viewModel.cropTrackerEnabled,
                                        lockedAspectRatio: viewModel.cropDynamicLockedAspectRatio,
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

                                if viewModel.watermarkConfig.isEnabled {
                                    WatermarkOverlayView(
                                        watermarkConfig: $viewModel.watermarkConfig,
                                        videoSize: CGSize(
                                            width: Double(abs(videoInfo?.videoSize.width ?? 200)),
                                            height: Double(abs(videoInfo?.videoSize.height ?? 500))),
                                        playerFrame: CGRect(
                                            x: 0, y: 0, width: geo.size.width,
                                            height: geo.size.height),
                                        cropRect: viewModel.cropEnabled ? viewModel.cropRect : nil
                                    )
                                }

                                if viewModel.dynamicSpeedEnabled {
                                    DynamicSpeedOverlayView(
                                        points: viewModel.dynamicSpeedPointsSorted,
                                        bounds: viewModel.resolvedDynamicSpeedBoundsTimes(),
                                        currentTime: currentTime,
                                        fallbackEnd: max(duration, videoInfo?.duration ?? 0.0),
                                        onAddPoint: { time, speedPercent in
                                            viewModel.upsertDynamicSpeedPoint(
                                                at: time, speedPercent: speedPercent)
                                        },
                                        onUpdatePoint: { time, speedPercent in
                                            viewModel.updateDynamicSpeedPoint(
                                                time: time, speedPercent: speedPercent)
                                        },
                                        onDeletePoint: { time in
                                            viewModel.deleteDynamicSpeedPoint(near: time)
                                        }
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 10)
                                }
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
                            sliderBackground(geo: geo)
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

            if let activeSegID = viewModel.activeTrimSegmentID, let seg = viewModel.trimSegments.first(where: { $0.id == activeSegID }) {
                HStack(spacing: 12) {
                    Button(lang.t("button.start")) {
                        guard let player = player else { return }
                        seekToTrimBound(player: player, seconds: seg.start, keepPlaying: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: trimJumpButtonWidth, height: trimJumpButtonHeight)

                    Button(lang.t("button.end")) {
                        guard let player = player else { return }
                        seekToTrimBound(player: player, seconds: seg.end, keepPlaying: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: trimJumpButtonWidth, height: trimJumpButtonHeight)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

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
        .onChange(of: viewModel.colorAdjustments) { oldValue, newValue in
            applyVideoFilters()
        }
        .onChange(of: viewModel.trimSegments) { oldValue, newValue in
            if let player = player {
                self.enforceTrimBoundsIfNeeded(time: self.currentTime, duration: self.duration, player: player)
            }
        }
        .onChange(of: viewModel.cropDynamicEnabled) { oldValue, newValue in
            guard newValue, let player = player else { return }
            let minStart = viewModel.trimSegments.map { $0.start }.min()
            let start = max(0, minStart ?? 0)
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
        if modifiers.contains(.command) || modifiers.contains(.option)
            || modifiers.contains(.control)
        {
            return event
        }

        if event.charactersIgnoringModifiers?.lowercased() == "m" {
            toggleMute()
            return nil
        }

        switch event.keyCode {
        case 49:  // Space
            if modifiers.contains(.shift) {
                return event
            }
            togglePlayback()
            return nil
        case 123:  // Left arrow
            if modifiers.contains(.shift) {
                return event
            }
            stepByFrame(direction: -1)
            return nil
        case 124:  // Right arrow
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
        if modifiers.contains(.command) || modifiers.contains(.option)
            || modifiers.contains(.control)
        {
            return event
        }

        let dominantDelta =
            abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
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

        if abs(scrubPosition - targetSeconds) > 0.01 { scrubPosition = targetSeconds }
        if abs(currentTime - targetSeconds) > 0.01 { currentTime = targetSeconds }
        if abs(viewModel.liveCurrentTime - targetSeconds) > 0.01 {
            viewModel.liveCurrentTime = targetSeconds
        }

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
        let isPlayingNow = rate > 0.01

        if isPlayerPlaying != isPlayingNow {
            isPlayerPlaying = isPlayingNow
        }

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

            let isPlayingNow = player.rate > 0.01
            if isPlayerPlaying != isPlayingNow {
                isPlayerPlaying = isPlayingNow
            }

            if duration <= 0 {
                updateDuration(player)
            }

            let newTime = player.currentTime().seconds
            if !newTime.isNaN && newTime >= 0 {
                if abs(currentTime - newTime) > 0.01 {
                    currentTime = newTime
                }
                if abs(viewModel.liveCurrentTime - newTime) > 0.01 {
                    viewModel.liveCurrentTime = newTime
                }
                if !isUserScrubbing {
                    let bounded = boundedPlaybackTime(newTime)
                    if abs(scrubPosition - bounded) > 0.01 {
                        scrubPosition = bounded
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sliderBackground(geo: GeometryProxy) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
                .contentShape(Rectangle())
            
            if duration > 0 && viewModel.trimSegments.count >= 2 {
                ForEach(viewModel.trimSegments) { segment in
                    TrimSegmentRectView(
                        segment: segment,
                        duration: duration,
                        geoWidth: geo.size.width,
                        isActive: viewModel.activeTrimSegmentID == segment.id
                    )
                }
            }
        }
        .gesture(sliderDragGesture(geoWidth: geo.size.width))
    }

    private func sliderDragGesture(geoWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isHoveringSeekSlider || isPointerDragScrubbing else { return }
                if !isPointerDragScrubbing {
                    isPointerDragScrubbing = true
                    startScrubbingSession()
                }

                let width = max(1.0, geoWidth)
                let clampedX = min(max(0.0, value.location.x), width)
                let progress = Double(clampedX / width)
                let range = sliderRange
                scrubPosition =
                    range.lowerBound
                    + (range.upperBound - range.lowerBound) * progress
            }
            .onEnded { _ in
                guard isPointerDragScrubbing else { return }
                isPointerDragScrubbing = false
                finishScrubbingSession()
            }
    }

    private func enforceTrimBoundsIfNeeded(for player: AVPlayer) {
        let currentSeconds = player.currentTime().seconds
        guard !currentSeconds.isNaN && !currentSeconds.isInfinite else { return }
        self.enforceTrimBoundsIfNeeded(time: currentSeconds, duration: self.duration, player: player)
    }

    private func enforceTrimBoundsIfNeeded(time: Double, duration: Double, player: AVPlayer) {
        if viewModel.loopEnabled || isSeekingToTrimBound { return }
        let segments = viewModel.trimSegments.sorted()
        if segments.count != 1 { return } // No limits
        
        let tolerance = 0.05
        
        var insideSeg: TrimSegment?
        var nextSeg: TrimSegment?
        for seg in segments {
            if time >= (seg.start - tolerance) && time <= (seg.end + tolerance) {
                insideSeg = seg
                break
            } else if seg.start > time {
                if nextSeg == nil || seg.start < nextSeg!.start {
                    nextSeg = seg
                }
            }
        }
        
        if insideSeg == nil {
            if let next = nextSeg {
                seekToTrimBound(player: player, seconds: next.start, keepPlaying: player.rate > 0.01)
            } else {
                player.pause()
            }
        } else if let end = insideSeg?.end, time > (end - 0.01) {
            // Reached the end of the current segment
            if let next = segments.first(where: { $0.start > end }) {
                seekToTrimBound(player: player, seconds: next.start, keepPlaying: player.rate > 0.01)
            } else {
                player.pause()
            }
        }
    }

    private func seekToTrimBound(player: AVPlayer, seconds: Double, keepPlaying: Bool) {
        isSeekingToTrimBound = true
        let boundedSeconds = boundedPlaybackTime(seconds)
        let target = CMTime(seconds: boundedSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                if abs(self.currentTime - boundedSeconds) > 0.01 {
                    self.currentTime = boundedSeconds
                }
                if abs(self.scrubPosition - boundedSeconds) > 0.01 {
                    self.scrubPosition = boundedSeconds
                }
                if abs(self.viewModel.liveCurrentTime - boundedSeconds) > 0.01 {
                    self.viewModel.liveCurrentTime = boundedSeconds
                }

                if keepPlaying {
                    self.updatePlayerRate(self.viewModel.speedPercent)
                    if !self.isPlayerPlaying { self.isPlayerPlaying = true }
                } else {
                    player.pause()
                    if self.isPlayerPlaying { self.isPlayerPlaying = false }
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
        seekToTrimBound(
            player: player, seconds: base + (frameStep * Double(direction)), keepPlaying: false)
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

        if abs(currentTime - bounded) > 0.01 { currentTime = bounded }
        if abs(viewModel.liveCurrentTime - bounded) > 0.01 { viewModel.liveCurrentTime = bounded }
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
        if viewModel.trimSegments.count != 1 {
           return (lower: 0.0, upper: duration > 0 ? duration : 0.0)
        }
        let lower = viewModel.trimSegments.map { $0.start }.min() ?? 0.0
        let upper = viewModel.trimSegments.map { $0.end }.max() ?? (duration > 0 ? duration : lower)
        return (lower: lower, upper: upper)
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
            itemDuration > 0
        {
            return itemDuration
        }

        if let infoDuration = videoInfo?.duration,
            infoDuration.isFinite,
            infoDuration > 0
        {
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
            let playerItem = player.currentItem
        else { return }

        let adjustments = viewModel.colorAdjustments

        // Solo aplicar si hay modificaciones
        if !adjustments.isModified {
            playerItem.videoComposition = nil
            return
        }

        let asset = playerItem.asset
        AVVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
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
            }
        ) { composition, error in
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

private struct DynamicSpeedOverlayView: View {
    @EnvironmentObject var lang: LanguageManager

    let points: [SpeedMapPoint]
    let bounds: (start: Double, end: Double)
    let currentTime: Double
    let fallbackEnd: Double
    let onAddPoint: (Double, Double) -> Void
    let onUpdatePoint: (Double, Double) -> Void
    let onDeletePoint: (Double) -> Void

    private let overlayHeight: CGFloat = 150

    private var sortedPoints: [SpeedMapPoint] {
        points.sorted { $0.time < $1.time }
    }

    private var effectiveBounds: (start: Double, end: Double) {
        if bounds.end > bounds.start {
            return bounds
        }
        let fallback = max(bounds.start + 0.001, fallbackEnd)
        return (start: bounds.start, end: fallback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(lang.t("dynamic_speed.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("\(lang.t("dynamic_speed.points")): \(sortedPoints.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            GeometryReader { geo in
                let width = max(1.0, geo.size.width)
                let height = max(1.0, geo.size.height)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.45))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)

                    gridPath(width: width, height: height)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.6)

                    if sortedPoints.count >= 2 {
                        areaPath(points: sortedPoints, width: width, height: height)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.26),
                                        Color.accentColor.opacity(0.08),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        linePath(points: sortedPoints, width: width, height: height)
                            .stroke(
                                Color.accentColor.opacity(0.95), style: StrokeStyle(lineWidth: 2))
                    }

                    currentTimeLine(width: width, height: height)
                        .stroke(Color.yellow.opacity(0.95), lineWidth: 1.1)

                    axisLabels

                    ForEach(Array(sortedPoints.enumerated()), id: \.offset) { _, point in
                        let pointX = xPosition(for: point.time, width: width)
                        let pointY = yPosition(forSpeedPercent: point.speed * 100.0, height: height)

                        VStack(spacing: 2) {
                            Text(speedLabel(point.speed))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.pink.opacity(0.95))
                            Text("t:\(timeLabel(point.time))")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(4)
                        .position(
                            x: pointX,
                            y: max(10, min(height - 10, pointY - 18))
                        )
                        .allowsHitTesting(false)

                        Circle()
                            .fill(Color.pink.opacity(0.95))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            )
                            .position(x: pointX, y: pointY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let newSpeedPercent = speedPercent(
                                            forY: value.location.y, height: height)
                                        onUpdatePoint(point.time, newSpeedPercent)
                                    }
                            )
                            .simultaneousGesture(
                                TapGesture(count: 1)
                                    .onEnded {
                                        guard isSecondaryClickEvent() else { return }
                                        onDeletePoint(point.time)
                                    }
                            )
                            .contextMenu {
                                Button(lang.t("dynamic_speed.delete_point")) {
                                    onDeletePoint(point.time)
                                }
                            }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            if isSecondaryClickEvent() {
                                return
                            }
                            let time = timeForX(value.location.x, width: width)
                            let speedPercent = speedPercent(forY: value.location.y, height: height)
                            onAddPoint(time, speedPercent)
                        }
                )
            }
            .frame(height: overlayHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var axisLabels: some View {
        VStack {
            HStack {
                Text("100%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
            Spacer()
            HStack {
                Text("1%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
        }
        .padding(6)
        .allowsHitTesting(false)
    }

    private func gridPath(width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        let rows = 8
        let columns = 16

        for row in 0...rows {
            let y = (CGFloat(row) / CGFloat(rows)) * height
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }

        for column in 0...columns {
            let x = (CGFloat(column) / CGFloat(columns)) * width
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }

        return path
    }

    private func areaPath(points: [SpeedMapPoint], width: CGFloat, height: CGFloat) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()

        path.move(to: CGPoint(x: xPosition(for: first.time, width: width), y: height))
        path.addLine(
            to: CGPoint(
                x: xPosition(for: first.time, width: width),
                y: yPosition(forSpeedPercent: first.speed * 100.0, height: height)
            ))

        for point in points.dropFirst() {
            path.addLine(
                to: CGPoint(
                    x: xPosition(for: point.time, width: width),
                    y: yPosition(forSpeedPercent: point.speed * 100.0, height: height)
                ))
        }

        if let last = points.last {
            path.addLine(to: CGPoint(x: xPosition(for: last.time, width: width), y: height))
        }
        path.closeSubpath()

        return path
    }

    private func linePath(points: [SpeedMapPoint], width: CGFloat, height: CGFloat) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(
            to: CGPoint(
                x: xPosition(for: first.time, width: width),
                y: yPosition(forSpeedPercent: first.speed * 100.0, height: height)
            ))

        for point in points.dropFirst() {
            path.addLine(
                to: CGPoint(
                    x: xPosition(for: point.time, width: width),
                    y: yPosition(forSpeedPercent: point.speed * 100.0, height: height)
                ))
        }

        return path
    }

    private func currentTimeLine(width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        let x = xPosition(for: currentTime, width: width)
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: height))
        return path
    }

    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        let range = max(0.000001, effectiveBounds.end - effectiveBounds.start)
        let progress = min(max((time - effectiveBounds.start) / range, 0.0), 1.0)
        return CGFloat(progress) * width
    }

    private func yPosition(forSpeedPercent speedPercent: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(speedPercent, 1.0), 100.0)
        let progress = 1.0 - (clamped / 100.0)
        return CGFloat(progress) * height
    }

    private func timeForX(_ x: CGFloat, width: CGFloat) -> Double {
        let range = max(0.000001, effectiveBounds.end - effectiveBounds.start)
        let clampedX = min(max(0.0, x), width)
        let progress = Double(clampedX / width)
        return effectiveBounds.start + (range * progress)
    }

    private func speedPercent(forY y: CGFloat, height: CGFloat) -> Double {
        let clampedY = min(max(0.0, y), height)
        let progress = 1.0 - Double(clampedY / height)
        return min(max(progress * 100.0, 1.0), 100.0)
    }

    private func speedLabel(_ speed: Double) -> String {
        String(format: "S:%.2f", speed)
    }

    private func timeLabel(_ time: Double) -> String {
        String(format: "%.2f", time)
    }

    private func isSecondaryClickEvent() -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return true
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return event.modifierFlags.contains(.control)
        default:
            return event.buttonNumber == 1
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

struct TrimSegmentRectView: View {
    let segment: TrimSegment
    let duration: Double
    let geoWidth: CGFloat
    let isActive: Bool

    var body: some View {
        let segWidth = max(0, CGFloat((segment.end - segment.start) / duration) * geoWidth)
        let segOffset = CGFloat(segment.start / duration) * geoWidth
        
        Rectangle()
            .fill(isActive ? Color.accentColor.opacity(0.4) : Color.blue.opacity(0.2))
            .cornerRadius(2)
            .frame(width: segWidth, height: 4)
            .offset(x: segOffset)
    }
}
