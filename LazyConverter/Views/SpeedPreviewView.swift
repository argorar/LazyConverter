//
//  SpeedPreviewView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import SwiftUI
import AVFoundation


struct SpeedPreviewView: NSViewRepresentable {
    let videoURL: URL?
    let speedPercent: Double
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .duringViewResize
        
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer = playerLayer
        
        let player = AVPlayer()
        context.coordinator.setupPlayer(player: player, layer: playerLayer)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateSpeed(speed: speedPercent / 100.0)
        if let url = videoURL {
            context.coordinator.loadVideo(url: url)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var playerLayer: AVPlayerLayer?
        var player: AVPlayer?
        
        func setupPlayer(player: AVPlayer, layer: AVPlayerLayer) {
            self.player = player
            self.playerLayer = layer
            layer.player = player
        }
        
        func loadVideo(url: URL) {
            let playerItem = AVPlayerItem(url: url)
            player?.replaceCurrentItem(with: playerItem)
            player?.play()
            
            // LOOP infinito
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                self?.player?.seek(to: .zero)
                self?.player?.play()
            }
        }
        
        func updateSpeed(speed: Double) {
            player?.rate = Float(speed)
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
