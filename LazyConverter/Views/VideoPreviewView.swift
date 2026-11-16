//
//  VideoPreviewView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import SwiftUI

struct VideoPreviewView: View {
    let videoInfo: VideoInfo
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var lang: LanguageManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Info del Video
            HStack(spacing: 6) {
                Image(systemName: "film")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(videoInfo.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
            }
            
            HStack(spacing: 16) {
                infoItem("clock", videoInfo.durationString)
                infoItem("aspectratio", videoInfo.sizeString)
                infoItem("film", String(format: "%.2f FPS", videoInfo.frameRate))
                infoItem("internaldrive", String(format: "%.1f MB", videoInfo.fileSizeMB))
                infoItem(
                    videoInfo.hasAudio ? "speaker.wave.2" : "speaker.slash",
                    lang.t(videoInfo.hasAudio ? "common.yes" : "common.no")
                )
                infoItem("paintpalette", videoInfo.colorInfo.pixelFormat)
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
        }
        .padding(12)
        .adaptiveCard(
            useGlass: theme.surfaceStyle == .glass,
            cornerRadius: 12,
            material: .hudWindow,
            fallbackColor: Color(nsColor: .controlBackgroundColor),
            fallbackOpacity: 0.7
        )
    }
    
    private func infoItem(_ systemName: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .regular))
                .frame(width: 13)
            Text(value)
        }
    }
}
