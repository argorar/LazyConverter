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
    let loopEnabled: Bool
    let trimStart: Double?
    let trimEnd: Double?
    let videoInfo: VideoInfo?
    let cropEnable: Bool
    let cropDynamicEnabled: Bool
    let cropDynamicKeyframes: [CropDynamicKeyframe]
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
        loopEnabled: Bool,
        trimStart: Double? = nil,
        trimEnd: Double? = nil,
        videoInfo: VideoInfo?,
        cropEnable: Bool,
        cropDynamicEnabled: Bool = false,
        cropDynamicKeyframes: [CropDynamicKeyframe] = [],
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
        self.loopEnabled = loopEnabled
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.videoInfo = videoInfo
        self.cropEnable = cropEnable
        self.cropDynamicEnabled = cropDynamicEnabled
        self.cropDynamicKeyframes = cropDynamicKeyframes
        self.cropRec = cropRec
        self.colorAdjustments = colorAdjustments
        self.frameRateSettings = frameRateSettings
        self.progressCallback = progressCallback
        self.completionCallback = completionCallback
    }
}
