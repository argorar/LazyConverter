//
//  QueueManager.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 1/02/26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class QueueManager: ObservableObject {
    @Published var queue: [QueueItem] = []
    @Published var isProcessing = false
    @Published var currentItemIndex: Int?
    @Published var globalProgress: Double = 0.0
    
    private var cancellables = Set<AnyCancellable>()
    
    func addToQueue(url: URL, settings: ConversionSettings) {
        let item = QueueItem(url: url, settings: settings)
        queue.append(item)
    }
    
    func addMultipleToQueue(urls: [URL], settings: ConversionSettings) {
        let items = urls.map { QueueItem(url: $0, settings: settings) }
        queue.append(contentsOf: items)
    }
    
    func removeItem(at index: Int) {
        guard index < queue.count else { return }
        queue.remove(at: index)
    }
    
    func clearCompleted() {
        queue.removeAll { $0.status == .completed }
    }
    
    func clearAll() {
        queue.removeAll()
        currentItemIndex = nil
        globalProgress = 0
    }
    
    func moveItem(from: IndexSet, to: Int) {
        queue.move(fromOffsets: from, toOffset: to)
    }
    
    func startQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        
        for (index, item) in queue.enumerated() where item.status == .pending {
            currentItemIndex = index
            await processItem(at: index)
            
            // Si se canceló, parar
            if !isProcessing { break }
        }
        
        isProcessing = false
        currentItemIndex = nil
        updateGlobalProgress()
    }
    
    func pauseQueue() {
        isProcessing = false
        FFmpegConverter.shared.cancel()
    }
    
    private func processItem(at index: Int) async {
        guard index < queue.count else { return }
        
        var item = queue[index]
        item.status = .converting
        item.progress = 0
        queue[index] = item
        
        // Output path
        let outputDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let outputFilename = (item.filename as NSString).deletingPathExtension + "_converted.\(item.format.rawValue)"
        let outputURL = outputDir.appendingPathComponent(outputFilename)
        
        await withCheckedContinuation { continuation in
            FFmpegConverter.shared.convert(
                inputURL: item.url,
                outputURL: outputURL,
                format: item.format,
                resolution: item.resolution,
                quality: item.quality,
                speedPercent: item.speedPercent,
                useGPU: item.useGPU,
                trimStart: item.trimStart,
                trimEnd: item.trimEnd,
                videoInfo: nil,
                cropEnable: item.cropEnabled,
                cropRec: item.cropRect,
                colorAdjustments: item.colorAdjustments,
                frameRateSettings: item.frameRateSettings,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.updateItemProgress(at: index, progress: progress)
                    }
                },
                completionCallback: { [weak self] result in
                    Task { @MainActor in
                        self?.handleCompletion(at: index, result: result, outputURL: outputURL)
                        continuation.resume()
                    }
                }
            )
        }
    }
    
    private func updateItemProgress(at index: Int, progress: Double) {
        guard index < queue.count else { return }
        queue[index].progress = progress
        updateGlobalProgress()
    }
    
    private func handleCompletion(at index: Int, result: Result<URL, FFmpegError>, outputURL: URL) {
        guard index < queue.count else { return }
        
        switch result {
        case .success(let url):
            queue[index].status = .completed
            queue[index].progress = 100
            queue[index].outputURL = url
        case .failure(let error):
            queue[index].status = .failed
            queue[index].error = error.localizedDescription
        }
        
        updateGlobalProgress()
    }
    
    private func updateGlobalProgress() {
        let completedCount = queue.filter { $0.status == .completed }.count
        globalProgress = queue.isEmpty ? 0 : Double(completedCount) / Double(queue.count) * 100
    }
}
