//
//  FFmpegConversionRequest.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 6/02/26.
//

import Foundation
import CoreGraphics

struct FFmpegConversionRequest {
    let inputURL: URL
    let outputURL: URL
    let format: VideoFormat
    let resolution: VideoResolution
    let quality: Int
    let speedPercent: Double
    let useGPU: Bool
    let trimStart: Double?
    let trimEnd: Double?
    let videoInfo: VideoInfo?
    let cropEnable: Bool
    let cropRec: CGRect?
    let colorAdjustments: ColorAdjustments
    let frameRateSettings: FrameRateSettings
    let progressCallback: (Double) -> Void
    let completionCallback: (Result<URL, FFmpegError>) -> Void
    
    init(
        inputURL: URL,
        outputURL: URL,
        format: VideoFormat,
        resolution: VideoResolution,
        quality: Int,
        speedPercent: Double,
        useGPU: Bool,
        trimStart: Double? = nil,
        trimEnd: Double? = nil,
        videoInfo: VideoInfo?,
        cropEnable: Bool,
        cropRec: CGRect? = nil,
        colorAdjustments: ColorAdjustments = .default,
        frameRateSettings: FrameRateSettings,
        progressCallback: @escaping (Double) -> Void,
        completionCallback: @escaping (Result<URL, FFmpegError>) -> Void
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.format = format
        self.resolution = resolution
        self.quality = quality
        self.speedPercent = speedPercent
        self.useGPU = useGPU
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.videoInfo = videoInfo
        self.cropEnable = cropEnable
        self.cropRec = cropRec
        self.colorAdjustments = colorAdjustments
        self.frameRateSettings = frameRateSettings
        self.progressCallback = progressCallback
        self.completionCallback = completionCallback
    }
}
