//
//  MergeVideosViewModel.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 22/04/26
//

import Combine
import AVFoundation
import AppKit
import SwiftUI

class MergeVideosViewModel: NSObject, ObservableObject {
    @AppStorage("selectedOutputDirectory") private var storedOutputDirectory: String = OutputDirectory.downloads.rawValue
    
    @Published var selectedVideoURLs: [URL] = []
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var errorLog: String?
    
    var lang: LanguageManager?
    
    func setLanguageManager(_ lang: LanguageManager) {
        self.lang = lang
    }
    
    func openFileSelector() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie, .avi]
        
        if panel.runModal() == .OK {
            let newURLs = panel.urls.filter { !self.selectedVideoURLs.contains($0) }
            self.selectedVideoURLs.append(contentsOf: newURLs)
            self.errorMessage = nil
        }
    }
    
    func removeVideo(at index: Int) {
        guard index >= 0 && index < selectedVideoURLs.count else { return }
        selectedVideoURLs.remove(at: index)
    }
    
    func moveUp(index: Int) {
        guard index > 0 && index < selectedVideoURLs.count else { return }
        selectedVideoURLs.swapAt(index, index - 1)
    }
    
    func moveDown(index: Int) {
        guard index >= 0 && index < selectedVideoURLs.count - 1 else { return }
        selectedVideoURLs.swapAt(index, index + 1)
    }
    
    func clearSelection() {
        selectedVideoURLs.removeAll()
        errorMessage = nil
        errorLog = nil
        progress = 0
        statusMessage = ""
        isProcessing = false
    }
    
    func startMerge() {
        guard selectedVideoURLs.count > 1 else {
            errorMessage = lang?.t("merge.error.not_enough_videos") ?? "Please select at least 2 videos to merge."
            return
        }
        
        isProcessing = true
        progress = 0
        statusMessage = lang?.t("merge.status.starting") ?? "Preparing to merge videos..."
        errorMessage = nil
        errorLog = nil
        
        let outputDir = OutputDirectory(rawValue: storedOutputDirectory)?.resolveURL() ?? OutputDirectory.downloads.resolveURL()
        
        // Generar un nombre de archivo uniendo los primeros dos y un timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let defaultName = "MergedVideo_\(timestamp).mp4"
        let outputURL = outputDir.appendingPathComponent(defaultName)
        
        FFmpegConverter.shared.mergeVideos(
            urls: selectedVideoURLs,
            outputURL: outputURL,
            progressCallback: { [weak self] currentProgress in
                DispatchQueue.main.async {
                    self?.progress = currentProgress
                    self?.statusMessage = self?.lang?.t("merge.status.processing") ?? "Merging videos..."
                }
            },
            completionCallback: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    switch result {
                    case .success(let url):
                        self?.progress = 100
                        self?.statusMessage = (self?.lang?.t("merge.status.success") ?? "Merged successfully!") + " (\(url.lastPathComponent))"
                    case .failure(let error):
                        self?.progress = 0
                        self?.errorMessage = self?.lang?.t("merge.error.failed") ?? "Merge failed."
                        self?.errorLog = error.localizedDescription
                    }
                }
            }
        )
    }
}
