//
//  CropDynamicKeyframe.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 10/02/26.
//

import Foundation

struct CropDynamicKeyframe: Equatable {
    let time: Double
    let crop: String
}

extension CropDynamicKeyframe {
    static func buildDynamicCropFilter(
        keyframes: [CropDynamicKeyframe],
        sourceDuration: Double,
        trimStart: Double?,
        trimEnd: Double?,
        setptsFilter: String
    ) -> String? {
        let clipStart = resolvedClipStart(trimStart: trimStart, sourceDuration: sourceDuration)
        let clipEnd = resolvedClipEnd(trimEnd: trimEnd, sourceDuration: sourceDuration, start: clipStart)
        return buildDynamicCropFilter(
            start: clipStart,
            end: clipEnd,
            setptsFilter: setptsFilter,
            cropMap: keyframes
        )
    }

    
    private static func buildDynamicCropFilter(
        start: Double,
        end: Double,
        setptsFilter: String,
        cropMap: [CropDynamicKeyframe]
    ) -> String? {
        guard end > start else { return nil }
        let clipDuration = max(0.0, end - start)
        guard clipDuration > 0 else { return nil }

        let epsilon = 0.000001
        let sorted = cropMap
            .filter { point in point.time >= (start - epsilon) && point.time <= (end + epsilon) }
            .sorted { lhs, rhs in lhs.time < rhs.time }
        guard !sorted.isEmpty else { return nil }

        let parsedPoints = sorted.compactMap { keyframe -> (time: Double, crop: (x: Double, y: Double, w: Double, h: Double))? in
            guard let parsed = parseCrop(keyframe.crop) else { return nil }
            return (time: keyframe.time, crop: parsed)
        }
        guard parsedPoints.count == sorted.count else { return nil }

        let firstTime = parsedPoints[0].time
        let firstCrop = parsedPoints[0].crop
        if sorted.count == 1 {
            return "trim=0:\(dot(clipDuration)),crop='x=\(dot(firstCrop.x)):y=\(dot(firstCrop.y)):w=\(dot(firstCrop.w)):h=\(dot(firstCrop.h)):exact=1',settb=1/9000,\(setptsFilter)"
        }

        let nSects = sorted.count - 1
        let easeType = sorted.count > 8 ? "linear" : "easeInOutSine"
        var cropXExprParts: [String] = []
        var cropYExprParts: [String] = []
        var cropWExprParts: [String] = []
        var cropHExprParts: [String] = []
        for sect in 0..<nSects {
            let leftCrop = parsedPoints[sect].crop
            let rightCrop = parsedPoints[sect + 1].crop

            let startTime = parsedPoints[sect].time - firstTime
            var endTime = parsedPoints[sect + 1].time - firstTime
            if sect + 2 > nSects {
                endTime = clipDuration
            }

            let sectDuration = endTime - startTime
            if sectDuration <= 0.0000001 { continue }

            let easeP = "((t-\(dot(startTime)))/\(dot(sectDuration)))"
            guard
                let easeX = getEasingExpression(
                    easingFunc: easeType,
                    easeA: "(\(dot(leftCrop.x)))",
                    easeB: "(\(dot(rightCrop.x)))",
                    easeP: easeP
                ),
                let easeY = getEasingExpression(
                    easingFunc: easeType,
                    easeA: "(\(dot(leftCrop.y)))",
                    easeB: "(\(dot(rightCrop.y)))",
                    easeP: easeP
                ),
                let easeW = getEasingExpression(
                    easingFunc: easeType,
                    easeA: "(\(dot(leftCrop.w)))",
                    easeB: "(\(dot(rightCrop.w)))",
                    easeP: easeP
                ),
                let easeH = getEasingExpression(
                    easingFunc: easeType,
                    easeA: "(\(dot(leftCrop.h)))",
                    easeB: "(\(dot(rightCrop.h)))",
                    easeP: easeP
                )
            else {
                continue
            }

            if sect == nSects - 1 {
                cropXExprParts.append("between(t, \(dot(startTime)), \(dot(endTime)))*\(easeX)")
                cropYExprParts.append("between(t, \(dot(startTime)), \(dot(endTime)))*\(easeY)")
                cropWExprParts.append("between(t, \(dot(startTime)), \(dot(endTime)))*\(easeW)")
                cropHExprParts.append("between(t, \(dot(startTime)), \(dot(endTime)))*\(easeH)")
            } else {
                cropXExprParts.append("(gte(t, \(dot(startTime)))*lt(t, \(dot(endTime))))*\(easeX)")
                cropYExprParts.append("(gte(t, \(dot(startTime)))*lt(t, \(dot(endTime))))*\(easeY)")
                cropWExprParts.append("(gte(t, \(dot(startTime)))*lt(t, \(dot(endTime))))*\(easeW)")
                cropHExprParts.append("(gte(t, \(dot(startTime)))*lt(t, \(dot(endTime))))*\(easeH)")
            }
        }

        guard !cropXExprParts.isEmpty, !cropYExprParts.isEmpty else { return nil }

        let cropXExpr = cropXExprParts.joined(separator: "+")
        let cropYExpr = cropYExprParts.joined(separator: "+")
        let hasZoom = parsedPoints.contains { point in
            abs(point.crop.w - firstCrop.w) > epsilon || abs(point.crop.h - firstCrop.h) > epsilon
        }

        if !hasZoom {
            return "trim=0:\(dot(clipDuration)),crop='x=\(cropXExpr):y=\(cropYExpr):w=\(dot(firstCrop.w)):h=\(dot(firstCrop.h)):exact=1',settb=1/9000,\(setptsFilter)"
        }

        guard !cropWExprParts.isEmpty, !cropHExprParts.isEmpty else { return nil }
        let cropWExpr = cropWExprParts.joined(separator: "+")
        let cropHExpr = cropHExprParts.joined(separator: "+")

        // Zoom dinámico manteniendo salida estable:
        // escalamos según el tamaño interpolado del crop y luego recortamos al tamaño base.
        let zoomExpr = "min(\(dot(firstCrop.w))/max(\(cropWExpr),1),\(dot(firstCrop.h))/max(\(cropHExpr),1))"
        let scaledXExpr = "(\(cropXExpr))*\(zoomExpr)"
        let scaledYExpr = "(\(cropYExpr))*\(zoomExpr)"

        return "trim=0:\(dot(clipDuration)),scale=w='iw*\(zoomExpr)':h='ih*\(zoomExpr)':eval=frame,crop='x=\(scaledXExpr):y=\(scaledYExpr):w=\(dot(firstCrop.w)):h=\(dot(firstCrop.h)):exact=1',settb=1/9000,\(setptsFilter)"
    }

    private static func parseCrop(_ crop: String) -> (x: Double, y: Double, w: Double, h: Double)? {
        let parts = crop.split(separator: ":")
        guard parts.count == 4 else { return nil }

        guard
            let x = Double(parts[0]),
            let y = Double(parts[1]),
            let w = Double(parts[2]),
            let h = Double(parts[3])
        else {
            return nil
        }

        return (x, y, w, h)
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
