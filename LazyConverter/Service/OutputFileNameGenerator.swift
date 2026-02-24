//
//  OutputFileNameGenerator.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 24/02/26.
//

import Foundation

enum OutputFileNameGenerator {
    static func nextAvailableOutputURL(
        inputURL: URL,
        outputDirectory: URL,
        format: VideoFormat,
        fileManager: FileManager = .default
    ) -> URL {
        let originalBaseName = inputURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = originalBaseName.isEmpty ? "converted" : originalBaseName
        let fileExtension = outputExtension(for: format)

        var index = 1
        while true {
            let candidateFilename = "\(baseName)_\(index).\(fileExtension)"
            let candidateURL = outputDirectory.appendingPathComponent(candidateFilename)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private static func outputExtension(for format: VideoFormat) -> String {
        switch format {
        case .webm:
            return "webm"
        case .av1:
            return "mp4"
        default:
            return format.rawValue
        }
    }
}
