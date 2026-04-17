//
//  TrimSegment.swift
//  LazyConverter
//
//  Created by Sebastián Agudelo on 15/04/26.
//

import Foundation

struct TrimSegment: Identifiable, Equatable, Comparable {
    let id: UUID
    var start: Double
    var end: Double
    
    init(id: UUID = UUID(), start: Double, end: Double) {
        self.id = id
        self.start = start
        self.end = end
    }
    
    var duration: Double {
        return max(0, end - start)
    }
    
    static func < (lhs: TrimSegment, rhs: TrimSegment) -> Bool {
        return lhs.start < rhs.start
    }
    
    static func == (lhs: TrimSegment, rhs: TrimSegment) -> Bool {
        return lhs.id == rhs.id && lhs.start == rhs.start && lhs.end == rhs.end
    }
}
