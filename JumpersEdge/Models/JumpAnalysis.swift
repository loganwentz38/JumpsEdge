//
//  JumpAnalysis.swift
//  JumpersEdge
//

import Foundation

struct JumpAnalysis: Sendable {
    let id: UUID
    let approachSpeed: Double   // meters per second (estimated)
    let strideLength: Double    // meters, average over approach; 0.0 if undetectable
    let airTime: Double         // seconds
    let date: Date
    let videoURL: URL

    nonisolated init(id: UUID = UUID(),
         approachSpeed: Double,
         strideLength: Double,
         airTime: Double,
         date: Date = Date(),
         videoURL: URL) {
        self.id = id
        self.approachSpeed = approachSpeed
        self.strideLength = strideLength
        self.airTime = airTime
        self.date = date
        self.videoURL = videoURL
    }
}
