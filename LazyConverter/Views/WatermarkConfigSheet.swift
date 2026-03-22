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
                                    .font(.system(size: min(fontSize, 40), weight: .bold))
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
                    viewModel.watermarkConfig = WatermarkConfig(
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
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
            fontSize = viewModel.watermarkConfig.fontSize
            color = viewModel.watermarkConfig.color
            opacity = viewModel.watermarkConfig.opacity
            
            if text.isEmpty {
                text = "LazyConverter"
                fontSize = 28
                color = .white
                opacity = 0.8
            }
        }
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
