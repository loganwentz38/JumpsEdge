//
//  JumpAnalysis.swift
//  JumpersEdge
//

import Foundation

struct JumpAnalysis: Sendable {
    let id: UUID
    let approachSpeed: Double   // meters per second (estimated)
    let takeoffAngle: Double    // degrees from vertical
    let airTime: Double         // seconds
    let date: Date
    let videoURL: URL

    init(id: UUID = UUID(),
         approachSpeed: Double,
         takeoffAngle: Double,
         airTime: Double,
         date: Date = Date(),
         videoURL: URL) {
        self.id = id
        self.approachSpeed = approachSpeed
        self.takeoffAngle = takeoffAngle
        self.airTime = airTime
        self.date = date
        self.videoURL = videoURL
    }
}
