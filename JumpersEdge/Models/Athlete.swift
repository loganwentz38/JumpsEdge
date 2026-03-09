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
    let speed: Double
    let stamina: Double
    let strength: Double
    var videoURLs: [URL] = []

    var name: String {
        if lastName.isEmpty {
            return firstName
        }
        return firstName + " " + lastName
    }
}
