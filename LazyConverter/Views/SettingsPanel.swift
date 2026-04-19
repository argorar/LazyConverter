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
    @EnvironmentObject var watermarkPreferences: WatermarkPreferencesManager
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
            watermarkSection
            cropSection
            formatSection
            trimSection
            qualitySection
            SpeedSliderPanel(viewModel: viewModel)
            FrameRateSection(viewModel: viewModel)
            stabilizationSection
            dynamicSpeedSection
            loopSection
            resolutionSection
            outputSizeLimitSection
            colorAdjustmentsSection
            advancedOptionsSection
            Spacer()
        }
        .padding(16)
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 12, material: .sidebar, fallbackColor: Color(nsColor: .controlBackgroundColor), fallbackOpacity: 1.0)
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
                HStack {
                    Text("Aspect Ratio:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.cropAspectRatio) {
                        ForEach(CropAspectRatioOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 100)
                    Spacer()
                }

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
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
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
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
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
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
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
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
        
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $viewModel.superCompression) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.badge.clock.fill")
                        .foregroundColor(viewModel.superCompression ? .orange : .secondary)
                    Text(lang.t("super_compression.title"))
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .toggleStyle(.switch)
            
            if viewModel.superCompression {
                Text(lang.t("super_compression.desc"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
                
                Toggle(isOn: $viewModel.superCompressionGPU) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .foregroundColor(viewModel.superCompressionGPU ? .accentColor : .secondary)
                        Text(lang.t("super_compression.gpu.title"))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
    }

    @ViewBuilder
    private var outputSizeLimitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("size_limit.title"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(viewModel.maxOutputSizeMB.map { "\($0) MB" } ?? lang.t("size_limit.off"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                TextField(
                    lang.t("size_limit.placeholder"),
                    text: Binding(
                        get: { viewModel.maxOutputSizeMBInput },
                        set: { newValue in
                            let digitsOnly = newValue.filter { $0.isNumber }
                            viewModel.maxOutputSizeMBInput = digitsOnly
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)

                Text("MB")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button(lang.t("button.clear")) {
                    viewModel.maxOutputSizeMBInput = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
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
                Spacer()
                Button(action: {
                    let start = viewModel.trimSegments.map { $0.end }.max() ?? 0.0
                    let end = viewModel.videoInfo?.duration ?? (start + 5.0)
                    let newSeg = TrimSegment(start: start, end: max(start + 0.1, end))
                    viewModel.trimSegments.append(newSeg)
                    viewModel.activeTrimSegmentID = newSeg.id
                }) {
                    Image(systemName: "plus")
                    Text(lang.t("trim.add_segment"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            if viewModel.trimSegments.isEmpty {
                Text(lang.t("trim.no_segments"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.trimSegments) { segment in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(viewModel.activeTrimSegmentID == segment.id ? Color.accentColor : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                                
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(lang.t("trim.start"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text(formatTime(segment.start))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(viewModel.activeTrimSegmentID == segment.id ? .green : .primary)
                                }
                                HStack {
                                    Text(lang.t("trim.end"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text(formatTime(segment.end))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(viewModel.activeTrimSegmentID == segment.id ? .blue : .primary)
                                }
                            }
                            
                            Spacer()
                            
                            if viewModel.activeTrimSegmentID == segment.id {
                                VStack(spacing: 4) {
                                    Button("Set Start") {
                                        if let idx = viewModel.trimSegments.firstIndex(where: { $0.id == segment.id }) {
                                            viewModel.trimSegments[idx].start = viewModel.liveCurrentTime
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.bordered)
                                    
                                    Button("Set End") {
                                        if let idx = viewModel.trimSegments.firstIndex(where: { $0.id == segment.id }) {
                                            viewModel.trimSegments[idx].end = viewModel.liveCurrentTime
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.bordered)
                                }
                            }
                            
                            Button(action: {
                                viewModel.trimSegments.removeAll(where: { $0.id == segment.id })
                                if viewModel.activeTrimSegmentID == segment.id {
                                    viewModel.activeTrimSegmentID = nil
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.activeTrimSegmentID == segment.id ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
                        )
                        .onTapGesture {
                            viewModel.activeTrimSegmentID = segment.id
                            viewModel.liveCurrentTime = segment.start
                        }
                    }
                }
            }
            
            if !viewModel.trimSegments.isEmpty {
                Button(action: {
                    viewModel.trimSegments.removeAll()
                    viewModel.activeTrimSegmentID = nil
                }) {
                    Text(lang.t("button.clear"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(12)
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 12, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
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
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 12, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
    }

    @ViewBuilder
    private var stabilizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("stabilization.title"))
                    .font(.system(size: 14, weight: .semibold))
                Toggle("", isOn: stabilizationToggleBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Spacer()
            }

            if viewModel.stabilizationEnabled {
                Picker("", selection: $viewModel.stabilizationLevel) {
                    Text(lang.t("stabilization.low")).tag(VideoStabilizationLevel.low)
                    Text(lang.t("stabilization.medium")).tag(VideoStabilizationLevel.medium)
                    Text(lang.t("stabilization.high")).tag(VideoStabilizationLevel.high)
                }
                .pickerStyle(.segmented)

                Text(lang.t("stabilization.description"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
    }

    private var stabilizationToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.stabilizationEnabled },
            set: { enabled in
                viewModel.stabilizationEnabled = enabled
            }
        )
    }

    @ViewBuilder
    private var dynamicSpeedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("dynamic_speed.title"))
                    .font(.system(size: 14, weight: .semibold))
                Toggle("", isOn: $viewModel.dynamicSpeedEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Spacer()
            }

            if viewModel.dynamicSpeedEnabled {
                HStack(spacing: 8) {
                    Text("\(lang.t("dynamic_speed.points")): \(viewModel.dynamicSpeedPointsSorted.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(lang.t("dynamic_speed.reset")) {
                        viewModel.resetDynamicSpeedPoints()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                }

                Text(lang.t("dynamic_speed.description"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
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
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
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
                HStack {
                    Text(lang.t("advanced.style"))
                    Spacer()
                    Picker("", selection: $theme.surfaceStyle) {
                        ForEach(AppSurfaceStyle.allCases) { styleOption in
                            Text(lang.t("style.\(styleOption.rawValue)")).tag(styleOption)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: theme.surfaceStyle) { _, _ in
                        theme.saveSurfaceStyle()
                    }
                }
                HStack {
                    Text(lang.t("advanced.defaultWatermark"))
                    Spacer()
                    TextField(lang.t("advanced.defaultWatermark.placeholder"), text: $watermarkPreferences.defaultWatermarkText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
            }
            .padding(.top, 12)
        }
        .font(.system(size: 12, weight: .medium, design: .default))
    }

    @ViewBuilder
    private var watermarkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "textformat")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                Text(lang.t("watermark.title"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                if viewModel.watermarkConfig.isEnabled {
                    Button(action: { viewModel.resetWatermark() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(lang.t("watermark.reset"))
                }

                Button(lang.t("watermark.configure")) {
                    viewModel.showWatermarkSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.selectedFileURL == nil)
            }

            if viewModel.watermarkConfig.isEnabled {
                HStack(spacing: 8) {
                    Text("\"\(viewModel.watermarkConfig.text)\"")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                    Text("\(Int(viewModel.watermarkConfig.fontSize))px")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(Int(viewModel.watermarkConfig.opacity * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(viewModel.watermarkConfig.color)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.3), lineWidth: 0.5)
                        )
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .adaptiveCard(useGlass: theme.surfaceStyle == .glass, cornerRadius: 8, material: .hudWindow, fallbackColor: Color(nsColor: .separatorColor), fallbackOpacity: 0.3)
        .sheet(isPresented: $viewModel.showWatermarkSheet) {
            WatermarkConfigSheet(viewModel: viewModel)
                .environmentObject(lang)
                .environmentObject(watermarkPreferences)
        }
    }
}
