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
    case landingNotDetected

    var errorDescription: String? {
        switch self {
        case .cannotReadAsset: return "Cannot read the video file."
        case .noVideoTrack: return "No video track found in file."
        case .cannotCreateReader: return "Cannot create video reader."
        case .noBodyDetected: return "No human body detected in video."
        case .insufficientFrames: return "Not enough frames to analyze."
        case .noTakeoffDetected: return "Could not detect takeoff moment."
        case .landingNotDetected: return "Could not detect landing — ensure the full jump is visible in the video."
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performAnalysis(
                videoURL: videoURL,
                athleteHeight: athleteHeight,
                progress: progress,
                completion: completion
            )
        }
    }

    // MARK: - Per-Frame Data

    private struct FrameData {
        let presentationTime: CMTime      // wall-clock time from the sample buffer
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
        // fps used here only for the estimated frame count used in progress reporting
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

        // Reuse request across frames — only the handler needs to be per-frame
        let poseRequest = VNDetectHumanBodyPoseRequest()

        // Extract body pose from each frame
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            // Capture presentation time before potentially skipping the frame
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                frameIndex += 1
                continue
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

            do {
                try handler.perform([poseRequest])
            } catch {
                frameIndex += 1
                continue
            }

            if let observation = poseRequest.results?.first {
                if let root = try? observation.recognizedPoint(.root),
                   let leftAnkle = try? observation.recognizedPoint(.leftAnkle),
                   let rightAnkle = try? observation.recognizedPoint(.rightAnkle),
                   let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
                   let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
                   root.confidence > 0.5,
                   leftAnkle.confidence > 0.5,
                   rightAnkle.confidence > 0.5,
                   leftShoulder.confidence > 0.5,
                   rightShoulder.confidence > 0.5 {

                    frames.append(FrameData(
                        presentationTime: presentationTime,
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

        // Bug C fix: use the minimum observed ankle Y as the ground reference.
        // The foot must touch the ground at some point in any valid video, so the
        // minimum Y across all frames is more robust than the first-N-frames average
        // (which can be taken mid-approach when the foot is already elevated).
        let baselineAnkleY = ankleYValues.min() ?? 0

        // Takeoff: first frame where ankle Y exceeds baseline + threshold,
        // confirmed by 3 consecutive positive velocity frames starting from that frame.
        let takeoffThreshold: CGFloat = 0.02
        var takeoffFrame: Int?

        for i in 3..<ankleYVelocity.count {
            // Bug B fix: require the first frame of the window (i-2) is still near
            // the ground (<=baseline+threshold), not already airborne. The original
            // condition (> baselineAnkleY) caused the takeoff to fire late because it
            // required the foot to already be visibly above the floor.
            if ankleYValues[i - 2] <= baselineAnkleY + takeoffThreshold
                && ankleYValues[i] > baselineAnkleY + takeoffThreshold
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
        var landingFrame: Int?
        for i in (takeoff + 3)..<ankleYValues.count {
            if ankleYValues[i] <= baselineAnkleY + takeoffThreshold / 2
                && ankleYVelocity[i] < 0 {
                landingFrame = i
                break
            }
        }

        guard let landing = landingFrame else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.landingNotDetected)) }
            return
        }

        // Bug A fix: use presentation timestamps instead of frame-count / fps.
        // Dropped frames (common in variable-frame-rate recordings) would cause the
        // fps-division approach to undercount elapsed time.
        let airTime = CMTimeGetSeconds(frames[landing].presentationTime - frames[takeoff].presentationTime)

        // Sanity cap: world-class long/triple jump air time is under 1.5s.
        // Anything beyond 2.0s means landing detection silently failed.
        guard airTime <= 2.0 else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.landingNotDetected)) }
            return
        }

        // Approach speed from root horizontal displacement pre-takeoff
        let approachStart = max(0, takeoff - 15)
        let approachEnd = takeoff
        var approachSpeed: Double = 0.0
        var scale: Double = 1.0  // kept in scope for measureStrideLength below

        if approachEnd > approachStart {
            let horizontalDisplacement = abs(
                frames[approachEnd].rootPosition.x - frames[approachStart].rootPosition.x
            )

            // Bug A fix: use presentation timestamps for approach duration too
            let approachDuration = CMTimeGetSeconds(
                frames[approachEnd].presentationTime - frames[approachStart].presentationTime
            )

            // Bug D fix: average body height across the full approach window instead
            // of reading a single potentially noisy reference frame. This is more
            // robust because the athlete may be partially cropped or leaning at any
            // single frame.
            let bodyHeightNormalized: CGFloat = {
                let approachRange = approachStart...approachEnd
                let heights = approachRange.compactMap { i -> CGFloat? in
                    let f = frames[i]
                    let sY = (f.leftShoulderPosition.y + f.rightShoulderPosition.y) / 2
                    let aY = (f.leftAnklePosition.y + f.rightAnklePosition.y) / 2
                    let h = abs(sY - aY)
                    // Discard frames where the body span is implausibly small
                    return h > 0.01 ? h : nil
                }
                guard !heights.isEmpty else { return 0 }
                return heights.reduce(0, +) / CGFloat(heights.count)
            }()

            // shoulder-to-ankle is approximately 80% of total height
            if bodyHeightNormalized > 0.01 && athleteHeight > 0 {
                scale = (athleteHeight * 0.8) / Double(bodyHeightNormalized)
            }

            let realDisplacement = Double(horizontalDisplacement) * scale
            approachSpeed = approachDuration > 0 ? realDisplacement / approachDuration : 0
        }

        // Stride length from foot plant detection over the approach window
        let approachFrames = Array(frames[approachStart..<approachEnd])
        let strideLength = measureStrideLength(
            approachFrames: approachFrames,
            athleteHeight: athleteHeight,
            scale: scale
        )

        let result = JumpAnalysis(
            approachSpeed: approachSpeed,
            strideLength: strideLength,
            airTime: airTime,
            videoURL: videoURL
        )

        DispatchQueue.main.async {
            progress(1.0)
            completion(.success(result))
        }
    }

    // MARK: - Stride Length Helpers

    /// Returns a smoothed version of `values` using a sliding-window average.
    private func smoothed(_ values: [CGFloat], window: Int) -> [CGFloat] {
        let half = window / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let slice = values[lo...hi]
            return slice.reduce(0, +) / CGFloat(slice.count)
        }
    }

    /// Returns the indices of local minima within `values`, where a minimum is
    /// strictly less than all neighbors within `halfWindow` on each side.
    private func localMinima(in values: [CGFloat], halfWindow: Int) -> [Int] {
        var minima: [Int] = []
        for i in halfWindow..<(values.count - halfWindow) {
            let candidate = values[i]
            let isMin = (1...halfWindow).allSatisfy {
                candidate < values[i - $0] && candidate < values[i + $0]
            }
            if isMin { minima.append(i) }
        }
        return minima
    }

    /// Estimates the average stride length (meters) from foot plant events in the approach.
    ///
    /// Strategy: smooth each ankle's Y signal, find local minima (foot-on-ground moments),
    /// sort plants chronologically, then measure horizontal distance between consecutive
    /// plants and convert to meters using the pre-computed pixel-to-meter scale.
    private func measureStrideLength(
        approachFrames: [FrameData],
        athleteHeight: Double,
        scale: Double
    ) -> Double {
        guard approachFrames.count >= 10 else { return 0.0 }

        // 5-frame smoothing window (~83ms at 60fps) suppresses jitter without
        // blurring true foot-plant events
        let smoothingWindow = 5
        let halfWindow = smoothingWindow

        let leftY  = smoothed(approachFrames.map { $0.leftAnkleY },  window: smoothingWindow)
        let rightY = smoothed(approachFrames.map { $0.rightAnkleY }, window: smoothingWindow)

        // Foot plants are local minima in each ankle's Y (lowest Y = closest to ground)
        let leftPlants  = localMinima(in: leftY,  halfWindow: halfWindow)
        let rightPlants = localMinima(in: rightY, halfWindow: halfWindow)

        struct PlantEvent {
            let frame: Int
            let ankleX: CGFloat
        }

        var plants: [PlantEvent] = []
        for f in leftPlants  { plants.append(PlantEvent(frame: f, ankleX: approachFrames[f].leftAnklePosition.x))  }
        for f in rightPlants { plants.append(PlantEvent(frame: f, ankleX: approachFrames[f].rightAnklePosition.x)) }
        plants.sort { $0.frame < $1.frame }

        // Need at least 3 plants to get 2 stride intervals
        guard plants.count >= 3 else { return 0.0 }

        // Measure horizontal distance between consecutive plants, convert to meters,
        // and discard any intervals outside the plausible human stride range (0.5–3.5m)
        var strideLengths: [Double] = []
        for i in 0..<(plants.count - 1) {
            let dx = abs(Double(plants[i + 1].ankleX - plants[i].ankleX))
            let realDx = dx * scale
            if realDx >= 0.5 && realDx <= 3.5 { strideLengths.append(realDx) }
        }

        guard strideLengths.count >= 2 else { return 0.0 }
        return strideLengths.reduce(0, +) / Double(strideLengths.count)
    }
}
