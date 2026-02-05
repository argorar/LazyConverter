//
//  VideoPreviewView.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import SwiftUI

struct VideoPreviewView: View {
    let videoInfo: VideoInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Info del Video
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.accentColor)
                    Text(videoInfo.fileName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                }
                
                HStack(spacing: 20) {
                    infoItem("⏱️", videoInfo.durationString)
                    infoItem("📏", videoInfo.sizeString)
                    infoItem("🎞️", String(format: "%.2f FPS", videoInfo.frameRate))
                    infoItem("💾", String(format: "%.1f MB", videoInfo.fileSizeMB))
                    infoItem(videoInfo.hasAudio ? "🔊" : "🔇", videoInfo.hasAudio ? "Sí" : "No")
                    infoItem("🎨", videoInfo.colorInfo.pixelFormat)
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .cornerRadius(12)
    }
    
    private func infoItem(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(icon)
            Text(value)
        }
    }
}

