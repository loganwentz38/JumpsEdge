//
//  VideoAnalyzer.swift
//  JumpersEdge
//

import AVFoundation
import Vision
import UIKit

nonisolated enum VideoAnalysisError: LocalizedError {
    case cannotReadAsset
    case noVideoTrack
    case cannotCreateReader
    case noBodyDetected
    case insufficientFrames
    case noTakeoffDetected

    var errorDescription: String? {
        switch self {
        case .cannotReadAsset: return "Cannot read the video file."
        case .noVideoTrack: return "No video track found in file."
        case .cannotCreateReader: return "Cannot create video reader."
        case .noBodyDetected: return "No human body detected in video."
        case .insufficientFrames: return "Not enough frames to analyze."
        case .noTakeoffDetected: return "Could not detect takeoff moment."
        }
    }
}

nonisolated class VideoAnalyzer {

    typealias ProgressHandler = (Float) -> Void
    typealias CompletionHandler = (Result<JumpAnalysis, Error>) -> Void

    /// Analyze a jump video and return a JumpAnalysis.
    func analyze(videoURL: URL,
                 athleteHeight: Double,
                 progress: @escaping ProgressHandler,
                 completion: @escaping CompletionHandler) {

        DispatchQueue.global(qos: .userInitiated).async {
            self.performAnalysis(
                videoURL: videoURL,
                athleteHeight: athleteHeight,
                progress: progress,
                completion: completion
            )
        }
    }

    // MARK: - Per-Frame Data

    private struct FrameData {
        let rootPosition: CGPoint
        let leftAnkleY: CGFloat
        let rightAnkleY: CGFloat
        let leftShoulderPosition: CGPoint
        let rightShoulderPosition: CGPoint
        let leftAnklePosition: CGPoint
        let rightAnklePosition: CGPoint
    }

    // MARK: - Analysis Pipeline

    private func performAnalysis(videoURL: URL,
                                 athleteHeight: Double,
                                 progress: @escaping ProgressHandler,
                                 completion: @escaping CompletionHandler) {

        let asset = AVAsset(url: videoURL)

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.noVideoTrack)) }
            return
        }

        let fps = videoTrack.nominalFrameRate
        guard fps > 0 else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.cannotReadAsset)) }
            return
        }

        let duration = CMTimeGetSeconds(asset.duration)
        let estimatedFrameCount = Int(duration * Double(fps))
        guard estimatedFrameCount > 10 else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.insufficientFrames)) }
            return
        }

        // Set up AVAssetReader
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard let reader = try? AVAssetReader(asset: asset) else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.cannotCreateReader)) }
            return
        }

        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)
        reader.startReading()

        var frames: [FrameData] = []
        var frameIndex = 0

        // Extract body pose from each frame
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                frameIndex += 1
                continue
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectHumanBodyPoseRequest()

            do {
                try handler.perform([request])
            } catch {
                frameIndex += 1
                continue
            }

            if let observation = request.results?.first {
                if let root = try? observation.recognizedPoint(.root),
                   let leftAnkle = try? observation.recognizedPoint(.leftAnkle),
                   let rightAnkle = try? observation.recognizedPoint(.rightAnkle),
                   let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
                   let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
                   root.confidence > 0.3 {

                    frames.append(FrameData(
                        rootPosition: root.location,
                        leftAnkleY: leftAnkle.location.y,
                        rightAnkleY: rightAnkle.location.y,
                        leftShoulderPosition: leftShoulder.location,
                        rightShoulderPosition: rightShoulder.location,
                        leftAnklePosition: leftAnkle.location,
                        rightAnklePosition: rightAnkle.location
                    ))
                }
            }

            frameIndex += 1
            if frameIndex % 5 == 0 {
                let p = Float(frameIndex) / Float(estimatedFrameCount)
                DispatchQueue.main.async { progress(min(p, 0.99)) }
            }
        }

        guard frames.count >= 10 else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.noBodyDetected)) }
            return
        }

        // Detect takeoff and landing
        let ankleYValues = frames.map { ($0.leftAnkleY + $0.rightAnkleY) / 2.0 }

        // Per-frame ankle Y velocity
        var ankleYVelocity: [CGFloat] = [0]
        for i in 1..<ankleYValues.count {
            ankleYVelocity.append(ankleYValues[i] - ankleYValues[i - 1])
        }

        // Baseline ankle Y from first ~10 frames
        let baselineCount = min(10, ankleYValues.count)
        let baselineAnkleY = ankleYValues.prefix(baselineCount).reduce(0, +) / CGFloat(baselineCount)

        // Takeoff: first frame where ankle Y exceeds baseline + threshold
        // with 3 consecutive positive velocity frames
        let takeoffThreshold: CGFloat = 0.02
        var takeoffFrame: Int?

        for i in 3..<ankleYVelocity.count {
            if ankleYValues[i] > baselineAnkleY + takeoffThreshold
                && ankleYVelocity[i] > 0
                && ankleYVelocity[i - 1] > 0
                && ankleYVelocity[i - 2] > 0 {
                takeoffFrame = i - 2
                break
            }
        }

        guard let takeoff = takeoffFrame else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.noTakeoffDetected)) }
            return
        }

        // Landing: after takeoff, first frame where ankle Y drops back near baseline
        var landingFrame = frames.count - 1
        for i in (takeoff + 3)..<ankleYValues.count {
            if ankleYValues[i] <= baselineAnkleY + takeoffThreshold / 2
                && ankleYVelocity[i] < 0 {
                landingFrame = i
                break
            }
        }

        // Calculate metrics
        let airTimeFrameCount = landingFrame - takeoff
        let airTime = Double(airTimeFrameCount) / Double(fps)

        // Approach speed from root horizontal displacement pre-takeoff
        let approachStart = max(0, takeoff - 15)
        let approachEnd = takeoff
        var approachSpeed: Double = 0.0

        if approachEnd > approachStart {
            let horizontalDisplacement = abs(
                frames[approachEnd].rootPosition.x - frames[approachStart].rootPosition.x
            )
            let approachFrameCount = approachEnd - approachStart
            let approachDuration = Double(approachFrameCount) / Double(fps)

            // Scale from normalized coords to real-world meters using athlete height
            let refFrame = frames[approachStart]
            let shoulderMid = CGPoint(
                x: (refFrame.leftShoulderPosition.x + refFrame.rightShoulderPosition.x) / 2,
                y: (refFrame.leftShoulderPosition.y + refFrame.rightShoulderPosition.y) / 2
            )
            let ankleMid = CGPoint(
                x: (refFrame.leftAnklePosition.x + refFrame.rightAnklePosition.x) / 2,
                y: (refFrame.leftAnklePosition.y + refFrame.rightAnklePosition.y) / 2
            )
            let bodyHeightNormalized = abs(shoulderMid.y - ankleMid.y)

            // shoulder-to-ankle is approximately 80% of total height
            let scale: Double
            if bodyHeightNormalized > 0.01 && athleteHeight > 0 {
                scale = (athleteHeight * 0.8) / Double(bodyHeightNormalized)
            } else {
                scale = 1.0
            }

            let realDisplacement = Double(horizontalDisplacement) * scale
            approachSpeed = approachDuration > 0 ? realDisplacement / approachDuration : 0
        }

        // Takeoff angle from shoulder-to-ankle line vs vertical at takeoff frame
        let takeoffFrameData = frames[takeoff]
        let shoulderMidTakeoff = CGPoint(
            x: (takeoffFrameData.leftShoulderPosition.x + takeoffFrameData.rightShoulderPosition.x) / 2,
            y: (takeoffFrameData.leftShoulderPosition.y + takeoffFrameData.rightShoulderPosition.y) / 2
        )
        let ankleMidTakeoff = CGPoint(
            x: (takeoffFrameData.leftAnklePosition.x + takeoffFrameData.rightAnklePosition.x) / 2,
            y: (takeoffFrameData.leftAnklePosition.y + takeoffFrameData.rightAnklePosition.y) / 2
        )

        let dx = Double(shoulderMidTakeoff.x - ankleMidTakeoff.x)
        let dy = Double(shoulderMidTakeoff.y - ankleMidTakeoff.y)

        let takeoffAngleRadians = atan2(abs(dx), dy)
        let takeoffAngleDegrees = takeoffAngleRadians * 180.0 / .pi

        let result = JumpAnalysis(
            approachSpeed: approachSpeed,
            takeoffAngle: takeoffAngleDegrees,
            airTime: airTime,
            videoURL: videoURL
        )

        DispatchQueue.main.async {
            progress(1.0)
            completion(.success(result))
        }
    }
}
