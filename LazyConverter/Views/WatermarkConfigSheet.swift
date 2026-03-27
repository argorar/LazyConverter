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
    @EnvironmentObject var watermarkPreferences: WatermarkPreferencesManager
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var fontName: String = WatermarkConfig.systemFontToken
    @State private var fontSearchQuery: String = ""
    @State private var fontSize: CGFloat = 48
    @State private var color: Color = .white
    @State private var opacity: Double = 1.0
    private let availableFonts: [String] = [WatermarkConfig.systemFontToken] + NSFontManager.shared.availableFonts.sorted()
    private var filteredFonts: [String] {
        let query = fontSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableFonts }
        return availableFonts.filter { font in
            fontLabel(for: font).localizedCaseInsensitiveContains(query) || font.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(lang.t("watermark.title"))
                    .font(.system(size: 18, weight: .semibold))
                Text(lang.t("watermark.drag_hint"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            
            Divider()
            
            // -- BODY --
            VStack(spacing: 24) {
                // Controls Group
                VStack(alignment: .leading, spacing: 16) {
                    formRow(title: lang.t("watermark.text")) {
                        TextField("", text: $text)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }
                    
                    formRow(title: lang.t("watermark.fontSize")) {
                        HStack(spacing: 12) {
                            Slider(value: $fontSize, in: 12...120, step: 1)
                                .tint(.accentColor)
                            Text("\(Int(fontSize))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }

                    formRow(title: lang.t("watermark.font")) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(lang.t("watermark.font.search"), text: $fontSearchQuery)
                                .textFieldStyle(.roundedBorder)

                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(filteredFonts, id: \.self) { font in
                                        fontOptionRow(font: font)
                                    }
                                }
                                .padding(4)
                            }
                            .frame(height: 150)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )

                            if filteredFonts.isEmpty {
                                Text(lang.t("watermark.font.no_results"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    formRow(title: lang.t("watermark.color")) {
                        ColorPicker("", selection: $color, supportsOpacity: false)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    formRow(title: lang.t("watermark.opacity")) {
                        HStack(spacing: 12) {
                            Slider(value: $opacity, in: 0.1...1.0, step: 0.05)
                                .tint(.accentColor)
                            Text("\(Int(opacity * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                
                // Preview Area
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 112)
                    
                    HStack {
                        Spacer()
                        ZStack {
                            GeometryReader { geo in
                                Path { path in
                                    let size: CGFloat = 8
                                    for x in stride(from: 0, to: geo.size.width + size, by: size) {
                                        for y in stride(from: 0, to: geo.size.height + size, by: size) {
                                            if (Int(x / size) + Int(y / size)) % 2 == 0 {
                                                path.addRect(CGRect(x: x, y: y, width: size, height: size))
                                            }
                                        }
                                    }
                                }
                                .fill(Color.gray.opacity(0.15))
                            }
                            
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Watermark")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.3))
                            } else {
                                Text(text)
                                    .font(previewFont(size: min(fontSize, 40)))
                                    .foregroundColor(color.opacity(opacity))
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
                                    .padding()
                            }
                        }
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.leading, 112)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            
            Divider()
            
            HStack {
                Spacer()
                Button(lang.t("watermark.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                
                Button(lang.t("watermark.apply")) {
                    watermarkPreferences.defaultWatermarkFontName = sanitizedFontName(fontName)
                    viewModel.watermarkConfig = WatermarkConfig(
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        fontName: sanitizedFontName(fontName),
                        fontSize: fontSize,
                        color: color,
                        opacity: opacity,
                        position: viewModel.watermarkConfig.position
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480)
        .onAppear {
            text = viewModel.watermarkConfig.text
            if viewModel.watermarkConfig.isEnabled {
                fontName = sanitizedFontName(viewModel.watermarkConfig.fontName)
            } else {
                fontName = sanitizedFontName(watermarkPreferences.defaultWatermarkFontName)
            }
            fontSize = viewModel.watermarkConfig.fontSize
            color = viewModel.watermarkConfig.color
            opacity = viewModel.watermarkConfig.opacity

            if text.isEmpty {
                let defaultThemeWatermark = watermarkPreferences.defaultWatermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
                text = defaultThemeWatermark.isEmpty ? "LazyConverter" : defaultThemeWatermark
                fontSize = 28
                color = .white
                opacity = 0.8
            }
        }
    }

    private func fontLabel(for font: String) -> String {
        font == WatermarkConfig.systemFontToken ? lang.t("watermark.font.system") : font
    }

    private func previewFont(size: CGFloat) -> Font {
        if fontName == WatermarkConfig.systemFontToken {
            return .system(size: size, weight: .bold)
        }
        return .custom(fontName, size: size)
    }

    @ViewBuilder
    private func fontOptionRow(font: String) -> some View {
        let isSelected = fontName == font
        Button(action: { fontName = font }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fontLabel(for: font))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(sampleFontPreviewText)
                        .font(previewFont(for: font, size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var sampleFontPreviewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "LazyConverter" : trimmed
    }

    private func previewFont(for font: String, size: CGFloat) -> Font {
        if font == WatermarkConfig.systemFontToken {
            return .system(size: size, weight: .bold)
        }
        return .custom(font, size: size)
    }

    private func sanitizedFontName(_ name: String) -> String {
        availableFonts.contains(name) ? name : WatermarkConfig.systemFontToken
    }
    
    private func formRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            content()
        }
    }
}
