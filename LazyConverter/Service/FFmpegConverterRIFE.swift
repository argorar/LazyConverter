import Foundation
import CoreGraphics

extension FFmpegConverter {
    
    // MARK: - Progress mapping
    
    /// Maps a local progress (0-100) to a segment of the global progress range.
    /// For example, mappedProgress(50, rangeStart: 20, rangeEnd: 30) returns 25.
    private func rifeMapProgress(_ localPercent: Double, rangeStart: Double, rangeEnd: Double) -> Double {
        let clamped = min(max(localPercent, 0), 100)
        return rangeStart + (clamped / 100.0) * (rangeEnd - rangeStart)
    }
    
    // RIFE pipeline progress weights (total = 100%)
    // Stage 1: Pre-encode           →  0% – 20%
    // Stage 2: Extract frames       → 20% – 30%
    // Stage 3: RIFE interpolation   → 30% – 70%
    // Stage 4: Assemble frames      → 70% – 85%
    // Stage 5: Final pass           → 85% – 100%
    
    private func requiresPreRifePass(request: FFmpegConversionRequest) -> Bool {
        return request.resolution != .original ||
               request.speedPercent != 100.0 ||
               request.dynamicSpeedEnabled ||
               request.loopEnabled ||
               !request.trimSegments.isEmpty ||
               request.cropEnable ||
               request.colorAdjustments != .default ||
               request.superCompression
    }
    
    func runRifeInterpolationPipeline(
        request: FFmpegConversionRequest,
        rifeExecutablePath: String,
        ffmpegExecutablePath: String,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        let outputDir = request.outputURL.deletingLastPathComponent()
        let baseName = request.outputURL.deletingPathExtension().lastPathComponent
        
        let prerifeURL = makeTemporaryOutputURL(in: outputDir, baseName: "\(baseName)_prerife", fileExtension: request.outputURL.pathExtension)
        let needsPreRife = requiresPreRifePass(request: request)
        
        // Save the original progress callback to use throughout the pipeline
        let originalProgressCallback = request.progressCallback
        
        var baseRequest = request
        baseRequest = FFmpegConversionRequest(
            inputURL: request.inputURL,
            outputURL: prerifeURL,
            format: request.format,
            resolution: request.resolution,
            quality: 18, // High quality intermediate
            speedPercent: request.speedPercent,
            maxOutputSizeMB: nil,
            dynamicSpeedEnabled: request.dynamicSpeedEnabled,
            dynamicSpeedPoints: request.dynamicSpeedPoints,
            useGPU: request.useGPU,
            stabilizationLevel: nil, // Do stabilization later
            loopEnabled: false, // Do loop later
            superCompression: false,
            superCompressionGPU: false,
            trimSegments: request.trimSegments,
            videoInfo: request.videoInfo,
            cropEnable: request.cropEnable,
            cropDynamicEnabled: request.cropDynamicEnabled,
            cropDynamicKeyframes: request.cropDynamicKeyframes,
            cropRec: request.cropRec,
            colorAdjustments: request.colorAdjustments,
            frameRateSettings: FrameRateSettings(mode: .keep, targetFrameRate: .fps60, useRifeGPU: false), // turn off internal interpolation
            watermarkConfig: nil, // Do watermark later
            progressCallback: request.progressCallback,
            completionCallback: request.completionCallback,
            rifeExecutablePath: nil
        )
        
        if needsPreRife {
            // Stage 1: Pre-encode (0% – 20%)
            // Override the converter's progress callback to map to stage 1 range
            self.setProgressCallback { localPercent in
                let mapped = self.rifeMapProgress(localPercent, rangeStart: 0, rangeEnd: 20)
                DispatchQueue.main.async {
                    originalProgressCallback(mapped)
                }
            }
            
            let prerifeArgs = buildFFmpegCommand(
                baseRequest,
                stabilizationTransformURL: nil,
                outputURL: prerifeURL,
                stabilizationEnabledOverride: false,
                includeOutputSizeLimit: false
            )
            
            logCommand(executablePath: ffmpegExecutablePath, arguments: prerifeArgs)
            executeFFmpeg(executablePath: ffmpegExecutablePath, arguments: prerifeArgs, videoDuration: resolvedOutputDuration(baseRequest)) { prerifeResult in
                switch prerifeResult {
                case .failure(let error):
                    completionCallback(.failure(error))
                case .success:
                    self.processRifeWithRAMDisk(
                        request: request,
                        prerifeURL: prerifeURL,
                        needsPreRife: true,
                        rifeExecutablePath: rifeExecutablePath,
                        ffmpegExecutablePath: ffmpegExecutablePath,
                        originalProgressCallback: originalProgressCallback,
                        completionCallback: completionCallback
                    )
                }
            }
        } else {
            // Skip Stage 1, report 20% immediately
            DispatchQueue.main.async {
                originalProgressCallback(self.rifeMapProgress(100, rangeStart: 0, rangeEnd: 20))
            }
            self.processRifeWithRAMDisk(
                request: request,
                prerifeURL: request.inputURL,
                needsPreRife: false,
                rifeExecutablePath: rifeExecutablePath,
                ffmpegExecutablePath: ffmpegExecutablePath,
                originalProgressCallback: originalProgressCallback,
                completionCallback: completionCallback
            )
        }
    }
    
    private func processRifeWithRAMDisk(
        request: FFmpegConversionRequest,
        prerifeURL: URL,
        needsPreRife: Bool,
        rifeExecutablePath: String,
        ffmpegExecutablePath: String,
        originalProgressCallback: @escaping (Double) -> Void,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        let ramDiskName = "LazyRAMDisk_\(UUID().uuidString.prefix(6))"
        let ramDiskPath = "/Volumes/\(ramDiskName)"
        let inputFramesDir = "\(ramDiskPath)/input"
        let outputFramesDir = "\(ramDiskPath)/output"
        
        let cleanupAll: () -> Void = {
            let task = Process()
            task.launchPath = "/usr/sbin/diskutil"
            task.arguments = ["unmount", "force", ramDiskPath]
            try? task.run()
            task.waitUntilExit()
            if needsPreRife {
                try? FileManager.default.removeItem(at: prerifeURL)
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let hdiutilTask = Process()
            hdiutilTask.launchPath = "/usr/bin/hdiutil"
            hdiutilTask.arguments = ["attach", "-nomount", "ram://4194304"]
            let pipe = Pipe()
            hdiutilTask.standardOutput = pipe
            do {
                try hdiutilTask.run()
                hdiutilTask.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let devicePath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !devicePath.isEmpty else {
                    cleanupAll()
                    completionCallback(.failure(.executionFailed("Failed to allocate RAM Disk")))
                    return
                }
                
                let diskutilTask = Process()
                diskutilTask.launchPath = "/usr/sbin/diskutil"
                diskutilTask.arguments = ["erasevolume", "HFS+", ramDiskName, devicePath]
                try diskutilTask.run()
                diskutilTask.waitUntilExit()
                
                if diskutilTask.terminationStatus != 0 {
                    cleanupAll()
                    completionCallback(.failure(.executionFailed("Failed to format RAM Disk")))
                    return
                }
            } catch {
                cleanupAll()
                completionCallback(.failure(.executionFailed("Error creating RAM Disk: \(error.localizedDescription)")))
                return
            }
            
            do {
                try FileManager.default.createDirectory(atPath: inputFramesDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(atPath: outputFramesDir, withIntermediateDirectories: true)
            } catch {
                cleanupAll()
                completionCallback(.failure(.executionFailed("Failed to create directories on RAM Disk")))
                return
            }
            
            // Stage 2: Extract frames (20% – 30%)
            self.setProgressCallback { localPercent in
                let mapped = self.rifeMapProgress(localPercent, rangeStart: 20, rangeEnd: 30)
                DispatchQueue.main.async {
                    originalProgressCallback(mapped)
                }
            }
            
            let extractArgs = [
                "-i", prerifeURL.path,
                "-progress", "pipe:1",
                "\(inputFramesDir)/frame_%08d.png"
            ]
            
            self.logCommand(executablePath: ffmpegExecutablePath, arguments: extractArgs)
            self.executeFFmpeg(executablePath: ffmpegExecutablePath, arguments: extractArgs, videoDuration: self.resolvedOutputDuration(request)) { extractResult in
                switch extractResult {
                case .failure(let error):
                    cleanupAll()
                    completionCallback(.failure(error))
                case .success:
                    // Calculate target frame count
                    let inputFiles = try? FileManager.default.contentsOfDirectory(atPath: inputFramesDir)
                    let inputCount = inputFiles?.filter { $0.hasSuffix(".png") }.count ?? 0
                    
                    // The prerife pass applies trims and speed filters (if any).
                    // Its true duration is the base trimmed duration adjusted by the speed multiplier.
                    let baseDuration = self.resolvedOutputDuration(request)
                    let speed = request.speedPercent / 100.0
                    
                    let targetDuration: Double
                    if request.dynamicSpeedEnabled {
                        let sourceDuration = max(0.0, request.videoInfo?.duration ?? 0.0)
                        let speedClipStart = request.trimSegments.map { $0.start }.min() ?? 0.0
                        let fallbackSpeedEndFromPoints = request.dynamicSpeedPoints.map(\.time).max() ?? speedClipStart
                        let maxTrimEnd = request.trimSegments.map { $0.end }.max() ?? (sourceDuration > 0 ? sourceDuration : speedClipStart)
                        let speedClipEnd = max(sourceDuration, fallbackSpeedEndFromPoints, maxTrimEnd)
                        
                        targetDuration = SpeedMapPoint.calculateDynamicDuration(
                            points: request.dynamicSpeedPoints,
                            clipStart: speedClipStart,
                            clipEnd: speedClipEnd
                        )
                    } else if request.speedPercent != 100.0 && speed > 0 {
                        targetDuration = baseDuration / speed
                    } else {
                        targetDuration = baseDuration
                    }
                    
                    let targetFPS = request.frameRateSettings.targetFrameRate.rawValue
                    
                    // targetCount is simply the target duration multiplied by the target frame rate.
                    // Always ensure we have at least inputCount frames to avoid errors.
                    let targetCount = max(inputCount, Int(targetDuration * targetFPS))
                    
                    // Stage 3: RIFE interpolation (30% – 70%)
                    // Report initial progress for RIFE stage
                    DispatchQueue.main.async {
                        originalProgressCallback(self.rifeMapProgress(0, rangeStart: 30, rangeEnd: 70))
                    }
                    
                    let rifeTask = Process()
                    rifeTask.launchPath = rifeExecutablePath
                    let modelPath = URL(fileURLWithPath: rifeExecutablePath).deletingLastPathComponent().appendingPathComponent("rife-v4.25").path
                    rifeTask.arguments = ["-m", modelPath, "-i", inputFramesDir, "-o", outputFramesDir, "-n", "\(targetCount)", "-f", "%08d.png"]
                    
                    // Monitor RIFE progress by counting output frames
                    let monitorQueue = DispatchQueue(label: "com.lazyconverter.rife.progress")
                    let monitorSource = DispatchSource.makeTimerSource(queue: monitorQueue)
                    monitorSource.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
                    monitorSource.setEventHandler {
                        let currentFiles = (try? FileManager.default.contentsOfDirectory(atPath: outputFramesDir))?
                            .filter { $0.hasSuffix(".png") }.count ?? 0
                        let localPercent = targetCount > 0
                            ? min(99.0, Double(currentFiles) / Double(targetCount) * 100.0)
                            : 0.0
                        let mapped = self.rifeMapProgress(localPercent, rangeStart: 30, rangeEnd: 70)
                        DispatchQueue.main.async {
                            originalProgressCallback(mapped)
                        }
                    }
                    monitorSource.resume()
                    
                    do {
                        try rifeTask.run()
                        rifeTask.waitUntilExit()
                        
                        monitorSource.cancel()
                        
                        if rifeTask.terminationStatus != 0 {
                            cleanupAll()
                            completionCallback(.failure(.executionFailed("RIFE execution failed with status \(rifeTask.terminationStatus)")))
                            return
                        }
                    } catch {
                        monitorSource.cancel()
                        cleanupAll()
                        completionCallback(.failure(.executionFailed("RIFE error: \(error.localizedDescription)")))
                        return
                    }
                    
                    // Report RIFE stage complete
                    DispatchQueue.main.async {
                        originalProgressCallback(self.rifeMapProgress(100, rangeStart: 30, rangeEnd: 70))
                    }
                    
                    // Stage 4: Assemble frames (70% – 85%)
                    self.setProgressCallback { localPercent in
                        let mapped = self.rifeMapProgress(localPercent, rangeStart: 70, rangeEnd: 85)
                        DispatchQueue.main.async {
                            originalProgressCallback(mapped)
                        }
                    }
                    
                    let outputFPS = request.frameRateSettings.targetFrameRate.rawValue
                    
                    var assembleArgs = [
                        "-framerate", "\(outputFPS)",
                        "-i", "\(outputFramesDir)/%08d.png",
                        "-i", prerifeURL.path,
                        "-map", "0:v", "-map", "1:a?",
                        "-vf", "hqdn3d=2:2:3:3,unsharp=3:3:0.3:3:3:0.3"
                    ]
                    
                    let (videoCodec, _) = self.codecForFormat(request.format, useGPU: request.useGPU, maxOutputSizeMB: request.maxOutputSizeMB)
                    assembleArgs += ["-c:v", videoCodec]
                    
                    if request.videoInfo?.hasAudio == true {
                        if needsPreRife {
                            assembleArgs += ["-c:a", "copy"] // Audio is already properly encoded in prerifeURL
                        } else {
                            // Since we skipped prerife, audio is from original source and might need re-encoding
                            let (_, audioCodec) = self.codecForFormat(request.format, useGPU: request.useGPU, maxOutputSizeMB: request.maxOutputSizeMB)
                            assembleArgs += ["-c:a", audioCodec]
                            assembleArgs += ["-b:a", "128k"]
                        }
                    }
                    
                    if request.format == .webm {
                        assembleArgs += ["-b:v", "0", "-quality", "good", "-cpu-used", "0"]
                    } else if request.format == .av1 {
                        assembleArgs += ["-preset", "4"]
                    }
                    
                    if request.maxOutputSizeMB == nil {
                        assembleArgs += self.qualityArguments(videoCodec: videoCodec, crf: request.quality)
                    } else {
                        assembleArgs += self.outputSizeLimitArguments(maxOutputSizeMB: request.maxOutputSizeMB, duration: self.resolvedOutputDuration(request), hasAudio: request.videoInfo?.hasAudio == true)
                    }
                    
                    let outputDir = request.outputURL.deletingLastPathComponent()
                    let baseName = request.outputURL.deletingPathExtension().lastPathComponent
                    let intermediateURL = self.makeTemporaryOutputURL(in: outputDir, baseName: "\(baseName)_postrife", fileExtension: request.outputURL.pathExtension)
                    
                    assembleArgs += ["-y", intermediateURL.path]
                    
                    self.logCommand(executablePath: ffmpegExecutablePath, arguments: assembleArgs)
                    self.executeFFmpeg(executablePath: ffmpegExecutablePath, arguments: assembleArgs, videoDuration: self.resolvedOutputDuration(request)) { assembleResult in
                        cleanupAll()
                        
                        switch assembleResult {
                        case .failure(let error):
                            completionCallback(.failure(error))
                        case .success:
                            // Stage 5: Final pass (85% – 100%)
                            self.setProgressCallback { localPercent in
                                let mapped = self.rifeMapProgress(localPercent, rangeStart: 85, rangeEnd: 100)
                                DispatchQueue.main.async {
                                    originalProgressCallback(mapped)
                                }
                            }
                            
                            var finalRequest = request
                            finalRequest = FFmpegConversionRequest(
                                inputURL: intermediateURL,
                                outputURL: request.outputURL,
                                format: request.format,
                                resolution: .original,
                                quality: request.quality,
                                speedPercent: 100.0,
                                maxOutputSizeMB: request.maxOutputSizeMB,
                                dynamicSpeedEnabled: false,
                                dynamicSpeedPoints: [],
                                useGPU: request.useGPU,
                                stabilizationLevel: request.stabilizationLevel,
                                loopEnabled: request.loopEnabled,
                                superCompression: request.superCompression,
                                superCompressionGPU: request.superCompressionGPU,
                                trimSegments: [],
                                videoInfo: request.videoInfo,
                                cropEnable: false,
                                cropDynamicEnabled: false,
                                cropDynamicKeyframes: [],
                                cropRec: nil,
                                colorAdjustments: .default,
                                frameRateSettings: FrameRateSettings(mode: .keep, targetFrameRate: .fps60, useRifeGPU: false),
                                watermarkConfig: request.watermarkConfig,
                                progressCallback: originalProgressCallback,
                                completionCallback: { finalResult in
                                    try? FileManager.default.removeItem(at: intermediateURL)
                                    completionCallback(finalResult)
                                },
                                rifeExecutablePath: nil
                            )
                            
                            self.runConversionPipeline(request: finalRequest, executablePath: ffmpegExecutablePath, completionCallback: finalRequest.completionCallback)
                        }
                    }
                }
            }
        }
    }
}
