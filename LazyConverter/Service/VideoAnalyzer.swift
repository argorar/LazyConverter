//
//  VideoAnalyzer.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import Foundation
import CoreGraphics

// MARK: - Video Analyzer
class VideoAnalyzer {
    static func analyze(_ url: URL) async -> VideoInfo? {
        guard url.isFileURL else { return nil }

        return await Task.detached {
            guard let ffprobePath = findFFprobe() else { return nil }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobePath)
            process.arguments = [
                "-v", "error",
                "-show_format",
                "-show_streams",
                "-of", "json",
                url.path
            ]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }

                let streams = json["streams"] as? [[String: Any]] ?? []
                guard let videoStream = streams.first(where: { ($0["codec_type"] as? String) == "video" }) else {
                    return nil
                }

                // Dimensiones y rotación
                var width = Double(videoStream["width"] as? Int ?? 0)
                var height = Double(videoStream["height"] as? Int ?? 0)

                var rotation = 0
                if let sideDataList = videoStream["side_data_list"] as? [[String: Any]] {
                    for sideData in sideDataList {
                        if let rot = sideData["rotation"] as? Int {
                            rotation = rot
                        } else if let rot = sideData["rotation"] as? Double {
                            rotation = Int(rot)
                        }
                    }
                }
                if rotation == 0, let tags = videoStream["tags"] as? [String: Any],
                   let rotateStr = tags["rotate"] as? String, let rot = Int(rotateStr) {
                    rotation = rot
                }

                if abs(rotation) == 90 || abs(rotation) == 270 {
                    swap(&width, &height)
                }

                // Duración
                let formatDict = json["format"] as? [String: Any] ?? [:]
                let durationStr = (formatDict["duration"] as? String) ?? (videoStream["duration"] as? String) ?? "0"
                let duration = Double(durationStr) ?? 0.0

                // Tamaño de archivo
                let sizeStr = formatDict["size"] as? String
                let fileSize = (sizeStr.flatMap { Int($0) }) ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0

                // Frame rate
                let fpsString = (videoStream["avg_frame_rate"] as? String) ?? (videoStream["r_frame_rate"] as? String)
                let fps = parseFrameRate(fpsString)

                // Audio
                let hasAudio = streams.contains(where: { ($0["codec_type"] as? String) == "audio" })

                // Color info
                let pixelFormat = videoStream["pix_fmt"] as? String ?? "yuv420p"
                let primaries = videoStream["color_primaries"] as? String ?? "bt709"
                let trc = videoStream["color_trc"] as? String ?? "bt709"
                let matrix = videoStream["color_space"] as? String ?? "bt709"
                let range = videoStream["color_range"] as? String ?? "tv"

                let colorInfo = VideoColorInfo(
                    pixelFormat: pixelFormat,
                    colorPrimaries: primaries,
                    colorTrc: trc,
                    colorSpace: matrix,
                    colorRange: range
                )

                return VideoInfo(
                    duration: duration,
                    videoSize: CGSize(width: width, height: height),
                    hasAudio: hasAudio,
                    fileSizeMB: Double(fileSize) / 1_048_576.0,
                    fileName: url.lastPathComponent,
                    originalURL: url,
                    frameRate: fps,
                    colorInfo: colorInfo
                )
            } catch {
                print("❌ Error analizando video con ffprobe: \(error)")
                return nil
            }
        }.value
    }

    private static func parseFrameRate(_ string: String?) -> Double {
        guard let string = string, !string.isEmpty, string != "0/0" else { return 30.0 }
        let parts = string.split(separator: "/")
        if parts.count == 2,
           let num = Double(parts[0]),
           let den = Double(parts[1]), den > 0 {
            return num / den
        }
        return Double(string) ?? 30.0
    }

    private static func findFFprobe() -> String? {
        if let bundlePath = Bundle.main.path(forResource: "ffprobe", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        let systemPaths = ["/usr/local/bin/ffprobe", "/opt/homebrew/bin/ffprobe"]
        for path in systemPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}

