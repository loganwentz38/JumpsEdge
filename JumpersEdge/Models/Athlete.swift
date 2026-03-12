//
//  Athlete.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 2/10/26.
//

import Foundation

enum JumpEvent: String, CaseIterable {
    case longJump = "Long Jump"
    case tripleJump = "Triple Jump"
    case both = "Both"
}

struct Athlete {
    let firstName: String
    let lastName: String
    let event: JumpEvent
    let height: Double              // meters (e.g. 1.83)
    var jumpAnalyses: [JumpAnalysis] = []
    var videoURLs: [URL] = []

    var name: String {
        if lastName.isEmpty {
            return firstName
        }
        return firstName + " " + lastName
    }

    // MARK: - Computed Aggregate Stats

    var jumpCount: Int {
        jumpAnalyses.count
    }

    var averageApproachSpeed: Double? {
        guard !jumpAnalyses.isEmpty else { return nil }
        return jumpAnalyses.map(\.approachSpeed).reduce(0, +) / Double(jumpAnalyses.count)
    }

    var averageAirTime: Double? {
        guard !jumpAnalyses.isEmpty else { return nil }
        return jumpAnalyses.map(\.airTime).reduce(0, +) / Double(jumpAnalyses.count)
    }

    var averageTakeoffAngle: Double? {
        guard !jumpAnalyses.isEmpty else { return nil }
        return jumpAnalyses.map(\.takeoffAngle).reduce(0, +) / Double(jumpAnalyses.count)
    }

    /// Consistency score: 0.0 to 1.0.
    /// Computed as 1 - normalized standard deviation of air times.
    /// Returns nil if fewer than 2 jumps.
    var consistencyScore: Double? {
        guard jumpAnalyses.count >= 2,
              let avg = averageAirTime, avg > 0 else { return nil }
        let variance = jumpAnalyses.map { pow($0.airTime - avg, 2) }.reduce(0, +) / Double(jumpAnalyses.count)
        let stdDev = sqrt(variance)
        let coefficientOfVariation = stdDev / avg
        return max(0, min(1, 1.0 - coefficientOfVariation))
    }
}
