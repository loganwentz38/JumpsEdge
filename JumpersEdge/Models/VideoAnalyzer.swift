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
    case noBodyDetected(usableFrames: Int, framesWithPerson: Int, totalFrames: Int)
    case insufficientFrames
    case noTakeoffDetected
    case landingNotDetected

    var errorDescription: String? {
        switch self {
        case .cannotReadAsset: return "Cannot read the video file."
        case .noVideoTrack: return "No video track found in file."
        case .cannotCreateReader: return "Cannot create video reader."
        case let .noBodyDetected(usableFrames, framesWithPerson, totalFrames):
            if framesWithPerson == 0 {
                return "No person was detected in the video. Make sure the athlete is in frame and well lit."
            }
            return "The athlete's hips and ankles were only clearly visible in \(usableFrames) of \(totalFrames) frames. Keep the athlete's whole body, including their feet, in frame, film from the side, and hold the iPad still."
        case .insufficientFrames: return "Not enough frames to analyze."
        case .noTakeoffDetected: return "Could not detect takeoff moment."
        case .landingNotDetected: return "Could not detect landing — ensure the full jump is visible in the video."
        }
    }
}

// `nonisolated` is required: the target defaults every type to @MainActor
// (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor), so without it the whole
// frame-by-frame Vision loop runs on the main thread and freezes the UI.
nonisolated final class VideoAnalyzer {

    typealias ProgressHandler = (Float) -> Void
    typealias CompletionHandler = (Result<JumpAnalysis, Error>) -> Void

    /// Analyze a jump video and return a JumpAnalysis.
    func analyze(videoURL: URL,
                 athleteHeight: Double,
                 progress: @escaping ProgressHandler,
                 completion: @escaping CompletionHandler) {

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.performAnalysis(
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
        let shoulderY: CGFloat?           // nil when neither shoulder was confidently detected
        let leftAnklePosition: CGPoint
        let rightAnklePosition: CGPoint
    }

    // MARK: - Analysis Pipeline

    @concurrent
    private func performAnalysis(videoURL: URL,
                                 athleteHeight: Double,
                                 progress: @escaping ProgressHandler,
                                 completion: @escaping CompletionHandler) async {

        let asset = AVURLAsset(url: videoURL)

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.noVideoTrack)) }
            return
        }

        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let videoOrientation = cgImageOrientation(from: preferredTransform)

        let fps = (try? await videoTrack.load(.nominalFrameRate)) ?? 0
        guard fps > 0 else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.cannotReadAsset)) }
            return
        }

        let duration = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
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
        var framesWithPerson = 0        // frames where anyone was detected, for the error message
        var lastAthleteRoot: CGPoint?   // where the athlete was last seen, to keep following them

        // Reuse request across frames — only the handler needs to be per-frame
        let poseRequest = VNDetectHumanBodyPoseRequest()

        // Extract body pose from each frame
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            // Drain Vision's per-frame temporaries each iteration instead of
            // letting them accumulate for the length of the video.
            autoreleasepool {
                // Capture presentation time before potentially skipping the frame
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                    orientation: videoOrientation,
                                                    options: [:])

                do {
                    try handler.perform([poseRequest])
                } catch {
                    return
                }

                guard let observation = selectAthlete(from: poseRequest.results ?? [],
                                                      near: lastAthleteRoot) else { return }
                framesWithPerson += 1
                if let root = try? observation.recognizedPoint(.root), root.confidence > 0.1 {
                    lastAthleteRoot = root.location
                }

                if let frame = makeFrameData(from: observation, at: presentationTime) {
                    frames.append(frame)
                }
            }

            frameIndex += 1
            if frameIndex % 5 == 0 {
                let p = Float(frameIndex) / Float(estimatedFrameCount)
                DispatchQueue.main.async { progress(min(p, 0.99)) }
            }
        }

        // copyNextSampleBuffer() also returns nil when decoding fails partway
        // through; report that instead of blaming body detection.
        guard reader.status != .failed else {
            DispatchQueue.main.async { completion(.failure(VideoAnalysisError.cannotReadAsset)) }
            return
        }

        guard frames.count >= 10 else {
            let error = VideoAnalysisError.noBodyDetected(usableFrames: frames.count,
                                                          framesWithPerson: framesWithPerson,
                                                          totalFrames: frameIndex)
            DispatchQueue.main.async { completion(.failure(error)) }
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
                var heights = shoulderToAnkleSpans(in: frames[approachStart...approachEnd])
                // Shoulders are optional per frame; if none were visible during the
                // approach, fall back to the whole clip rather than losing the scale.
                if heights.isEmpty {
                    heights = shoulderToAnkleSpans(in: frames[...])
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

    // MARK: - Pose Helpers

    /// Picks the athlete when Vision finds several people (coaches, other
    /// jumpers, officials). Prefers whoever is nearest to where the athlete was
    /// last seen so tracking doesn't hop between people mid-jump; otherwise takes
    /// the person who appears tallest in frame. A lone person is always used.
    private func selectAthlete(from observations: [VNHumanBodyPoseObservation],
                               near lastRoot: CGPoint?) -> VNHumanBodyPoseObservation? {
        guard observations.count > 1 else { return observations.first }

        if let lastRoot {
            let nearest = observations
                .compactMap { observation -> (observation: VNHumanBodyPoseObservation, distance: CGFloat)? in
                    guard let root = try? observation.recognizedPoint(.root),
                          root.confidence > 0.1 else { return nil }
                    let distance = hypot(root.location.x - lastRoot.x, root.location.y - lastRoot.y)
                    return (observation, distance)
                }
                .min { $0.distance < $1.distance }

            // Normalized image distance. A sprinting athlete moves ~0.02 per frame,
            // so this tolerates several missed frames without switching people.
            if let nearest, nearest.distance < 0.2 {
                return nearest.observation
            }
        }

        return observations.max { apparentHeight(of: $0) < apparentHeight(of: $1) }
    }

    /// Vertical extent of a person's confidently detected joints, in normalized
    /// image coordinates — a proxy for how large they appear in frame.
    private func apparentHeight(of observation: VNHumanBodyPoseObservation) -> CGFloat {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        let ys = points.values.filter { $0.confidence > 0.1 }.map { $0.location.y }
        guard let lowest = ys.min(), let highest = ys.max() else { return 0 }
        return highest - lowest
    }

    /// Extracts the joints the analysis needs, or nil if the hips or either ankle
    /// weren't detected confidently. Shoulders are optional: in a side-on shot the
    /// far shoulder is often hidden, and they're only used to estimate body size.
    private func makeFrameData(from observation: VNHumanBodyPoseObservation,
                               at presentationTime: CMTime) -> FrameData? {
        guard let root = try? observation.recognizedPoint(.root),
              let leftAnkle = try? observation.recognizedPoint(.leftAnkle),
              let rightAnkle = try? observation.recognizedPoint(.rightAnkle),
              root.confidence > 0.3,
              leftAnkle.confidence > 0.3,
              rightAnkle.confidence > 0.3 else { return nil }

        let shoulderJoints: [VNHumanBodyPoseObservation.JointName] = [.leftShoulder, .rightShoulder]
        let shoulderYs: [CGFloat] = shoulderJoints.compactMap { joint in
            guard let shoulder = try? observation.recognizedPoint(joint),
                  shoulder.confidence > 0.2 else { return nil }
            return shoulder.location.y
        }
        let shoulderY = shoulderYs.isEmpty ? nil : shoulderYs.reduce(0, +) / CGFloat(shoulderYs.count)

        return FrameData(
            presentationTime: presentationTime,
            rootPosition: root.location,
            leftAnkleY: leftAnkle.location.y,
            rightAnkleY: rightAnkle.location.y,
            shoulderY: shoulderY,
            leftAnklePosition: leftAnkle.location,
            rightAnklePosition: rightAnkle.location
        )
    }

    /// Shoulder-to-ankle span for each frame where a shoulder was visible.
    private func shoulderToAnkleSpans(in frames: ArraySlice<FrameData>) -> [CGFloat] {
        frames.compactMap { f -> CGFloat? in
            guard let shoulderY = f.shoulderY else { return nil }
            let ankleY = (f.leftAnklePosition.y + f.rightAnklePosition.y) / 2
            let span = abs(shoulderY - ankleY)
            // Discard frames where the body span is implausibly small
            return span > 0.01 ? span : nil
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

    /// Maps a video track's preferredTransform to the CGImagePropertyOrientation
    /// that Vision needs to correctly interpret the pixel data.
    private func cgImageOrientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        if transform.a == 0 && transform.b == 1 && transform.c == -1 && transform.d == 0 {
            return .right           // portrait
        } else if transform.a == 0 && transform.b == -1 && transform.c == 1 && transform.d == 0 {
            return .left            // portrait upside down
        } else if transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1 {
            return .up              // landscape right (natural sensor orientation)
        } else if transform.a == -1 && transform.b == 0 && transform.c == 0 && transform.d == -1 {
            return .down            // landscape left
        }
        return .up                  // fallback: natural sensor orientation
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
        // blurring true foot-plant events.
        let smoothingWindow = 5

        // Minima search uses a wider window than the smoothing window to avoid
        // picking up local jitter as foot-plants. Each candidate must be lower
        // than every neighbor up to `minimaHalfWindow` frames away on each side,
        // yielding an effective 11-frame (±5) plant-detection window.
        let minimaHalfWindow = 5

        let leftY  = smoothed(approachFrames.map { $0.leftAnkleY },  window: smoothingWindow)
        let rightY = smoothed(approachFrames.map { $0.rightAnkleY }, window: smoothingWindow)

        // Foot plants are local minima in each ankle's Y (lowest Y = closest to ground)
        let leftPlants  = localMinima(in: leftY,  halfWindow: minimaHalfWindow)
        let rightPlants = localMinima(in: rightY, halfWindow: minimaHalfWindow)

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
