//
//  CropDynamicKeyframe.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 10/02/26.
//

import Foundation
import CoreGraphics

struct CropDynamicKeyframe: Equatable {
    let frameIndex: Int
    let time: Double
    let cropRect: CGRect
}

extension CropDynamicKeyframe {
    static func buildDynamicCropFilter(
        keyframes: [CropDynamicKeyframe],
        sourceSize: CGSize,
        sourceDuration: Double,
        trimStart: Double?,
        trimEnd: Double?,
        setptsFilter: String
    ) -> String? {
        let sorted = keyframes.sorted { lhs, rhs in
            if lhs.frameIndex == rhs.frameIndex { return lhs.time < rhs.time }
            return lhs.frameIndex < rhs.frameIndex
        }
        
        guard !sorted.isEmpty else { return nil }
        
        let sourceWidth = max(1, Int(sourceSize.width))
        let sourceHeight = max(1, Int(sourceSize.height))
        
        let clipStart = resolvedClipStart(trimStart: trimStart, sourceDuration: sourceDuration)
        let clipEnd = resolvedClipEnd(trimEnd: trimEnd, sourceDuration: sourceDuration, start: clipStart)
        let clipDuration = max(0.0, clipEnd - clipStart)
        guard clipDuration > 0 else { return nil }
        
        let trimFilter = "trim=start=\(dot(clipStart)):end=\(dot(clipEnd))"
        
        struct CropPoint {
            let initialTime: Double
            let x: Double
            let y: Double
            let w: Double
            let h: Double
        }
        
        let points: [CropPoint] = sorted.map { keyframe in
            let rect = clampRect(keyframe.cropRect)
            return CropPoint(
                initialTime: keyframe.time,
                x: Double(Int(rect.origin.x * CGFloat(sourceWidth))),
                y: Double(Int(rect.origin.y * CGFloat(sourceHeight))),
                w: Double(Int(rect.width * CGFloat(sourceWidth))),
                h: Double(Int(rect.height * CGFloat(sourceHeight)))
            )
        }
        
        guard let firstPoint = points.first else { return nil }
        
        if points.count == 1 {
            return "\(trimFilter),\(setptsFilter),crop='x=\(dot(firstPoint.x)):y=\(dot(firstPoint.y)):w=\(dot(firstPoint.w)):h=\(dot(firstPoint.h)):exact=1'"
        }
        
        let firstTime = firstPoint.initialTime - clipStart
        let nSects = points.count - 1
        let easeType = "easeInOutSine"
        var cropXExprParts: [String] = []
        var cropYExprParts: [String] = []
        
        for sect in 0..<nSects {
            let left = points[sect]
            let right = points[sect + 1]
            
            let startTime = (left.initialTime - clipStart) - firstTime
            var endTime = (right.initialTime - clipStart) - firstTime
            
            if sect == nSects - 1 {
                endTime = clipDuration
            }
            
            let sectDuration = endTime - startTime
            if sectDuration <= 0.0000001 { continue }
            
            let easeP = "((t-\(dot(startTime)))/\(dot(sectDuration)))"
            guard
                let easeX = getEasingExpression(
                    easingFunc: easeType,
                    easeA: "(\(dot(left.x)))",
                    easeB: "(\(dot(right.x)))",
                    easeP: easeP
                ),
                let easeY = getEasingExpression(
                    easingFunc: easeType,
                    easeA: "(\(dot(left.y)))",
                    easeB: "(\(dot(right.y)))",
                    easeP: easeP
                )
            else {
                continue
            }
            
            if sect == nSects - 1 {
                cropXExprParts.append("between(t, \(dot(startTime)), \(dot(endTime)))*\(easeX)")
                cropYExprParts.append("between(t, \(dot(startTime)), \(dot(endTime)))*\(easeY)")
            } else {
                cropXExprParts.append("(gte(t, \(dot(startTime)))*lt(t, \(dot(endTime))))*\(easeX)")
                cropYExprParts.append("(gte(t, \(dot(startTime)))*lt(t, \(dot(endTime))))*\(easeY)")
            }
        }
        
        guard !cropXExprParts.isEmpty, !cropYExprParts.isEmpty else { return nil }
        
        let cropW = dot(firstPoint.w)
        let cropH = dot(firstPoint.h)
        let cropXExpr = cropXExprParts.joined(separator: "+")
        let cropYExpr = cropYExprParts.joined(separator: "+")
        
        return "\(trimFilter),\(setptsFilter),crop='x=\(cropXExpr):y=\(cropYExpr):w=\(cropW):h=\(cropH):exact=1'"
    }
    
    private static func clampRect(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = max(0, min(1, r.origin.x))
        r.origin.y = max(0, min(1, r.origin.y))
        r.size.width = max(0.0001, min(1 - r.origin.x, r.size.width))
        r.size.height = max(0.0001, min(1 - r.origin.y, r.size.height))
        return r
    }
    
    private static func resolvedClipStart(trimStart: Double?, sourceDuration: Double) -> Double {
        if sourceDuration <= 0 {
            return max(0.0, trimStart ?? 0.0)
        }
        let rawStart = max(0.0, trimStart ?? 0.0)
        return min(rawStart, sourceDuration)
    }
    
    private static func resolvedClipEnd(trimEnd: Double?, sourceDuration: Double, start: Double) -> Double {
        let rawEnd: Double
        if let trimEnd {
            rawEnd = max(0.0, trimEnd)
        } else if sourceDuration > 0 {
            rawEnd = sourceDuration
        } else {
            rawEnd = start
        }
        
        if sourceDuration > 0 {
            return min(max(rawEnd, start), sourceDuration)
        }
        return max(rawEnd, start)
    }
    
    private static func getEasingExpression(
        easingFunc: String,
        easeA: String,
        easeB: String,
        easeP: String
    ) -> String? {
        let p = "(clip(\(easeP),0,1))"
        let t = "(2*\(p))"
        let m = "(\(p)-1)"
        
        if easingFunc == "instant" {
            return "if(lte(\(p),0),\(easeA),\(easeB))"
        }
        if easingFunc == "linear" {
            return "lerp(\(easeA), \(easeB), \(p))"
        }
        
        let ease: String
        if easingFunc == "easeInCubic" {
            ease = "\(p)^3"
        } else if easingFunc == "easeOutCubic" {
            ease = "1+\(m)^3"
        } else if easingFunc == "easeInOutCubic" {
            ease = "if(lt(\(t),1), \(p)*\(t)^2, 1+(\(m)^3)*4)"
        } else if easingFunc == "easeInOutSine" {
            ease = "0.5*(1-cos(\(p)*PI))"
        } else if easingFunc == "easeInCircle" {
            ease = "1-sqrt(1-\(p)^2)"
        } else if easingFunc == "easeOutCircle" {
            ease = "sqrt(1-\(m)^2)"
        } else if easingFunc == "easeInOutCircle" {
            ease = "if(lt(\(t),1), (1-sqrt(1-\(t)^2))*0.5, (sqrt(1-4*\(m)^2)+1)*0.5)"
        } else {
            return nil
        }
        
        return "(\(easeA)+(\(easeB)-\(easeA))*\(ease))"
    }
    
    private static func dot(_ value: Double) -> String {
        let invariant = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
        return invariant.replacingOccurrences(of: ",", with: ".")
    }
}
