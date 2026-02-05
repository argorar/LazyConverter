//
//  VideoAnalyzer.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 25/12/25.
//

import Foundation
import AVFoundation
import AppKit


// MARK: - Video Analyzer
class VideoAnalyzer {
    static func analyze(_ url: URL) async -> VideoInfo? {
        guard url.isFileURL else { return nil }
        
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.load(.tracks)
            
            guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
                return nil
            }
            let audioTrack = tracks.first { $0.mediaType == .audio }

            let size = try await videoTrack.load(.naturalSize)

            let transform: CGAffineTransform = try await videoTrack.load(.preferredTransform)
            let videoSize = size.applying(transform)

            let fileSize = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0

            let fps = try await Double(videoTrack.load(.nominalFrameRate))

            let colorInfo = await Task.detached {
                return await extractColorInfoWithFFprobe(url: url)
            }.value
            
            return VideoInfo(
                duration: duration.seconds,
                videoSize: videoSize,
                hasAudio: audioTrack != nil,
                fileSizeMB: Double(fileSize) / 1_048_576,
                fileName: url.lastPathComponent,
                originalURL: url,
                frameRate: fps,
                colorInfo: colorInfo
            )
        } catch {
            print("❌ Error analizando video: \(error)")
            return nil
        }
    }
    
    private static func extractColorInfoWithFFprobe(url: URL) -> VideoColorInfo {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: findFFprobe())
            
            // ffprobe query COMPLETA para color info
            process.arguments = [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=pix_fmt,color_primaries,color_trc,color_space,color_range,side_data_list",
                "-of", "csv=p=0",
                url.path
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String( data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Parsear salida CSV: pix_fmt,color_primaries,color_trc,color_space,color_range
                let fields = output?.components(separatedBy: ",")
                
                let pixelFormat = fields?.first ?? "yuv420p"
                let primaries = fields?.dropFirst().first ?? "bt709"
                let trc = fields?.dropFirst(2).first ?? "bt709"
                let matrix = fields?.dropFirst(3).first ?? "bt709"
                let range = fields?.dropFirst(4).first ?? "tv"
                
                return VideoColorInfo(
                    pixelFormat: pixelFormat,
                    colorPrimaries: primaries,
                    colorTrc: trc,
                    colorSpace: matrix,
                    colorRange: range
                )
                
            } catch {
                print("Error ejecutando ffprobe: \(error)")
            }
            
            return VideoColorInfo(
                pixelFormat: "yuv420p",
                colorPrimaries: "bt709",
                colorTrc: "bt709",
                colorSpace: "bt709",
                colorRange: "tv"
            )
        }
    
    private static func findFFprobe() -> String {
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

