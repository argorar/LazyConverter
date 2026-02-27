//
//  YtDlpService.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 27/02/26.
//

import Foundation

enum YtDlpServiceError: LocalizedError {
    case notInstalled
    case invalidInput
    case busy
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "yt-dlp is not installed"
        case .invalidInput:
            return "Invalid input URL"
        case .busy:
            return "A download is already in progress"
        case .downloadFailed(let reason):
            return reason
        }
    }
}

final class YtDlpService {
    static let shared = YtDlpService()

    private var process: Process?
    private(set) var lastErrorLog: String?

    private init() {}

    func isInstalled() -> Bool {
        guard let path = findYtDlpPath() else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    func download(
        videoURLString: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let trimmed = videoURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(YtDlpServiceError.invalidInput))
            return
        }

        guard let ytDlpPath = findYtDlpPath(),
              FileManager.default.isExecutableFile(atPath: ytDlpPath) else {
            completion(.failure(YtDlpServiceError.notInstalled))
            return
        }

        guard process == nil else {
            completion(.failure(YtDlpServiceError.busy))
            return
        }

        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        var arguments: [String] = []

        if isYouTubeURL(trimmed) {
            arguments += [
                "--format", "bestvideo+bestaudio/best",
                "--merge-output-format", "mp4"
            ]
        }

        if let ffmpegPath = findFFmpegPath() {
            arguments += ["--ffmpeg-location", ffmpegPath]
        }

        arguments += [
            "-P", downloadsDirectory.path,
            "-o", "%(title)s.%(ext)s",
            trimmed
        ]
        process.arguments = arguments
        self.process = process
        self.lastErrorLog = nil

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        var stdoutBuffer = ""
        var stderrBuffer = ""
        var stdoutLog = ""
        var stderrLog = ""
        var latestFilePath: URL?
        var lastReportedProgress: Double = 0.0
        var expectedStages: Int = 1
        var currentStage: Int = 0
        var currentStagePercent: Double = 0.0

        let lock = NSLock()
        func mappedProgress(for rawPercent: Double) -> Double {
            let percent = min(max(rawPercent, 0.0), 100.0)

            if percent + 0.5 < currentStagePercent {
                if currentStage < (expectedStages - 1) {
                    currentStage += 1
                }
                currentStagePercent = percent
            } else {
                currentStagePercent = max(currentStagePercent, percent)
            }

            let safeStages = max(1, expectedStages)
            let safeStageIndex = min(max(currentStage, 0), safeStages - 1)
            let mapped = ((Double(safeStageIndex) + (currentStagePercent / 100.0)) / Double(safeStages)) * 100.0
            return min(max(mapped, 0.0), 99.5)
        }

        func advanceStageIfNeeded() {
            guard currentStagePercent >= 99.0 else { return }
            if expectedStages == 1 {
                expectedStages = 2
            }
            currentStage = min(currentStage + 1, expectedStages - 1)
            currentStagePercent = 0.0
        }

        func updateLatestFilePath(from line: String) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { return }

            if let stageCount = self.extractExpectedStageCount(from: trimmedLine) {
                expectedStages = max(expectedStages, stageCount)
            }

            if trimmedLine.contains("Destination:") {
                advanceStageIfNeeded()
            }

            if trimmedLine.hasPrefix("/") {
                latestFilePath = URL(fileURLWithPath: trimmedLine)
                return
            }

            if let range = trimmedLine.range(of: "Destination: ") {
                let destination = String(trimmedLine[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if destination.hasPrefix("/") {
                    latestFilePath = URL(fileURLWithPath: destination)
                }
                return
            }

            if let mergeRange = trimmedLine.range(of: "into \""),
               let closeQuote = trimmedLine[mergeRange.upperBound...].firstIndex(of: "\"") {
                let filePath = String(trimmedLine[mergeRange.upperBound..<closeQuote])
                if filePath.hasPrefix("/") {
                    latestFilePath = URL(fileURLWithPath: filePath)
                }
            }
        }

        func consumeLines(
            from buffer: inout String,
            flushPartial: Bool = false,
            handler: (String) -> Void
        ) {
            while let separatorIndex = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let line = String(buffer[..<separatorIndex])
                var removeUpperBound = buffer.index(after: separatorIndex)

                if buffer[separatorIndex] == "\r",
                   removeUpperBound < buffer.endIndex,
                   buffer[removeUpperBound] == "\n" {
                    removeUpperBound = buffer.index(after: removeUpperBound)
                }

                buffer.removeSubrange(..<removeUpperBound)
                if !line.isEmpty {
                    handler(line)
                }
            }

            if flushPartial {
                let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    handler(remainder)
                }
                buffer.removeAll(keepingCapacity: true)
            }
        }

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

            var latestProgress: Double?
            lock.lock()
            stdoutBuffer += chunk
            stdoutLog += chunk
            if let percent = self.extractHighestProgressPercent(from: chunk) {
                latestProgress = max(latestProgress ?? 0.0, mappedProgress(for: percent))
            }
            consumeLines(from: &stdoutBuffer) { line in
                updateLatestFilePath(from: line)
                if let percent = self.extractProgressPercent(from: line) {
                    latestProgress = max(latestProgress ?? 0.0, mappedProgress(for: percent))
                }
            }
            if let latestProgress {
                let clamped = min(max(latestProgress, 0.0), 99.5)
                if abs(clamped - lastReportedProgress) >= 0.1 {
                    lastReportedProgress = clamped
                    DispatchQueue.main.async {
                        progress(clamped)
                    }
                }
            }
            lock.unlock()
        }

        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

            var latestProgress: Double?
            lock.lock()
            stderrBuffer += chunk
            stderrLog += chunk
            if let percent = self.extractHighestProgressPercent(from: chunk) {
                latestProgress = max(latestProgress ?? 0.0, mappedProgress(for: percent))
            }
            consumeLines(from: &stderrBuffer) { line in
                updateLatestFilePath(from: line)
                if let percent = self.extractProgressPercent(from: line) {
                    latestProgress = max(latestProgress ?? 0.0, mappedProgress(for: percent))
                }
            }
            if let latestProgress {
                let clamped = min(max(latestProgress, 0.0), 99.5)
                if abs(clamped - lastReportedProgress) >= 0.1 {
                    lastReportedProgress = clamped
                    DispatchQueue.main.async {
                        progress(clamped)
                    }
                }
            }
            lock.unlock()
        }

        process.terminationHandler = { _ in
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            self.process = nil

            lock.lock()
            consumeLines(from: &stdoutBuffer, flushPartial: true) { line in
                updateLatestFilePath(from: line)
                if let percent = self.extractProgressPercent(from: line) {
                    lastReportedProgress = max(lastReportedProgress, mappedProgress(for: percent))
                }
            }
            consumeLines(from: &stderrBuffer, flushPartial: true) { line in
                updateLatestFilePath(from: line)
                if let percent = self.extractProgressPercent(from: line) {
                    lastReportedProgress = max(lastReportedProgress, mappedProgress(for: percent))
                }
            }
            let resolvedOutputURL = latestFilePath
            let resolvedStdout = stdoutLog.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedError = stderrLog.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalProgress = min(max(lastReportedProgress, 0.0), 100.0)
            lock.unlock()
            let combinedLog = [resolvedStdout, resolvedError]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    self.lastErrorLog = nil
                    progress(max(finalProgress, 99.0))
                    if let resolvedOutputURL, FileManager.default.fileExists(atPath: resolvedOutputURL.path) {
                        progress(100.0)
                        completion(.success(resolvedOutputURL))
                        return
                    }
                    self.lastErrorLog = combinedLog.isEmpty ? nil : combinedLog
                    completion(.failure(YtDlpServiceError.downloadFailed("yt-dlp finished without an output file")))
                    return
                }

                self.lastErrorLog = combinedLog.isEmpty ? nil : combinedLog
                completion(.failure(YtDlpServiceError.downloadFailed(resolvedError.isEmpty ? "yt-dlp download failed" : resolvedError)))
            }
        }

        do {
            try process.run()
        } catch {
            self.process = nil
            self.lastErrorLog = error.localizedDescription
            completion(.failure(error))
        }
    }

    func cancelDownload() {
        process?.terminate()
        process = nil
    }

    private func extractProgressPercent(from line: String) -> Double? {
        extractHighestProgressPercent(from: line)
    }

    private func extractHighestProgressPercent(from text: String) -> Double? {
        let pattern = #"(\d{1,3}(?:[.,]\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        var highest: Double?
        for match in matches where match.numberOfRanges > 1 {
            let raw = (text as NSString).substring(with: match.range(at: 1))
            let normalized = raw.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized), value.isFinite else { continue }
            let clamped = min(max(value, 0.0), 100.0)
            highest = max(highest ?? clamped, clamped)
        }
        return highest
    }

    private func extractExpectedStageCount(from line: String) -> Int? {
        guard line.localizedCaseInsensitiveContains("format(s):") else { return nil }
        guard let markerRange = line.range(of: "format(s):", options: .caseInsensitive) else { return nil }
        let formatsPart = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formatsPart.isEmpty else { return nil }

        // Ejemplo: "616+251" => 2 descargas (video + audio)
        let plusCount = formatsPart.filter { $0 == "+" }.count
        if plusCount > 0 {
            return plusCount + 1
        }

        // Fallback: si no hay '+', asumir una sola etapa.
        return 1
    }

    private func findYtDlpPath() -> String? {
        if let bundlePath = Bundle.main.path(forResource: "yt-dlp", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        let knownPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !output.isEmpty else { return nil }
            return FileManager.default.isExecutableFile(atPath: output) ? output : nil
        } catch {
            return nil
        }
    }

    private func findFFmpegPath() -> String? {
        FFmpegConverter.shared.resolvedFFmpegPath()
    }

    private func isYouTubeURL(_ input: String) -> Bool {
        if let url = URL(string: input),
           let host = url.host?.lowercased() {
            return host == "youtu.be" ||
            host.contains("youtube.com") ||
            host.contains("youtube-nocookie.com")
        }

        let lower = input.lowercased()
        return lower.contains("youtube.com") || lower.contains("youtu.be")
    }
}
