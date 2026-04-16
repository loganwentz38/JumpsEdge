//
//  Logger+App.swift
//  JumpersEdge
//
//  Shared os.Logger instances for structured, release-safe logging.
//

import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "JumpersEdge"

    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let coreData = Logger(subsystem: subsystem, category: "coredata")
}
