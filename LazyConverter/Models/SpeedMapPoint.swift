//
//  SpeedMapPoint.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 20/02/26.
//

import Foundation

struct SpeedMapPoint: Equatable, Hashable {
    let time: Double
    let speed: Double
}

extension SpeedMapPoint {
    private static let epsilon = 0.0000001
    private static let minSpeed = 0.01

    static func buildSpeedSetptsFilter(duration: Double, speed: Double, resetPTSWhenNoSpeed: Bool) -> String {
        let clampedSpeed = max(minSpeed, speed)
        guard clampedSpeed > 0 else {
            return resetPTSWhenNoSpeed ? "setpts=PTS-STARTPTS" : "setpts=PTS"
        }

        if abs(clampedSpeed - 1.0) < epsilon {
            return resetPTSWhenNoSpeed ? "setpts=PTS-STARTPTS" : "setpts=PTS"
        }

        if duration > epsilon {
            let points = [
                SpeedMapPoint(time: 0.0, speed: clampedSpeed),
                SpeedMapPoint(time: duration, speed: clampedSpeed)
            ]

            if let expression = buildSetptsExpressionFromSpeedPoints(points) {
                return "setpts='\(expression)/TB'"
            }
        }

        let base = resetPTSWhenNoSpeed ? "(PTS-STARTPTS)" : "PTS"
        return "setpts=\(dot(1.0 / clampedSpeed))*\(base)"
    }

    static func buildDynamicSpeedSetptsFilter(
        points: [SpeedMapPoint],
        clipStart: Double,
        clipEnd: Double
    ) -> String? {
        let normalizedPoints = normalize(points: points, clipStart: clipStart, clipEnd: clipEnd)
        guard normalizedPoints.count >= 2 else { return nil }
        guard let expression = buildSetptsExpressionFromSpeedPoints(normalizedPoints) else { return nil }
        return "setpts='\(expression)/TB'"
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

            let startSpeed = max(minSpeed, left.speed)
            let endSpeed = max(minSpeed, right.speed)
            let speedChange = endSpeed - startSpeed

            let sectionStart = left.time - speedMapStartTime
            let sectionEnd = right.time - speedMapStartTime
            let sectionDuration = sectionEnd - sectionStart

            if sectionDuration <= epsilon {
                continue
            }

            let x = speedChange / sectionDuration
            let y = startSpeed - (x * sectionStart)

            let sliceDuration: String
            if abs(speedChange) < epsilon || abs(x) < epsilon {
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

    private static func normalize(
        points: [SpeedMapPoint],
        clipStart: Double,
        clipEnd: Double
    ) -> [SpeedMapPoint] {
        guard clipEnd > clipStart else { return [] }

        var filtered = points
            .filter { point in
                point.time.isFinite && point.speed.isFinite &&
                point.time >= (clipStart - epsilon) &&
                point.time <= (clipEnd + epsilon)
            }
            .map { point in
                SpeedMapPoint(
                    time: min(max(point.time, clipStart), clipEnd),
                    speed: max(minSpeed, point.speed)
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.time - rhs.time) < epsilon {
                    return lhs.speed < rhs.speed
                }
                return lhs.time < rhs.time
            }

        guard !filtered.isEmpty else { return [] }

        var deduped: [SpeedMapPoint] = []
        deduped.reserveCapacity(filtered.count)
        for point in filtered {
            if let last = deduped.last, abs(last.time - point.time) < epsilon {
                deduped[deduped.count - 1] = point
            } else {
                deduped.append(point)
            }
        }

        guard !deduped.isEmpty else { return [] }

        if let first = deduped.first, first.time > (clipStart + epsilon) {
            deduped.insert(
                SpeedMapPoint(time: clipStart, speed: first.speed),
                at: 0
            )
        } else if let first = deduped.first, abs(first.time - clipStart) >= epsilon {
            deduped[0] = SpeedMapPoint(time: clipStart, speed: first.speed)
        }

        if let last = deduped.last, last.time < (clipEnd - epsilon) {
            deduped.append(SpeedMapPoint(time: clipEnd, speed: last.speed))
        } else if let last = deduped.last, abs(last.time - clipEnd) >= epsilon {
            deduped[deduped.count - 1] = SpeedMapPoint(time: clipEnd, speed: last.speed)
        }

        return deduped
    }

    private static func dot(_ value: Double) -> String {
        let invariant = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
        return invariant.replacingOccurrences(of: ",", with: ".")
    }
}
