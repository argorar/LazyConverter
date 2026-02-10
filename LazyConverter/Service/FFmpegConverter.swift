//
//  AppLanguage.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import Foundation

class FFmpegConverter {
    static let shared = FFmpegConverter()
    
    private var process: Process?
    private var progressCallback: ((Double) -> Void)?
    
    func convert(_ request: FFmpegConversionRequest) {
        self.progressCallback = request.progressCallback
        
        print("🔹 FFmpegConverter.convert()")
        print("    speed: \(Int(request.speedPercent))%")
        print("    outputURL: \(request.outputURL.path)")
        print("    format   : \(request.format)")
        print("    resolution: \(request.resolution)")
        print("    quality  : \(request.quality)")
        print("    useGPU   : \(request.useGPU)")
        
        guard isFfmpegInstalled() else {
            print("❌ FFmpeg no encontrado en rutas conocidas")
            request.completionCallback(.failure(.ffmpegNotFound))
            return
        }
        var effectiveDuration = 0.0
        if let trimStart = request.trimStart, let trimEnd = request.trimEnd {
            effectiveDuration = trimEnd - trimStart
        }
        else {
            effectiveDuration = request.videoInfo?.duration ?? 0.0
        }
        
        // 3) Construir comando ffmpeg
        let arguments = self.buildFFmpegCommand(request)
        
        // Log del comando ffmpeg
        let ffmpegPath = self.findFFmpeg()
        print("🔹 Ejecutando ffmpeg:")
        print("    \(ffmpegPath) \\")
        for arg in arguments {
            print("      \"\(arg)\" \\")
        }
        
        // 4) Ejecutar en background
        DispatchQueue.global(qos: .userInitiated).async {
            if request.loopEnabled {
                let tempOutputURL = self.makeTemporaryOutputURL(
                    in: request.outputURL.deletingLastPathComponent(),
                    baseName: request.outputURL.deletingPathExtension().lastPathComponent,
                    fileExtension: request.outputURL.pathExtension
                )
                
                var firstPassArgs = arguments
                if !firstPassArgs.isEmpty {
                    firstPassArgs[firstPassArgs.count - 1] = tempOutputURL.path
                }
                
                self.executeFFmpeg(
                    executablePath: ffmpegPath,
                    arguments: firstPassArgs,
                    videoDuration: effectiveDuration,
                    completionCallback: { result in
                        switch result {
                        case .success:
                            let boomerangArgs = self.buildBoomerangCommand(
                                inputURL: tempOutputURL,
                                outputURL: request.outputURL,
                                format: request.format,
                                quality: request.quality,
                                useGPU: request.useGPU,
                                hasAudio: request.videoInfo?.hasAudio == true && request.speedPercent == 100.0
                            )
                            
                            self.executeFFmpeg(
                                executablePath: ffmpegPath,
                                arguments: boomerangArgs,
                                videoDuration: effectiveDuration * 2,
                                completionCallback: { secondResult in
                                    try? FileManager.default.removeItem(at: tempOutputURL)
                                    request.completionCallback(secondResult)
                                }
                            )
                        case .failure(let error):
                            request.completionCallback(.failure(error))
                        }
                    }
                )
            } else {
                self.executeFFmpeg(
                    executablePath: ffmpegPath,
                    arguments: arguments,
                    videoDuration: effectiveDuration,
                    completionCallback: request.completionCallback
                )
            }
        }
    }
    
    private func buildFFmpegCommand(_ request: FFmpegConversionRequest) -> [String] {
        var videoFilters: [String] = []
        var audioFilters: [String] = []
        var arguments: [String] = []
        
        // 1. TRIM FILTER (prioridad máxima)
        if let start = request.trimStart, let end = request.trimEnd {
            videoFilters.append("trim=start=\(start):end=\(end),setpts=PTS-STARTPTS")
            if request.videoInfo?.hasAudio == true && request.speedPercent == 100.0 {
                videoFilters.removeAll()
                arguments += ["-ss", String(start), "-to", String(end)]
            }
        }
        arguments += ["-i", request.inputURL.path]
        
        if let pixFmt = request.videoInfo?.colorInfo.pixelFormat, !pixFmt.isEmpty {
            arguments += ["-pix_fmt", pixFmt]
        }
        
        // 2. SPEED FILTER
        if request.speedPercent != 100.0 {
            let speed = request.speedPercent / 100.0
            videoFilters.append("setpts=\(1/speed)*PTS")
        }
        
        // Resolución (después de velocidad)
        if request.resolution != .original {
            let resolutionValue = request.resolution.ffmpegParam
            videoFilters.append("scale=\(resolutionValue):force_original_aspect_ratio=decrease")
            print("📏 Escalando a: \(resolutionValue)")
        }
        
        //crop
        if request.cropEnable, let cropRect = request.cropRec, let videoSize = request.videoInfo?.videoSize {
            
            let x = Int(cropRect.origin.x * videoSize.width)
            let y = Int(cropRect.origin.y * videoSize.height)
            let w = Int(cropRect.size.width * videoSize.width)
            let h = Int(cropRect.size.height * videoSize.height)

            videoFilters.append("crop=\(w):\(h):\(x):\(y)")
        }
        
        if let colorFilter = request.colorAdjustments.toFFmpegFilter() {
            videoFilters.append(colorFilter)
        }
        
        if let fpsFilters = request.frameRateSettings.toFFmpegFilter() {
            videoFilters.append(fpsFilters)
        }
        
        if !videoFilters.isEmpty {
            arguments += ["-vf", videoFilters.joined(separator: ",")]
        }
        
        if !audioFilters.isEmpty {
            arguments += ["-af", audioFilters.joined(separator: ",")]
        }
        
        let (videoCodec, audioCodec) = codecForFormat(request.format, useGPU: request.useGPU)
        
        arguments += ["-c:v", videoCodec]
        
        if request.format == .webm {
            arguments += ["-b:v", "0",
                          "-quality", "good",
                          "-cpu-used", "0",
                          "-row-mt", "1",
                          "-tile-columns", "2",
                          "-frame-parallel", "1",
                          "-auto-alt-ref", "1",
                          "-lag-in-frames", "25"]
        }
        else if request.format == .mp4 {
            arguments += ["-preset", "veryslow",
            "-tune", "film",
            "-rc-lookahead", "60",
            "-aq-mode", "3"]
        }
        else if request.format == .av1
        {
            arguments += ["-preset", "4",
                          "-svtav1-params", "scd=1",
                          "-svtav1-params", "scm=0"]
        }
        
        
        
        arguments += ["-crf", "\(request.quality)"]  // 0-51 (menor=mejor)
        
        
        if (request.videoInfo?.hasAudio == true && request.speedPercent == 100.0) {
            arguments += ["-c:a", audioCodec]
            arguments += ["-b:a", "128k"]
        }
        else {
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
        arguments += [
            "-progress", "pipe:1",
            "-y",
            request.outputURL.path
        ]
            
        print("🎬 FFmpeg Command:")
        print("  \(arguments.joined(separator: " "))")
        
        return arguments
    }

    private func buildBoomerangCommand(
        inputURL: URL,
        outputURL: URL,
        format: VideoFormat,
        quality: Int,
        useGPU: Bool,
        hasAudio: Bool
    ) -> [String] {
        var arguments: [String] = ["-i", inputURL.path]
        let (videoCodec, audioCodec) = codecForFormat(format, useGPU: useGPU)
        
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
        
        arguments += ["-crf", "\(quality)"]
        arguments += [
            "-progress", "pipe:1",
            "-y",
            outputURL.path
        ]
        
        return arguments
    }

    private func makeTemporaryOutputURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(baseName)_tmp_\(timestamp).\(fileExtension)"
        return directory.appendingPathComponent(filename)
    }

    private func codecForFormat(_ format: VideoFormat, useGPU: Bool) -> (video: String, audio: String) {
        let videoCodec = "h264_videotoolbox"
        
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

    private func executeFFmpeg(
        executablePath: String,
        arguments: [String],
        videoDuration: TimeInterval,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        self.process = process

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

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
                if case .success = result {
                    self?.progressCallback?(100.0)
                }
                completionCallback(result)
            }
        }

        // stdout: progreso
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return } // EOF

            if let chunk = String( data: data, encoding: .utf8), !chunk.isEmpty {
                stdoutBuffer += chunk

                // procesar por líneas completas (key=value)
                while let range = stdoutBuffer.range(of: "\n") {
                    let line = String(stdoutBuffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    stdoutBuffer.removeSubrange(..<range.upperBound)

                    if !line.isEmpty {
                        self?.parseFFmpegOutput(line + "\n", videoDuration: videoDuration)

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
            if data.isEmpty { return } // EOF
            if let chunk = String( data: data, encoding: .utf8), !chunk.isEmpty {
                stderrBuffer += chunk
            }
        }

        process.terminationHandler = { _ in
            // Importante: al terminar, imprime stderr completo si existe
            if !stderrBuffer.isEmpty {
                print("📥 FFmpeg stderr completo:\n\(stderrBuffer)")
            }

            print("🔚 FFmpeg finalizado - Status: \(process.terminationStatus)")

            if finished { return } // ya finalizó por progress=end

            if process.terminationStatus == 0 {
                finish(.success(URL(fileURLWithPath: arguments.last ?? "")))
            } else {
                finish(.failure(.conversionFailed))
            }
        }

        do {
            try process.run()
            print("▶️ FFmpeg iniciado (PID: \(process.processIdentifier))")
        } catch {
            print("❌ Error al iniciar FFmpeg: \(error)")
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
                    let duration = max(0.001, videoDuration) // evita div/0
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
        process.executableURL = URL(fileURLWithPath: findFFmpeg())
        process.arguments = testArgs + ["-c:v", "hevc_videotoolbox"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func cancel() {
        print("⏹️ Cancelando proceso ffmpeg...")
        process?.terminate()
        process = nil
    }
    
    
    func isFfmpegInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: findFFmpeg())
    }
    
    private func findFFmpeg() -> String {
        // Buscar en Bundle (EMBEDDED)
        if let bundlePath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            print("✅ FFmpeg encontrado en Bundle: \(bundlePath)")
            return bundlePath
        }
        
        // Fallback rutas sistema
        let systemPaths = ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("✅ FFmpeg en sistema: \(path)")
                return path
            }
        }
        
        fatalError("❌ FFmpeg no encontrado ni en Bundle ni en sistema")
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
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg no está instalado. Instala con: brew install ffmpeg"
        case .ffprobeNotFound:
            return "FFprobe no está disponible"
        case .cannotGetDuration:
            return "No se pudo obtener la duración del video"
        case .conversionFailed:
            return "La conversión de video falló"
        case .executionFailed(let reason):
            return "Error al ejecutar FFmpeg: \(reason)"
        }
    }
}
