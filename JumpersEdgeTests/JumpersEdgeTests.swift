//
//  JumpersEdgeTests.swift
//  JumpersEdgeTests
//
//  Created by Logan Wentz on 1/15/26.
//

import Testing
@testable import JumpersEdge

struct AthleteTests {

    let dummyURL = URL(fileURLWithPath: "/tmp/video.mov")

    // MARK: - Name

    @Test func nameWithLastName() {
        let athlete = Athlete(firstName: "Logan", lastName: "Wentz", event: .longJump, height: 1.83)
        #expect(athlete.name == "Logan Wentz")
    }

    @Test func nameWithEmptyLastName() {
        let athlete = Athlete(firstName: "Logan", lastName: "", event: .longJump, height: 1.83)
        #expect(athlete.name == "Logan")
    }

    // MARK: - Aggregates with no analyses

    @Test func aggregatesAreNilWithNoJumps() {
        let athlete = Athlete(firstName: "A", lastName: "B", event: .tripleJump, height: 1.75)
        #expect(athlete.jumpCount == 0)
        #expect(athlete.averageApproachSpeed == nil)
        #expect(athlete.averageAirTime == nil)
        #expect(athlete.averageStrideLength == nil)
        #expect(athlete.consistencyScore == nil)
    }

    // MARK: - Aggregates with analyses

    @Test func averageApproachSpeed() {
        let analyses = [
            JumpAnalysis(approachSpeed: 8.0, strideLength: 2.1, airTime: 0.6, videoURL: dummyURL),
            JumpAnalysis(approachSpeed: 10.0, strideLength: 2.3, airTime: 0.8, videoURL: dummyURL)
        ]
        let athlete = Athlete(firstName: "A", lastName: "B", event: .longJump, height: 1.80, jumpAnalyses: analyses)
        #expect(athlete.averageApproachSpeed == 9.0)
    }

    @Test func averageAirTime() {
        let analyses = [
            JumpAnalysis(approachSpeed: 8.0, strideLength: 2.0, airTime: 0.5, videoURL: dummyURL),
            JumpAnalysis(approachSpeed: 9.0, strideLength: 2.0, airTime: 0.7, videoURL: dummyURL)
        ]
        let athlete = Athlete(firstName: "A", lastName: "B", event: .both, height: 1.80, jumpAnalyses: analyses)
        #expect(athlete.averageAirTime == 0.6)
    }

    @Test func averageStrideLengthExcludesZeros() {
        let analyses = [
            JumpAnalysis(approachSpeed: 8.0, strideLength: 0.0, airTime: 0.5, videoURL: dummyURL),
            JumpAnalysis(approachSpeed: 9.0, strideLength: 2.4, airTime: 0.6, videoURL: dummyURL),
            JumpAnalysis(approachSpeed: 9.5, strideLength: 2.6, airTime: 0.7, videoURL: dummyURL)
        ]
        let athlete = Athlete(firstName: "A", lastName: "B", event: .longJump, height: 1.80, jumpAnalyses: analyses)
        #expect(athlete.averageStrideLength == 2.5)
    }

    @Test func averageStrideLengthNilWhenAllZero() {
        let analyses = [
            JumpAnalysis(approachSpeed: 8.0, strideLength: 0.0, airTime: 0.5, videoURL: dummyURL)
        ]
        let athlete = Athlete(firstName: "A", lastName: "B", event: .longJump, height: 1.80, jumpAnalyses: analyses)
        #expect(athlete.averageStrideLength == nil)
    }

    // MARK: - Consistency score

    @Test func consistencyScoreNilWithOneJump() {
        let analyses = [
            JumpAnalysis(approachSpeed: 8.0, strideLength: 2.0, airTime: 0.6, videoURL: dummyURL)
        ]
        let athlete = Athlete(firstName: "A", lastName: "B", event: .longJump, height: 1.80, jumpAnalyses: analyses)
        #expect(athlete.consistencyScore == nil)
    }

    @Test func consistencyScorePerfectWhenIdentical() {
        let analyses = [
            JumpAnalysis(approachSpeed: 8.0, strideLength: 2.0, airTime: 0.6, videoURL: dummyURL),
            JumpAnalysis(approachSpeed: 9.0, strideLength: 2.1, airTime: 0.6, videoURL: dummyURL)
        ]
        let athlete = Athlete(firstName: "A", lastName: "B", event: .longJump, height: 1.80, jumpAnalyses: analyses)
        #expect(athlete.consistencyScore == 1.0)
    }

    @Test func consistencyScoreBetweenZeroAndOne() {
        let analyses = [
            JumpAnalysis(approachSpeed: 8.0, strideLength: 2.0, airTime: 0.4, videoURL: dummyURL),
            JumpAnalysis(approachSpeed: 9.0, strideLength: 2.1, airTime: 0.8, videoURL: dummyURL)
        ]
        let athlete = Athlete(firstName: "A", lastName: "B", event: .longJump, height: 1.80, jumpAnalyses: analyses)
        let score = athlete.consistencyScore!
        #expect(score > 0.0 && score < 1.0)
    }
}

struct JumpEventTests {

    @Test func allCases() {
        #expect(JumpEvent.allCases.count == 3)
    }

    @Test func rawValues() {
        #expect(JumpEvent.longJump.rawValue == "Long Jump")
        #expect(JumpEvent.tripleJump.rawValue == "Triple Jump")
        #expect(JumpEvent.both.rawValue == "Both")
    }
}
