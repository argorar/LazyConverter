//
//  WatermarkConfigSheet.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 16/03/26.
//

import SwiftUI
import AppKit

struct WatermarkConfigSheet: View {
    @ObservedObject var viewModel: VideoConversionViewModel
    @EnvironmentObject var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var fontSize: CGFloat = 48
    @State private var color: Color = .white
    @State private var opacity: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "textformat")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("watermark.title"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            // Text input
            VStack(alignment: .leading, spacing: 6) {
                Text(lang.t("watermark.text"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField(lang.t("watermark.text"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
            }

            // Font size slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lang.t("watermark.fontSize"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(fontSize)) px")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                Slider(value: $fontSize, in: 12...120, step: 1)
                    .tint(.accentColor)
            }

            // Color picker
            HStack {
                Text(lang.t("watermark.color"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
            }

            // Opacity slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lang.t("watermark.opacity"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(opacity * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                Slider(value: $opacity, in: 0.1...1.0, step: 0.05)
                    .tint(.accentColor)
            }

            // Preview of the watermark text
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: min(fontSize, 32)))
                        .foregroundColor(color.opacity(opacity))
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    Spacer()
                }
            }

            Divider()

            // Hint text
            Text(lang.t("watermark.drag_hint"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Action buttons
            HStack {
                Spacer()
                Button(lang.t("watermark.cancel")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)

                Button(lang.t("watermark.apply")) {
                    viewModel.watermarkConfig = WatermarkConfig(
                        text: text,
                        fontSize: fontSize,
                        color: color,
                        opacity: opacity,
                        position: viewModel.watermarkConfig.position
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 420)
        .onAppear {
            text = viewModel.watermarkConfig.text
            fontSize = viewModel.watermarkConfig.fontSize
            color = viewModel.watermarkConfig.color
            opacity = viewModel.watermarkConfig.opacity
        }
    }
}
