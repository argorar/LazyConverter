//
//  AppLanguage.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import Foundation
import CoreGraphics
import Foundation

class FFmpegConverter {
    static let shared = FFmpegConverter()
    
    private var process: Process?
    private var progressCallback: ((Double) -> Void)?
    private(set) var lastErrorLog: String?
    
    func convert(_ request: FFmpegConversionRequest) {
        self.progressCallback = request.progressCallback
        
        print("🔹 FFmpegConverter.convert()")
        print("    speed: \(Int(request.speedPercent))%")
        print("    dynamic speed: \(request.dynamicSpeedEnabled ? "on" : "off")")
        print("    outputURL: \(request.outputURL.path)")
        print("    format   : \(request.format)")
        print("    resolution: \(request.resolution)")
        print("    quality  : \(request.quality)")
        print("    size limit: \(request.maxOutputSizeMB.map { "\($0) MB" } ?? "off")")
        print("    useGPU   : \(request.useGPU)")
        print("    stabilization: \(request.stabilizationLevel?.rawValue ?? "none")")
        
        guard let ffmpegPath = resolvedFFmpegPath(),
              FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
            print("❌ FFmpeg no encontrado en rutas conocidas")
            request.completionCallback(.failure(.ffmpegNotFound))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.runConversionPipeline(
                request: request,
                executablePath: ffmpegPath,
                completionCallback: request.completionCallback
            )
        }
    }
    
    private func runConversionPipeline(
        request: FFmpegConversionRequest,
        executablePath: String,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        let effectiveDuration = resolvedOutputDuration(request)

        var watermarkImageURL: URL?
        if !request.superCompression,
           let wmConfig = request.watermarkConfig, wmConfig.isEnabled,
           let videoSize = request.videoInfo?.videoSize {
            watermarkImageURL = WatermarkImageGenerator.generate(
                config: wmConfig,
                videoSize: videoSize,
                cropRect: request.cropEnable ? request.cropRec : nil
            )
        }

        let cleanupWatermark: () -> Void = {
            if let url = watermarkImageURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        if let stabilizationLevel = request.stabilizationLevel {
            runStabilizationTwoPassPipeline(
                request: request,
                stabilizationLevel: stabilizationLevel,
                executablePath: executablePath,
                videoDuration: effectiveDuration,
                watermarkImageURL: watermarkImageURL,
                completionCallback: { result in
                    cleanupWatermark()
                    completionCallback(result)
                }
            )
            return
        }

        // When watermark is present, use a two-pass pipeline:
        // Pass 1: Apply all video/audio filters → intermediate file
        // Pass 2: Overlay the watermark PNG → final output
        if let wmURL = watermarkImageURL {
            let outputDir = request.outputURL.deletingLastPathComponent()
            let baseName = request.outputURL.deletingPathExtension().lastPathComponent
            let intermediateURL = makeTemporaryOutputURL(
                in: outputDir,
                baseName: "\(baseName)_prewm",
                fileExtension: request.outputURL.pathExtension
            )

            let pass1Args = buildFFmpegCommand(
                request,
                stabilizationTransformURL: nil,
                outputURL: intermediateURL,
                stabilizationEnabledOverride: false,
                includeOutputSizeLimit: !request.loopEnabled
            )
            logCommand(executablePath: executablePath, arguments: pass1Args)

            let runPass2: (URL) -> Void = { inputForOverlay in
                let overlayArgs = self.buildWatermarkOverlayCommand(
                    inputURL: inputForOverlay,
                    watermarkURL: wmURL,
                    outputURL: request.outputURL,
                    format: request.format,
                    quality: request.quality,
                    useGPU: request.useGPU,
                    maxOutputSizeMB: request.maxOutputSizeMB
                )
                self.logCommand(executablePath: executablePath, arguments: overlayArgs)
                self.executeFFmpeg(
                    executablePath: executablePath,
                    arguments: overlayArgs,
                    videoDuration: effectiveDuration,
                    completionCallback: { overlayResult in
                        try? FileManager.default.removeItem(at: inputForOverlay)
                        cleanupWatermark()
                        completionCallback(overlayResult)
                    }
                )
            }

            if request.loopEnabled {
                // With loop: pass 1 → boomerang → watermark overlay
                executeMainAndOptionalLoop(
                    request: request,
                    executablePath: executablePath,
                    arguments: pass1Args,
                    videoDuration: effectiveDuration,
                    completionCallback: { pass1Result in
                        switch pass1Result {
                        case .success(let resultURL):
                            runPass2(resultURL)
                        case .failure(let error):
                            try? FileManager.default.removeItem(at: intermediateURL)
                            cleanupWatermark()
                            completionCallback(.failure(error))
                        }
                    }
                )
            } else {
                // Without loop: pass 1 → watermark overlay
                executeFFmpeg(
                    executablePath: executablePath,
                    arguments: pass1Args,
                    videoDuration: effectiveDuration,
                    completionCallback: { pass1Result in
                        switch pass1Result {
                        case .success:
                            runPass2(intermediateURL)
                        case .failure(let error):
                            try? FileManager.default.removeItem(at: intermediateURL)
                            cleanupWatermark()
                            completionCallback(.failure(error))
                        }
                    }
                )
            }
            return
        }

        // No watermark — single-pass pipeline
        let mainArguments = buildFFmpegCommand(
            request,
            stabilizationTransformURL: nil,
            outputURL: request.outputURL,
            stabilizationEnabledOverride: false,
            includeOutputSizeLimit: !request.loopEnabled
        )
        logCommand(executablePath: executablePath, arguments: mainArguments)
        executeMainAndOptionalLoop(
            request: request,
            executablePath: executablePath,
            arguments: mainArguments,
            videoDuration: effectiveDuration,
            completionCallback: completionCallback
        )
    }

    private func requestNeedsBaseFilterPass(_ request: FFmpegConversionRequest) -> Bool {
        if !request.trimSegments.isEmpty {
            return true
        }
        if request.resolution != .original {
            return true
        }
        if request.cropEnable {
            return true
        }
        if request.colorAdjustments.toFFmpegFilter() != nil {
            return true
        }
        if request.frameRateSettings.toFFmpegFilter() != nil {
            return true
        }
        if request.speedPercent != 100.0 || request.dynamicSpeedEnabled {
            return true
        }
        return false
    }

    private func runStabilizationTwoPassPipeline(
        request: FFmpegConversionRequest,
        stabilizationLevel: VideoStabilizationLevel,
        executablePath: String,
        videoDuration: Double,
        watermarkImageURL: URL? = nil,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        let outputDirectory = request.outputURL.deletingLastPathComponent()
        let outputName = request.outputURL.deletingPathExtension().lastPathComponent
        let transformsURL = makeTemporaryTransformURL(
            in: outputDirectory,
            baseName: outputName
        )

        let hasWatermark = watermarkImageURL != nil
        let finalOutputURL = request.outputURL
        let needsBasePass = requestNeedsBaseFilterPass(request)

        let intermediateURL: URL? = needsBasePass
            ? makeTemporaryOutputURL(
                in: outputDirectory,
                baseName: "\(outputName)_prestab",
                fileExtension: request.outputURL.pathExtension
            )
            : nil

        let stabilizationInputURL = intermediateURL ?? request.inputURL

        let stabilizedURL: URL
        if request.loopEnabled || hasWatermark {
            stabilizedURL = makeTemporaryOutputURL(
                in: outputDirectory,
                baseName: "\(outputName)_stabilized",
                fileExtension: request.outputURL.pathExtension
            )
        } else {
            stabilizedURL = finalOutputURL
        }

        let cleanup: () -> Void = {
            if let url = intermediateURL {
                try? FileManager.default.removeItem(at: url)
            }
            try? FileManager.default.removeItem(at: transformsURL)
            if stabilizedURL != finalOutputURL {
                try? FileManager.default.removeItem(at: stabilizedURL)
            }
        }

        let applyWatermarkIfNeeded: (URL) -> Void = { [self] inputURL in
            guard let wmURL = watermarkImageURL else {
                cleanup()
                completionCallback(.success(inputURL))
                return
            }
            let overlayArgs = self.buildWatermarkOverlayCommand(
                inputURL: inputURL,
                watermarkURL: wmURL,
                outputURL: finalOutputURL,
                format: request.format,
                quality: request.quality,
                useGPU: request.useGPU,
                maxOutputSizeMB: request.maxOutputSizeMB
            )
            self.logCommand(executablePath: executablePath, arguments: overlayArgs)
            self.executeFFmpeg(
                executablePath: executablePath,
                arguments: overlayArgs,
                videoDuration: videoDuration,
                completionCallback: { wmResult in
                    if inputURL != finalOutputURL {
                        try? FileManager.default.removeItem(at: inputURL)
                    }
                    cleanup()
                    completionCallback(wmResult)
                }
            )
        }

        let runStabilization: () -> Void = { [self] in
            let detectArguments = self.buildStabilizationDetectCommand(
                inputURL: stabilizationInputURL,
                transformsURL: transformsURL,
                level: stabilizationLevel
            )
            self.logCommand(executablePath: executablePath, arguments: detectArguments)
            self.executeFFmpeg(
                executablePath: executablePath,
                arguments: detectArguments,
                videoDuration: videoDuration,
                reportProgress: false,
                completionCallback: { detectResult in
                    switch detectResult {
                    case .failure(let error):
                        cleanup()
                        completionCallback(.failure(error))
                    case .success:
                        let transformArguments = self.buildStabilizationTransformCommand(
                            request: request,
                            stabilizationLevel: stabilizationLevel,
                            inputURL: stabilizationInputURL,
                            outputURL: stabilizedURL,
                            transformsURL: transformsURL,
                            includeOutputSizeLimit: !request.loopEnabled && !hasWatermark
                        )
                        self.logCommand(
                            executablePath: executablePath, arguments: transformArguments)
                        self.executeFFmpeg(
                            executablePath: executablePath,
                            arguments: transformArguments,
                            videoDuration: videoDuration,
                            completionCallback: { transformResult in
                                switch transformResult {
                                case .failure(let error):
                                    cleanup()
                                    completionCallback(.failure(error))
                                case .success:
                                    if request.loopEnabled {
                                        let boomerangOutputURL = hasWatermark
                                            ? self.makeTemporaryOutputURL(
                                                in: outputDirectory,
                                                baseName: "\(outputName)_boomerang",
                                                fileExtension: request.outputURL.pathExtension
                                            )
                                            : finalOutputURL

                                        let boomerangArgs = self.buildBoomerangCommand(
                                            inputURL: stabilizedURL,
                                            outputURL: boomerangOutputURL,
                                            format: request.format,
                                            quality: request.quality,
                                            useGPU: request.useGPU,
                                            hasAudio: request.videoInfo?.hasAudio == true
                                                && request.speedPercent == 100.0
                                                && !request.dynamicSpeedEnabled,
                                            maxOutputSizeMB: request.maxOutputSizeMB,
                                            duration: videoDuration * 2
                                        )
                                        self.logCommand(
                                            executablePath: executablePath,
                                            arguments: boomerangArgs)
                                        self.executeFFmpeg(
                                            executablePath: executablePath,
                                            arguments: boomerangArgs,
                                            videoDuration: videoDuration * 2,
                                            completionCallback: { boomerangResult in
                                                switch boomerangResult {
                                                case .success:
                                                    applyWatermarkIfNeeded(boomerangOutputURL)
                                                case .failure(let error):
                                                    cleanup()
                                                    completionCallback(.failure(error))
                                                }
                                            }
                                        )
                                    } else {
                                        applyWatermarkIfNeeded(stabilizedURL)
                                    }
                                }
                            }
                        )
                    }
                }
            )
        }

        if needsBasePass {
            let baseArguments = buildFFmpegCommand(
                request,
                stabilizationTransformURL: nil,
                outputURL: intermediateURL!,
                stabilizationEnabledOverride: false,
                includeOutputSizeLimit: false
            )
            logCommand(executablePath: executablePath, arguments: baseArguments)
            executeFFmpeg(
                executablePath: executablePath,
                arguments: baseArguments,
                videoDuration: videoDuration,
                completionCallback: { baseResult in
                    switch baseResult {
                    case .failure(let error):
                        cleanup()
                        completionCallback(.failure(error))
                    case .success:
                        runStabilization()
                    }
                }
            )
        } else {
            runStabilization()
        }
    }

    private func executeMainAndOptionalLoop(
        request: FFmpegConversionRequest,
        executablePath: String,
        arguments: [String],
        videoDuration: Double,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        if request.loopEnabled {
            let tempOutputURL = makeTemporaryOutputURL(
                in: request.outputURL.deletingLastPathComponent(),
                baseName: request.outputURL.deletingPathExtension().lastPathComponent,
                fileExtension: request.outputURL.pathExtension
            )

            var firstPassArgs = arguments
            if !firstPassArgs.isEmpty {
                firstPassArgs[firstPassArgs.count - 1] = tempOutputURL.path
            }

            logCommand(executablePath: executablePath, arguments: firstPassArgs)
            executeFFmpeg(
                executablePath: executablePath,
                arguments: firstPassArgs,
                videoDuration: videoDuration,
                completionCallback: { firstResult in
                    switch firstResult {
                    case .success:
                        let boomerangArgs = self.buildBoomerangCommand(
                            inputURL: tempOutputURL,
                            outputURL: request.outputURL,
                            format: request.format,
                            quality: request.quality,
                            useGPU: request.useGPU,
                            hasAudio: request.videoInfo?.hasAudio == true
                                && request.speedPercent == 100.0 && !request.dynamicSpeedEnabled,
                            maxOutputSizeMB: request.maxOutputSizeMB,
                            duration: videoDuration * 2
                        )
                        self.logCommand(executablePath: executablePath, arguments: boomerangArgs)
                        self.executeFFmpeg(
                            executablePath: executablePath,
                            arguments: boomerangArgs,
                            videoDuration: videoDuration * 2,
                            completionCallback: { secondResult in
                                try? FileManager.default.removeItem(at: tempOutputURL)
                                completionCallback(secondResult)
                            }
                        )
                    case .failure(let error):
                        try? FileManager.default.removeItem(at: tempOutputURL)
                        completionCallback(.failure(error))
                    }
                }
            )
            return
        }

        executeFFmpeg(
            executablePath: executablePath,
            arguments: arguments,
            videoDuration: videoDuration,
            completionCallback: completionCallback
        )
    }

    private func buildFFmpegCommand(
        _ request: FFmpegConversionRequest,
        stabilizationTransformURL: URL? = nil,
        outputURL: URL? = nil,
        stabilizationEnabledOverride: Bool? = nil,
        includeOutputSizeLimit: Bool = true
    ) -> [String] {
        var videoFilters: [String] = []
        let audioFilters: [String] = []
        var arguments: [String] = []
        var deferredStaticCropFilter: String?
        let usingDynamicCrop =
            request.cropEnable && request.cropDynamicEnabled
            && !request.cropDynamicKeyframes.isEmpty
        let stabilizationEnabled =
            stabilizationEnabledOverride ?? (request.stabilizationLevel != nil)
        
        let sourceDuration = max(0.0, request.videoInfo?.duration ?? 0.0)
        let speedClipStart = request.trimSegments.map { $0.start }.min() ?? 0.0
        let fallbackSpeedEndFromPoints =
            request.dynamicSpeedPoints.map(\.time).max() ?? speedClipStart
        let maxTrimEnd = request.trimSegments.map { $0.end }.max() ?? (sourceDuration > 0 ? sourceDuration : speedClipStart)
        let speedClipEnd = max(sourceDuration, fallbackSpeedEndFromPoints, maxTrimEnd)
        
        let dynamicSpeedFilter =
            request.dynamicSpeedEnabled
            ? SpeedMapPoint.buildDynamicSpeedSetptsFilter(
                points: request.dynamicSpeedPoints,
                clipStart: speedClipStart,
                clipEnd: speedClipEnd
            )
            : nil
        let speed = request.speedPercent / 100.0
        let hasStaticSpeedChange = request.speedPercent != 100.0 && speed > 0
        let canKeepAudio =
            request.videoInfo?.hasAudio == true && request.speedPercent == 100.0
            && !request.dynamicSpeedEnabled
        var hasMergedSetpts = false
        
        arguments += ["-i", request.inputURL.path]

        var finalVideoPad = "[0:v]"
        var finalAudioPad = canKeepAudio ? "[0:a]" : ""
        var filterComplexArgs: [String] = []

        if !request.trimSegments.isEmpty {
            let segments = request.trimSegments.sorted()
            let n = segments.count
            
            var complexGraph = ""
            // Video split
            complexGraph += "[0:v]split=\(n)"
            for i in 0..<n { complexGraph += "[v_in\(i)]" }
            complexGraph += ";"
            
            // Audio split
            if canKeepAudio {
                complexGraph += "[0:a]asplit=\(n)"
                for i in 0..<n { complexGraph += "[a_in\(i)]" }
                complexGraph += ";"
            }
            
            // Trims
            var concatInputs = ""
            for (i, seg) in segments.enumerated() {
                complexGraph += "[v_in\(i)]trim=start=\(dot(seg.start)):end=\(dot(seg.end)),setpts=PTS-STARTPTS[v_out\(i)];"
                if canKeepAudio {
                    complexGraph += "[a_in\(i)]atrim=start=\(dot(seg.start)):end=\(dot(seg.end)),asetpts=PTS-STARTPTS[a_out\(i)];"
                }
                concatInputs += "[v_out\(i)]"
                if canKeepAudio { concatInputs += "[a_out\(i)]" }
            }
            
            // Concat
            complexGraph += "\(concatInputs)concat=n=\(n):v=1:a=\(canKeepAudio ? 1 : 0)[v_concat]"
            finalVideoPad = "[v_concat]"
            if canKeepAudio {
                complexGraph += "[a_concat];"
                finalAudioPad = "[a_concat]"
            } else {
                complexGraph += ";"
            }
            
            filterComplexArgs.append(complexGraph)
        }

        if let pixFmt = request.videoInfo?.colorInfo.pixelFormat, !pixFmt.isEmpty {
            arguments += ["-pix_fmt", pixFmt]
        }
        
        // Resolución
        if request.resolution != .original {
            let resolutionValue = request.resolution.ffmpegParam
            videoFilters.append("scale=\(resolutionValue):force_original_aspect_ratio=decrease")
            print("📏 Escalando a: \(resolutionValue)")
        }
        
        // crop
        if request.cropEnable {
            if request.cropDynamicEnabled, let videoInfo = request.videoInfo {
                let clipStart = request.trimSegments.map { $0.start }.min() ?? 0.0
                let clipEnd = request.trimSegments.map { $0.end }.max() ?? sourceDuration
                let clipDuration = max(0.0, clipEnd - clipStart)
                let setptsFilter =
                    dynamicSpeedFilter
                    ?? (hasStaticSpeedChange
                        ? SpeedMapPoint.buildSpeedSetptsFilter(
                            duration: clipDuration, speed: speed, resetPTSWhenNoSpeed: true)
                        : "setpts=PTS-STARTPTS")

                if let dynamicCrop = CropDynamicKeyframe.buildDynamicCropFilter(
                    keyframes: request.cropDynamicKeyframes,
                    sourceDuration: sourceDuration,
                    trimStart: clipStart,
                    trimEnd: clipEnd,
                    setptsFilter: setptsFilter
                ) {
                    videoFilters.append(dynamicCrop)
                    hasMergedSetpts = true
                }
            } else if let cropRect = request.cropRec, let videoSize = request.videoInfo?.videoSize {
                let x = Int(cropRect.origin.x * videoSize.width)
                let y = Int(cropRect.origin.y * videoSize.height)
                let w = Int(cropRect.size.width * videoSize.width)
                let h = Int(cropRect.size.height * videoSize.height)
                
                deferredStaticCropFilter = "crop=\(w):\(h):\(x):\(y)"
            }
        }

        if let stabilizationLevel = request.stabilizationLevel, let stabilizationTransformURL, stabilizationEnabled {
            let filter = stabilizationLevel.buildTransformFilter(
                transformsPath: stabilizationTransformURL.path
            )
            videoFilters.append(filter)
        }

        if let deferredStaticCropFilter {
            videoFilters.append(deferredStaticCropFilter)
        }
        
        if let colorFilter = request.colorAdjustments.toFFmpegFilter() {
            videoFilters.append(colorFilter)
        }
        
        if let fpsFilters = request.frameRateSettings.toFFmpegFilter() {
            videoFilters.append(fpsFilters)
        }
        
        if !hasMergedSetpts {
            if let dynamicSpeedFilter {
                videoFilters.append(dynamicSpeedFilter)
            } else if hasStaticSpeedChange {
                let duration = resolvedOutputDuration(request)
                videoFilters.append(
                    SpeedMapPoint.buildSpeedSetptsFilter(
                        duration: duration, speed: speed, resetPTSWhenNoSpeed: false))
            }
        }
        
        if filterComplexArgs.isEmpty {
            if !videoFilters.isEmpty {
                arguments += ["-vf", videoFilters.joined(separator: ",")]
            }
            if !audioFilters.isEmpty {
                arguments += ["-af", audioFilters.joined(separator: ",")]
            }
        } else {
            var graph = filterComplexArgs.joined(separator: " ")
            if !videoFilters.isEmpty {
                graph += " \(finalVideoPad)\(videoFilters.joined(separator: ","))[v_final]"
                finalVideoPad = "[v_final]"
            }
            if !audioFilters.isEmpty && canKeepAudio {
                graph += " \(finalAudioPad)\(audioFilters.joined(separator: ","))[a_final]"
                finalAudioPad = "[a_final]"
            }
            arguments += ["-filter_complex", graph]
            arguments += ["-map", finalVideoPad]
            if canKeepAudio {
                arguments += ["-map", finalAudioPad]
            }
        }

        let (videoCodec, audioCodec) = codecForFormat(
            request.format, useGPU: request.useGPU, maxOutputSizeMB: request.maxOutputSizeMB)

        var finalVideoCodec = videoCodec
        var finalAudioCodec = audioCodec
        
        if request.superCompression {
            finalVideoCodec = request.superCompressionGPU ? "hevc_videotoolbox" : "libx265"
            finalAudioCodec = "aac"
            arguments += ["-tag:v", "hvc1"]
        }

        arguments += ["-c:v", finalVideoCodec]

        if request.format == .webm {
            arguments += [
                "-b:v", "0",
                "-quality", "good",
                "-cpu-used", "0",
                "-row-mt", "1",
                "-tile-columns", "2",
                "-frame-parallel", "1",
                "-auto-alt-ref", "1",
                "-lag-in-frames", "25",
            ]
        } else if request.format == .av1 {
            arguments += [
                "-preset", "4",
                "-svtav1-params", "scd=1",
                "-svtav1-params", "scm=0",
            ]
        }

        if request.superCompression {
            if request.superCompressionGPU {
                arguments += ["-q:v", "65", "-profile:v", "main10"]
            } else {
                arguments += ["-crf", "28", "-preset", "slow"]
            }
        } else if !includeOutputSizeLimit || request.maxOutputSizeMB == nil {
            arguments += qualityArguments(videoCodec: finalVideoCodec, crf: request.quality)
        }

        if request.videoInfo?.hasAudio == true && request.speedPercent == 100.0
            && !request.dynamicSpeedEnabled
        {
            arguments += ["-c:a", finalAudioCodec]
            let audioBitrate = request.superCompression ? "96k" : "128k"
            arguments += ["-b:a", audioBitrate]
        } else {
            arguments += ["-an"]
        }

        if let primaries = request.videoInfo?.colorInfo.validFFmpegPrimaries(), !primaries.isEmpty {
            arguments += ["-color_primaries", primaries]
        }
        if let trc = request.videoInfo?.colorInfo.validFFmpegTrc(), !trc.isEmpty {
            arguments += ["-color_trc", trc]
        }
        if let colorspace = request.videoInfo?.colorInfo.validFFmpegColorspace(),
            !colorspace.isEmpty
        {
            arguments += ["-colorspace", colorspace]
        }
        if let range = request.videoInfo?.colorInfo.validFFmpegRange(), !range.isEmpty {
            arguments += ["-color_range", range]
        }
        if includeOutputSizeLimit {
            let duration = resolvedOutputDuration(request)
            arguments += outputSizeLimitArguments(
                maxOutputSizeMB: request.maxOutputSizeMB, duration: duration, hasAudio: canKeepAudio
            )
        }
        arguments += [
            "-progress", "pipe:1",
            "-y",
            (outputURL ?? request.outputURL).path,
        ]

        print("🎬 FFmpeg Command:")
        print("  \(arguments.joined(separator: " "))")
        
        return arguments
    }

    private func dot(_ value: Double) -> String {
        let invariant = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
        return invariant.replacingOccurrences(of: ",", with: ".")
    }

    private func resolvedClipStart(_ request: FFmpegConversionRequest, sourceDuration: Double)
        -> Double
    {
        let minTrimStart = request.trimSegments.map { $0.start }.min()
        if sourceDuration <= 0 {
            return max(0.0, minTrimStart ?? 0.0)
        }
        let rawStart = max(0.0, minTrimStart ?? 0.0)
        return min(rawStart, sourceDuration)
    }

    private func resolvedClipEnd(
        _ request: FFmpegConversionRequest, sourceDuration: Double, start: Double
    ) -> Double {
        let rawEnd: Double
        let maxTrimEnd = request.trimSegments.map { $0.end }.max()
        if let trimEnd = maxTrimEnd {
            rawEnd = max(0.0, trimEnd)
        } else if sourceDuration > 0 {
            rawEnd = sourceDuration
        } else {
            rawEnd = start
        }
        
        if sourceDuration > 0 {
            return min(max(rawEnd, start), sourceDuration)
        }
        
        return max(rawEnd, start)
    }

    private func resolvedClipBounds(_ request: FFmpegConversionRequest) -> (
        start: Double, end: Double
    )? {
        guard !request.trimSegments.isEmpty else { return nil }
        
        let sourceDuration = max(0.0, request.videoInfo?.duration ?? 0.0)
        let start = resolvedClipStart(request, sourceDuration: sourceDuration)
        let end = resolvedClipEnd(request, sourceDuration: sourceDuration, start: start)
        
        return (start, end)
    }
    
    private func resolvedOutputDuration(_ request: FFmpegConversionRequest) -> Double {
        if !request.trimSegments.isEmpty {
            return request.trimSegments.reduce(0.0) { $0 + max(0.0, $1.end - $1.start) }
        }
        return max(0.0, request.videoInfo?.duration ?? 0.0)
    }

    private func buildStabilizationDetectCommand(
        inputURL: URL,
        transformsURL: URL,
        level: VideoStabilizationLevel
    ) -> [String] {
        var arguments: [String] = [
            "-i", inputURL.path,
        ]
        let detectFilter = level.buildDetectFilter(
            transformsPath: transformsURL.path
        )
        arguments += [
            "-vf", detectFilter,
            "-an",
            "-f", "null",
            "-"
        ]

        return arguments
    }

    private func buildStabilizationTransformCommand(
        request: FFmpegConversionRequest,
        stabilizationLevel: VideoStabilizationLevel,
        inputURL: URL,
        outputURL: URL,
        transformsURL: URL,
        includeOutputSizeLimit: Bool
    ) -> [String] {
        var arguments: [String] = [
            "-i", inputURL.path,
        ]

        let transformFilter = stabilizationLevel.buildTransformFilter(
            transformsPath: transformsURL.path
        )
        arguments += ["-vf", transformFilter]

        let (videoCodec, audioCodec) = codecForFormat(
            request.format, useGPU: request.useGPU, maxOutputSizeMB: request.maxOutputSizeMB)
        arguments += ["-c:v", videoCodec]

        if videoCodec == "h264_videotoolbox" && includeOutputSizeLimit
            && request.maxOutputSizeMB != nil
        {
            arguments += ["-profile:v", "high"]
        }

        if request.format == .webm {
            arguments += [
                "-b:v", "0",
                "-quality", "good",
                "-cpu-used", "0",
                "-row-mt", "1",
                "-tile-columns", "2",
                "-frame-parallel", "1",
                "-auto-alt-ref", "1",
                "-lag-in-frames", "25",
            ]
        } else if request.format == .mp4 {
            if videoCodec != "h264_videotoolbox" {
                arguments += ["-preset", "veryslow"]
            }
        } else if request.format == .av1 {
            arguments += [
                "-preset", "4",
                "-svtav1-params", "scd=1",
                "-svtav1-params", "scm=0",
            ]
        }

        if !includeOutputSizeLimit || request.maxOutputSizeMB == nil {
            arguments += qualityArguments(videoCodec: videoCodec, crf: request.quality)
        }

        if request.videoInfo?.hasAudio == true && request.speedPercent == 100.0
            && !request.dynamicSpeedEnabled
        {
            arguments += ["-c:a", audioCodec]
            arguments += ["-b:a", "128k"]
        } else {
            arguments += ["-an"]
        }

        if let primaries = request.videoInfo?.colorInfo.validFFmpegPrimaries(), !primaries.isEmpty {
            arguments += ["-color_primaries", primaries]
        }
        if let trc = request.videoInfo?.colorInfo.validFFmpegTrc(), !trc.isEmpty {
            arguments += ["-color_trc", trc]
        }
        if let colorspace = request.videoInfo?.colorInfo.validFFmpegColorspace(), !colorspace.isEmpty {
            arguments += ["-colorspace", colorspace]
        }
        if let range = request.videoInfo?.colorInfo.validFFmpegRange(), !range.isEmpty {
            arguments += ["-color_range", range]
        }
        if includeOutputSizeLimit {
            let duration = resolvedOutputDuration(request)
            let hasAudio =
                request.videoInfo?.hasAudio == true && request.speedPercent == 100.0
                && !request.dynamicSpeedEnabled
            arguments += outputSizeLimitArguments(
                maxOutputSizeMB: request.maxOutputSizeMB, duration: duration, hasAudio: hasAudio)
        }

        arguments += [
            "-progress", "pipe:1",
            "-y",
            outputURL.path
        ]

        return arguments
    }

    private func logCommand(executablePath: String, arguments: [String]) {
        print("🔹 Ejecutando ffmpeg:")
        print("    \(executablePath) \\")
        for arg in arguments {
            print("      \"\(arg)\" \\")
        }
    }

    private func buildWatermarkOverlayCommand(
        inputURL: URL,
        watermarkURL: URL,
        outputURL: URL,
        format: VideoFormat,
        quality: Int,
        useGPU: Bool,
        maxOutputSizeMB: Int?
    ) -> [String] {
        var arguments: [String] = [
            "-i", inputURL.path,
            "-i", watermarkURL.path,
            "-filter_complex", "[0:v][1:v]overlay=0:0",
            "-map", "0:a?",
        ]

        let (videoCodec, audioCodec) = codecForFormat(
            format, useGPU: useGPU, maxOutputSizeMB: maxOutputSizeMB)
        arguments += ["-c:v", videoCodec]
        arguments += ["-c:a", audioCodec]
        arguments += ["-b:a", "128k"]

        if maxOutputSizeMB == nil {
            arguments += qualityArguments(videoCodec: videoCodec, crf: quality)
        }

        arguments += [
            "-progress", "pipe:1",
            "-y",
            outputURL.path,
        ]

        return arguments
    }

    private func buildBoomerangCommand(
        inputURL: URL,
        outputURL: URL,
        format: VideoFormat,
        quality: Int,
        useGPU: Bool,
        hasAudio: Bool,
        maxOutputSizeMB: Int?,
        duration: Double
    ) -> [String] {
        var arguments: [String] = ["-i", inputURL.path]
        let (videoCodec, audioCodec) = codecForFormat(
            format, useGPU: useGPU, maxOutputSizeMB: maxOutputSizeMB)

        if hasAudio {
            arguments += [
                "-filter_complex",
                "[0:v]reverse[vrev];[0:a]areverse[arev];[0:v][0:a][vrev][arev]concat=n=2:v=1:a=1[v][a]",
                "-map", "[v]",
                "-map", "[a]",
                "-c:v", videoCodec,
                "-c:a", audioCodec,
                "-b:a", "128k"
            ]
        } else {
            arguments += [
                "-filter_complex",
                "[0:v]reverse[vrev];[0:v][vrev]concat=n=2:v=1:a=0[v]",
                "-map", "[v]",
                "-c:v", videoCodec
            ]
        }

        if maxOutputSizeMB == nil {
            arguments += qualityArguments(videoCodec: videoCodec, crf: quality)
        }
        arguments += outputSizeLimitArguments(
            maxOutputSizeMB: maxOutputSizeMB, duration: duration, hasAudio: hasAudio)
        arguments += [
            "-progress", "pipe:1",
            "-y",
            outputURL.path,
        ]

        return arguments
    }

    private func makeTemporaryOutputURL(in directory: URL, baseName: String, fileExtension: String)
        -> URL
    {
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(baseName)_tmp_\(timestamp).\(fileExtension)"
        return directory.appendingPathComponent(filename)
    }

    private func makeTemporaryTransformURL(in directory: URL, baseName: String) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(baseName)_stab_\(timestamp).trf"
        return directory.appendingPathComponent(filename)
    }

    private func codecForFormat(_ format: VideoFormat, useGPU: Bool, maxOutputSizeMB: Int?) -> (
        video: String, audio: String
    ) {
        var videoCodec = "h264_videotoolbox"

        if format == .mp4, maxOutputSizeMB != nil {
            videoCodec = "libx265"
        }

        switch format {
        case .mp4:
            return (videoCodec, "aac")
        case .mkv:
            return (videoCodec, "aac")
        case .mov:
            return (videoCodec, "aac")
        case .av1:
            return ("libsvtav1", "aac")
        case .webm:
            return ("libvpx-vp9", "libopus")
        }
    }

    private func qualityArguments(videoCodec: String, crf: Int) -> [String] {
        if videoCodec == "h264_videotoolbox" {
            // Map CRF 1-51 (lower is better) to q:v 1-100 (higher is better)
            let clampedCrf = max(1, min(51, crf))
            let normalized = (51.0 - Double(clampedCrf)) / 50.0
            let qv = Int(round(normalized * 99.0 + 1.0))
            return ["-q:v", "\(qv)"]
        }
        return ["-crf", "\(crf)"]
    }

    private func outputSizeLimitArguments(maxOutputSizeMB: Int?, duration: Double, hasAudio: Bool)
        -> [String]
    {
        guard let maxOutputSizeMB = maxOutputSizeMB, maxOutputSizeMB > 0 else { return [] }

        let limitBytes = Double(maxOutputSizeMB) * 1024.0 * 1024.0
        var args = ["-fs", "\(Int64(limitBytes))"]

        if duration > 0 {
            let audioBitrateKbps = hasAudio ? 64.0 : 0.0


            let totalBitrateKbps = (limitBytes / duration * 8.0) / 1024.0

            // Subtract audio bitrate and leave 5% margin for container overhead
            let videoBitrateKbps = Int((totalBitrateKbps * 0.95) - audioBitrateKbps)

            if videoBitrateKbps > 0 {
                args += [
                    "-b:v", "\(videoBitrateKbps)k",
                    "-maxrate:v", "\(videoBitrateKbps)k",
                    "-bufsize:v", "\(videoBitrateKbps * 2)k",
                ]
            } else {
                print("⚠️ Size constraints are too tight for the given duration!")
            }
        }

        return args
    }

    private func executeFFmpeg(
        executablePath: String,
        arguments: [String],
        videoDuration: TimeInterval,
        reportProgress: Bool = true,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        self.process = process

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        var stdoutBuffer = ""
        var stderrBuffer = ""
        var finished = false

        func finish(_ result: Result<URL, FFmpegError>) {
            guard !finished else { return }
            finished = true

            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil

            DispatchQueue.main.async { [weak self] in
                if reportProgress, case .success = result {
                    self?.progressCallback?(100.0)
                }
                completionCallback(result)
            }
        }

        // stdout: progreso
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }  // EOF

            if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                stdoutBuffer += chunk

                // procesar por líneas completas (key=value)
                while let range = stdoutBuffer.range(of: "\n") {
                    let line = String(stdoutBuffer[..<range.lowerBound]).trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    stdoutBuffer.removeSubrange(..<range.upperBound)

                    if !line.isEmpty {
                        if reportProgress {
                            self?.parseFFmpegOutput(line + "\n", videoDuration: videoDuration)
                        }

                        if line.contains("progress=end") {
                            print("✅ FFmpeg completado por progress=end")
                            finish(.success(URL(fileURLWithPath: arguments.last ?? "")))
                            return
                        }
                    }
                }
            }
        }

        // stderr: logs (banner, warnings, errores)
        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }  // EOF
            if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                stderrBuffer += chunk
            }
        }

        process.terminationHandler = { _ in
            // Importante: al terminar, imprime stderr completo si existe
            if !stderrBuffer.isEmpty {
                print("📥 FFmpeg stderr completo:\n\(stderrBuffer)")
            }

            print("🔚 FFmpeg finalizado - Status: \(process.terminationStatus)")

            if finished { return }  // ya finalizó por progress=end

            if process.terminationStatus == 0 {
                self.lastErrorLog = nil
                finish(.success(URL(fileURLWithPath: arguments.last ?? "")))
            } else {
                self.lastErrorLog = stderrBuffer.isEmpty ? nil : stderrBuffer
                finish(.failure(.conversionFailed))
            }
        }

        do {
            try process.run()
            print("▶️ FFmpeg iniciado (PID: \(process.processIdentifier))")
        } catch {
            print("❌ Error al iniciar FFmpeg: \(error)")
            self.lastErrorLog = error.localizedDescription
            finish(.failure(.executionFailed(error.localizedDescription)))
        }
    }

    private func parseFFmpegOutput(_ output: String, videoDuration: TimeInterval) {
        // output puede ser una o varias líneas key=value
        let lines = output.split(whereSeparator: \.isNewline)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // 1) progreso por out_time_ms (en realidad microsegundos)
            if line.hasPrefix("out_time_ms=") {
                let value = line.dropFirst("out_time_ms=".count)
                if let outTimeUs = Double(value) {
                    let duration = max(0.001, videoDuration)  // evita div/0
                    let currentSeconds = outTimeUs / 1_000_000.0

                    let ratio = min(0.999, max(0.0, currentSeconds / duration))
                    let percent = ratio * 100.0

                    DispatchQueue.main.async {
                        self.progressCallback?(percent)
                    }
                }
                continue
            }

            // 2) (Opcional) también soportar out_time_us
            if line.hasPrefix("out_time_us=") {
                let value = line.dropFirst("out_time_us=".count)
                if let outTimeUs = Double(value) {
                    let duration = max(0.001, videoDuration)
                    let currentSeconds = outTimeUs / 1_000_000.0

                    let ratio = min(0.999, max(0.0, currentSeconds / duration))
                    let percent = ratio * 100.0

                    DispatchQueue.main.async {
                        self.progressCallback?(percent)
                    }
                }
                continue
            }

            // 3) finalización
            if line == "progress=end" {
                DispatchQueue.main.async {
                    self.progressCallback?(100.0)
                }
                continue
            }
        }
    }

    private func getDuration(of videoURL: URL, completion: @escaping (TimeInterval) -> Void) {
        let ffprobePath = findFFprobe()
        let path = videoURL.path

        let args = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path
        ]

        print("🔹 Ejecutando ffprobe:")
        print("    \(ffprobePath) \\")
        for arg in args {
            print("      \"\(arg)\" \\")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = args
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        DispatchQueue.global().async {
            do {
                try process.run()
            } catch {
                print("❌ Error al ejecutar ffprobe: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(0) }
                return
            }

            process.waitUntilExit()

            let outHandle = outPipe.fileHandleForReading
            let data = outHandle.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let outString = String( data: data, encoding: .utf8) {
                print("📤 [ffprobe stdout]:\n\(outString)")
            }
            if let errString = String( data: errData, encoding: .utf8), !errString.isEmpty {
                print("📥 [ffprobe stderr]:\n\(errString)")
            }

            guard process.terminationStatus == 0,
                  let output = String( data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let duration = Double(output) else {
                print("❌ ffprobe terminó con status \(process.terminationStatus) o salida inválida")
                DispatchQueue.main.async { completion(0) }
                return
            }
            
            print("⏱️ Duración detectada por ffprobe: \(duration) segundos")
            DispatchQueue.main.async {
                completion(duration)
            }
        }
    }

    private func supportsHardwareEncoding() -> Bool {
        let testArgs = ["-f", "lavfi", "-i", "testsrc=duration=1", "-f", "null", "-"]
        let process = Process()
        guard let ffmpegPath = resolvedFFmpegPath() else {
            return false
        }
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = testArgs + ["-c:v", "hevc_videotoolbox"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private struct MergeInputInfo {
        let url: URL
        let duration: Double
        let hasAudio: Bool
        let width: Int
        let height: Int
    }

    /// Merge multiple video files into a single output file.
    /// Uses filter_complex with scale+pad to normalise resolutions and concat to join them.
    /// Automatically detects which inputs have audio and handles all combinations.
    func mergeVideos(
        urls: [URL],
        outputURL: URL,
        progressCallback: @escaping (Double) -> Void,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        self.progressCallback = progressCallback

        guard let ffmpegPath = resolvedFFmpegPath(),
              FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
            completionCallback(.failure(.ffmpegNotFound))
            return
        }

        guard urls.count > 1 else {
            completionCallback(.failure(.conversionFailed))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let inputs = self.probeMergeInputsSync(for: urls)
            let totalDuration = inputs.reduce(0.0) { $0 + $1.duration }
            let arguments = self.buildMergeVideosCommand(inputs: inputs, outputURL: outputURL)
            self.logCommand(executablePath: ffmpegPath, arguments: arguments)
            self.executeFFmpeg(
                executablePath: ffmpegPath,
                arguments: arguments,
                videoDuration: max(0.001, totalDuration),
                completionCallback: completionCallback
            )
        }
    }

    /// Builds the FFmpeg arguments for merging N videos using filter_complex concat.
    /// All inputs are scaled + padded to the largest resolution found among inputs.
    /// Handles three audio scenarios: all have audio, none have audio, or mixed.
    private func buildMergeVideosCommand(inputs: [MergeInputInfo], outputURL: URL) -> [String] {
        let n = inputs.count
        var arguments: [String] = []

        // Determine the target canvas from the largest width and height across inputs
        let maxW = max(2, inputs.map { $0.width }.max() ?? 1920)
        let maxH = max(2, inputs.map { $0.height }.max() ?? 1080)
        // Ensure even dimensions (required by most codecs)
        let targetW = maxW % 2 == 0 ? maxW : maxW + 1
        let targetH = maxH % 2 == 0 ? maxH : maxH + 1
        print("📐 Merge target resolution: \(targetW)x\(targetH)")

        for input in inputs {
            arguments += ["-i", input.url.path]
        }

        let noneHaveAudio = inputs.allSatisfy { !$0.hasAudio }
        let includeAudio = !noneHaveAudio

        // For the mixed case, add anullsrc inputs to generate silence
        // for videos that lack audio. Track which ffmpeg input index
        // provides the audio for each original input.
        var audioInputIndex: [Int: Int] = [:]   // original index → ffmpeg input index for audio
        var nextInputIndex = n

        if includeAudio {
            for (i, input) in inputs.enumerated() {
                if input.hasAudio {
                    audioInputIndex[i] = i
                } else {
                    // Add a silent audio source whose duration matches this video
                    arguments += [
                        "-f", "lavfi",
                        "-t", String(format: "%.3f", input.duration),
                        "-i", "anullsrc=r=44100:cl=stereo"
                    ]
                    audioInputIndex[i] = nextInputIndex
                    nextInputIndex += 1
                }
            }
        }

        var filterGraph = ""
        for i in 0..<n {
            filterGraph += "[\(i):v]scale=\(targetW):\(targetH):force_original_aspect_ratio=decrease,pad=\(targetW):\(targetH):(ow-iw)/2:(oh-ih)/2,setsar=1[v\(i)];"
        }

        for i in 0..<n {
            filterGraph += "[v\(i)]"
            if includeAudio {
                let aIdx = audioInputIndex[i]!
                filterGraph += "[\(aIdx):a]"
            }
        }
        filterGraph += "concat=n=\(n):v=1:a=\(includeAudio ? 1 : 0)"
        if includeAudio {
            filterGraph += "[outv][outa]"
        } else {
            filterGraph += "[outv]"
        }

        arguments += ["-filter_complex", filterGraph]
        arguments += ["-map", "[outv]"]
        if includeAudio {
            arguments += ["-map", "[outa]"]
        }
        arguments += ["-c:v", "h264_videotoolbox"]
        arguments += ["-q:v", "65"]
        if includeAudio {
            arguments += ["-c:a", "aac", "-b:a", "128k"]
        }
        arguments += ["-progress", "pipe:1", "-y", outputURL.path]

        return arguments
    }

    private func probeMergeInputsSync(for urls: [URL]) -> [MergeInputInfo] {
        let ffprobePath = findFFprobe()
        var results: [MergeInputInfo] = []

        for url in urls {
            let output = probeValueSync(
                ffprobePath: ffprobePath,
                arguments: [
                    "-v", "error",
                    "-show_entries", "format=duration:stream=width,height,codec_type",
                    "-of", "json",
                    url.path
                ]
            )

            var duration: Double = 0
            var width: Int = 0
            var height: Int = 0
            var hasAudio = false

            if let json = output,
               let data = json.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Duration from format
                if let format = root["format"] as? [String: Any],
                   let durStr = format["duration"] as? String,
                   let dur = Double(durStr) {
                    duration = dur
                }

                // Streams: video resolution + audio detection
                if let streams = root["streams"] as? [[String: Any]] {
                    for stream in streams {
                        let codecType = stream["codec_type"] as? String ?? ""
                        if codecType == "video" && width == 0 {
                            width = stream["width"] as? Int ?? 0
                            height = stream["height"] as? Int ?? 0
                        }
                        if codecType == "audio" {
                            hasAudio = true
                        }
                    }
                }
            }

            results.append(MergeInputInfo(url: url, duration: duration, hasAudio: hasAudio, width: width, height: height))
            print("🔍 Merge input: \(url.lastPathComponent) — \(width)x\(height), duration: \(duration)s, audio: \(hasAudio)")
        }

        return results
    }

    private func probeValueSync(ffprobePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func cancel() {
        print("⏹️ Cancelando proceso ffmpeg...")
        process?.terminate()
        process = nil
    }
    
    
    func isFfmpegInstalled() -> Bool {
        guard let path = resolvedFFmpegPath() else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
    
    func resolvedFFmpegPath() -> String? {
        // Buscar en Bundle (EMBEDDED)
        if let bundlePath = Bundle.main.path(forResource: "ffmpeg", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            print("✅ FFmpeg encontrado en Bundle: \(bundlePath)")
            return bundlePath
        }
        
        // Fallback rutas sistema
        let systemPaths = ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
        for path in systemPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                print("✅ FFmpeg en sistema: \(path)")
                return path
            }
        }

        return nil
    }

    private func findFFprobe() -> String {
        // Buscar en Bundle (EMBEDDED)
        if let bundlePath = Bundle.main.path(forResource: "ffprobe", ofType: nil) {
            print("✅ FFprobe encontrado en Bundle: \(bundlePath)")
            return bundlePath
        }
        
        // Fallback rutas sistema
        let systemPaths = ["/usr/local/bin/ffprobe", "/opt/homebrew/bin/ffprobe"]
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("✅ FFprobe en sistema: \(path)")
                return path
            }
        }
        
        fatalError("❌ FFprobe no encontrado ni en Bundle ni en sistema")
    }

}


enum FFmpegError: LocalizedError {
    case ffmpegNotFound
    case ffprobeNotFound
    case cannotGetDuration
    case conversionFailed
    case executionFailed(String)
    
    var errorDescription: String? {
        func localized(_ key: String, fallback: String) -> String {
            let userDefaults = UserDefaults.standard
            if let data = userDefaults.data(forKey: "selectedLanguage"),
               let language = try? JSONDecoder().decode(AppLanguage.self, from: data),
               let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return NSLocalizedString(key, tableName: nil, bundle: bundle, value: fallback, comment: "")
            }
            return NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
        }
        
        switch self {
        case .ffmpegNotFound:
            return localized("error.ffmpeg_not_found", fallback: "FFmpeg is not installed. Install with: brew install ffmpeg")
        case .ffprobeNotFound:
            return localized("error.ffprobe_not_found", fallback: "FFprobe is not available")
        case .cannotGetDuration:
            return localized("error.cannot_get_duration", fallback: "Unable to get video duration")
        case .conversionFailed:
            return localized("error.conversion_failed", fallback: "Video conversion failed")
        case .executionFailed(let reason):
            let format = localized("error.execution_failed_format", fallback: "Error executing FFmpeg: %@")
            return String(format: format, reason)
        }
    }
}
