//
//  SpeedMapPoint.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 20/02/26.
//

import Foundation

struct SpeedMapPoint: Equatable {
    let time: Double
    let speed: Double
}

extension SpeedMapPoint {
    static func buildSpeedSetptsFilter(duration: Double, speed: Double, resetPTSWhenNoSpeed: Bool) -> String {
        guard speed > 0 else {
            return resetPTSWhenNoSpeed ? "setpts=PTS-STARTPTS" : "setpts=PTS"
        }

        if abs(speed - 1.0) < 0.000001 {
            return resetPTSWhenNoSpeed ? "setpts=PTS-STARTPTS" : "setpts=PTS"
        }

        if duration > 0.000001 {
            let points = [
                SpeedMapPoint(time: 0.0, speed: speed),
                SpeedMapPoint(time: duration, speed: speed)
            ]

            if let expression = buildSetptsExpressionFromSpeedPoints(points) {
                return "setpts='\(expression)/TB'"
            }
        }

        let base = resetPTSWhenNoSpeed ? "(PTS-STARTPTS)" : "PTS"
        return "setpts=\(dot(1.0 / speed))*\(base)"
    }

    private static func buildSetptsExpressionFromSpeedPoints(_ points: [SpeedMapPoint]) -> String? {
        let sortedPoints = points.sorted { lhs, rhs in
            if lhs.time == rhs.time {
                return lhs.speed < rhs.speed
            }
            return lhs.time < rhs.time
        }

        guard sortedPoints.count >= 2 else { return nil }

        let speedMapStartTime = sortedPoints[0].time
        var setpts = ""
        var hasSections = false

        for i in 0..<(sortedPoints.count - 1) {
            let left = sortedPoints[i]
            let right = sortedPoints[i + 1]

            let startSpeed = max(0.000001, left.speed)
            let endSpeed = max(0.000001, right.speed)
            let speedChange = endSpeed - startSpeed

            let sectionStart = left.time - speedMapStartTime
            let sectionEnd = right.time - speedMapStartTime
            let sectionDuration = sectionEnd - sectionStart

            if sectionDuration <= 0.0000001 {
                continue
            }

            let x = speedChange / sectionDuration
            let y = startSpeed - (x * sectionStart)

            let sliceDuration: String
            if abs(speedChange) < 0.0000001 {
                sliceDuration = "(min((T-STARTT-(\(dot(sectionStart)))),\(dot(sectionDuration)))/\(dot(endSpeed)))"
            } else {
                sliceDuration = "(1/\(dot(x)))*(log(abs(\(dot(x))*min((T-STARTT),\(dot(sectionEnd)))+(\(dot(y)))))-log(abs(\(dot(x))*\(dot(sectionStart))+(\(dot(y))))))"
            }

            let guardedSlice = "if(gte((T-STARTT),\(dot(sectionStart))), \(sliceDuration),0)"

            if i == 0 {
                setpts.append("(if(eq(N,0),0,\(guardedSlice)))")
            } else {
                setpts.append("+(\(guardedSlice))")
            }

            hasSections = true
        }

        guard hasSections else { return nil }
        return "(\(setpts))"
    }

    private static func dot(_ value: Double) -> String {
        let invariant = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
        return invariant.replacingOccurrences(of: ",", with: ".")
    }
}
