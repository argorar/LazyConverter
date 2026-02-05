//
//  QueueItem.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 1/02/26.
//

import Foundation
import SwiftUI

struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let filename: String
    var status: QueueStatus = .pending
    var progress: Double = 0.0
    var outputURL: URL?
    var error: String?
    

    let format: VideoFormat
    let resolution: VideoResolution
    let quality: Int
    let speedPercent: Double
    let useGPU: Bool
    let trimStart: Double?
    let trimEnd: Double?
    let cropEnabled: Bool
    let cropRect: CGRect?
    let colorAdjustments: ColorAdjustments
    let frameRateSettings: FrameRateSettings
    
    init(url: URL, settings: ConversionSettings) {
        self.url = url
        self.filename = url.lastPathComponent
        self.format = settings.format
        self.resolution = settings.resolution
        self.quality = settings.quality
        self.speedPercent = settings.speedPercent
        self.useGPU = settings.useGPU
        self.trimStart = settings.trimStart
        self.trimEnd = settings.trimEnd
        self.cropEnabled = settings.cropEnabled
        self.cropRect = settings.cropRect
        self.colorAdjustments = settings.colorAdjustments
        self.frameRateSettings = settings.frameRateSettings
    }
}

enum QueueStatus: String {
    case pending = "Pending"
    case converting = "Converting"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .converting: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .secondary
        case .converting: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

struct ConversionSettings {
    let format: VideoFormat
    let resolution: VideoResolution
    let quality: Int
    let speedPercent: Double
    let useGPU: Bool
    let trimStart: Double?
    let trimEnd: Double?
    let cropEnabled: Bool
    let cropRect: CGRect?
    let colorAdjustments: ColorAdjustments
    let frameRateSettings: FrameRateSettings
}
