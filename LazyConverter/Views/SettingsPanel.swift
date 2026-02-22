//
//  SettingsPanel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//


import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var viewModel: VideoConversionViewModel
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var theme: ThemeManager
    @State private var showCropHelp = false
    
    private var cropHelpText: String {
        "\(lang.t("crop.extraInfo"))\n\(lang.t("crop.dynamicInfo"))\n\(lang.t("crop.trackerInfo"))"
    }
    
    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && !time.isInfinite && time >= 0 else { return "--:--.--" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time * 100).truncatingRemainder(dividingBy: 100))
        return String(format: "%d:%02d.%02d", minutes, seconds, ms)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerTitle
            cropSection
            formatSection
            resolutionSection
            qualitySection
            SpeedSliderPanel(viewModel: viewModel)
            FrameRateSection(viewModel: viewModel)
            trimSection
            loopSection
            colorAdjustmentsSection
            advancedOptionsSection
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var headerTitle: some View {
        Text(lang.t("header.config"))
            .font(.system(size: 16, weight: .semibold, design: .default))
            .foregroundColor(.primary)
    }
    
    @ViewBuilder
    private var cropSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "crop")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("crop.enable"))
                    .font(.system(size: 14, weight: .semibold))
                Toggle("", isOn: $viewModel.cropEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Spacer()
                if viewModel.cropEnabled {
                    if viewModel.cropDynamicEnabled {
                        Text("\(lang.t("crop.keyframes")): \(viewModel.cropDynamicKeyframes.count)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Button(action: { viewModel.resetCrop() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(lang.t("crop.reset"))

                    Button(action: { showCropHelp.toggle() }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(cropHelpText)
                    .popover(isPresented: $showCropHelp, arrowEdge: .top) {
                        Text(cropHelpText)
                            .font(.system(size: 13))
                            .padding(12)
                    }
                }
            }

            if viewModel.cropEnabled {
                HStack(alignment: .center, spacing: 8) {
                    Toggle(lang.t("crop.dynamic"), isOn: $viewModel.cropDynamicEnabled)
                        .toggleStyle(.switch)
                    Toggle(lang.t("crop.tracker"), isOn: $viewModel.cropTrackerEnabled)
                        .toggleStyle(.switch)
                    if viewModel.isTrackingCrop {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text(lang.t("crop.tracking"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .separatorColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("format.title"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Picker("", selection: $viewModel.selectedFormat) {
                ForEach(VideoFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .separatorColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "inset.filled.rectangle.and.person.filled")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("resolution.title"))
                    .font(.system(size: 14, weight: .semibold))
            }
            Picker("", selection: $viewModel.selectedResolution) {
                ForEach(VideoResolution.allCases, id: \.self) { resolution in
                    Text(resolution.displayName).tag(resolution)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .separatorColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "aqi.medium")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("quality.title"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(Int(viewModel.quality)) CRF")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(.accentColor)
            }
            Slider(value: $viewModel.quality, in: 1...51, step: 1)
                .tint(.accentColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .separatorColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var trimSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scissors")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("trim.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            HStack(spacing: 12) {
                Button(lang.t("button.start")) {
                    if viewModel.selectedFileURL == nil { return }
                    viewModel.trimStart = viewModel.liveCurrentTime
                }
                .background(viewModel.trimStart != nil ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                .foregroundColor(.white)
                Button(lang.t("button.end")) {
                    if viewModel.selectedFileURL == nil { return }
                    viewModel.trimEnd = viewModel.liveCurrentTime
                }
                .background(viewModel.trimEnd != nil ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .foregroundColor(.white)
                Button(lang.t("button.clear")) {
                    viewModel.trimStart = nil
                    viewModel.trimEnd = nil
                }
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lang.t("trim.start"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.trimStart != nil ? formatTime(viewModel.trimStart!) : "--:--.--")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewModel.trimStart != nil ? .green : .secondary)
                }
                HStack {
                    Text(lang.t("trim.end"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.trimEnd != nil ? formatTime(viewModel.trimEnd!) : "--:--.--")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewModel.trimEnd != nil ? .blue : .secondary)
                }
                if let start = viewModel.trimStart, let end = viewModel.trimEnd {
                    let duration = end - start
                    HStack {
                        Text(lang.t("trim.duration"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(duration))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .separatorColor).opacity(0.3))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var colorAdjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("color.adjustments"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if viewModel.colorAdjustments.isModified {
                    Button(lang.t("reset")) {
                        viewModel.resetColorAdjustments()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lang.t("brightness")).font(.system(size: 12))
                    Spacer()
                    Text(String(format: "%.2f", viewModel.colorAdjustments.brightness))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                Slider(value: viewModel.brightness, in: -1.0...1.0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lang.t("contrast")).font(.system(size: 12))
                    Spacer()
                    Text(String(format: "%.2f", viewModel.colorAdjustments.contrast))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                Slider(value: viewModel.contrast, in: 0.0...2.0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lang.t("gamma")).font(.system(size: 12))
                    Spacer()
                    Text(String(format: "%.2f", viewModel.colorAdjustments.gamma))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                Slider(value: viewModel.gamma, in: 0.5...2.5)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lang.t("saturation")).font(.system(size: 12))
                    Spacer()
                    Text(String(format: "%.2f", viewModel.colorAdjustments.saturation))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                Slider(value: viewModel.saturation, in: 0.0...2.0)
            }
        }
        .padding(12)
        .background(Color(nsColor: .separatorColor).opacity(0.3))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var loopSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "repeat")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
            Text(lang.t("loop.title"))
                .font(.system(size: 14, weight: .semibold))
            Toggle("", isOn: $viewModel.loopEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .separatorColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var advancedOptionsSection: some View {
        DisclosureGroup(lang.t("advanced.options")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(lang.t("advanced.language"))
                    Spacer()
                    Picker("", selection: $lang.language) {
                        ForEach(AppLanguage.allCases) { langOption in
                            Text(langOption.displayName).tag(langOption)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: lang.language) { oldValue, newValue in
                        lang.saveUserLanguage()
                    }
                }
                HStack {
                    Text(lang.t("advanced.output"))
                    Spacer()
                    Picker("", selection: $viewModel.outputDirectory) {
                        ForEach(OutputDirectory.allCases) { option in
                            Text(lang.t("output.\(option.rawValue)")).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    .onChange(of: viewModel.outputDirectory) { oldValue, newValue in
                        viewModel.persistOutputDirectory()
                    }
                }
                HStack {
                    Text(lang.t("advanced.theme"))
                    Spacer()
                    Picker("", selection: $theme.theme) {
                        ForEach(AppTheme.allCases) { themeOption in
                            Text(lang.t("theme.\(themeOption.rawValue)")).tag(themeOption)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: theme.theme) { oldValue, newValue in
                        theme.saveUserTheme()
                    }
                }
            }
            .padding(.top, 12)
        }
        .font(.system(size: 12, weight: .medium, design: .default))
    }
}
