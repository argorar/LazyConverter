//
//  FrameRateSection.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 1/02/26.
//

import SwiftUI

struct FrameRateSection: View {
    @ObservedObject var viewModel: VideoConversionViewModel
    @EnvironmentObject var lang: LanguageManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                
                Text(lang.t("framerate.title"))
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                if let sourceFPS = viewModel.videoInfo?.frameRate {
                    Text("\(String(format: "%.2f", sourceFPS)) fps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .separatorColor).opacity(0.3))
                        .cornerRadius(4)
                }
            }
            
            Picker(lang.t("framerate.mode"), selection: $viewModel.frameRateSettings.mode) {
                Text(lang.t("framerate.keep")).tag(FrameRateMode.keep)
                Text(lang.t("framerate.interpolate")).tag(FrameRateMode.interpolate)
            }
            .pickerStyle(.segmented)

            if viewModel.frameRateSettings.mode == .interpolate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.t("framerate.target"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(FrameRate.allCases, id: \.self) { fps in
                            frameRateButton(fps: fps)
                        }
                    }
                }
                .padding(.top, 4)
                
                // Warning
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text(lang.t("framerate.interpolate.warning"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color(nsColor: .separatorColor).opacity(0.3))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func frameRateButton(fps: FrameRate) -> some View {
        Button(action: {
            viewModel.frameRateSettings.targetFrameRate = fps
        }) {
            VStack(spacing: 4) {
                Text(fps.shortName)
                    .font(.system(size: 13, weight: .semibold))
                Text("fps")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                viewModel.frameRateSettings.targetFrameRate == fps
                    ? Color.accentColor
                    : Color(nsColor: .controlBackgroundColor)
            )
            .foregroundColor(
                viewModel.frameRateSettings.targetFrameRate == fps
                    ? .white
                    : .primary
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        viewModel.frameRateSettings.targetFrameRate == fps
                            ? Color.accentColor
                            : Color(nsColor: .separatorColor),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
