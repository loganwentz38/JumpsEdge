//
//  VideoAnalyzerTests.swift
//  JumpersEdgeTests
//

import AVFoundation
import Foundation
import Testing
@testable import JumpersEdge

struct VideoAnalyzerTests {

    /// Regression test: VideoAnalyzer must do its frame-by-frame work off the
    /// main thread. The app target defaults types to @MainActor, so dropping
    /// `nonisolated` from VideoAnalyzer silently moved the loop onto the main
    /// thread and froze the UI for the whole analysis.
    @Test @MainActor func analysisKeepsMainThreadResponsive() async throws {
        let videoURL = try await makeBlankVideo(frameCount: 240, fps: 60)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let analyzer = VideoAnalyzer()
        let monitor = MainThreadStallMonitor()
        monitor.start()
        let result: Result<JumpAnalysis, Error> = await withCheckedContinuation { continuation in
            analyzer.analyze(videoURL: videoURL, athleteHeight: 1.8, progress: { _ in }) { result in
                continuation.resume(returning: result)
            }
        }
        monitor.stop()

        #expect(monitor.longestStall < 0.25, "Main thread stalled for \(monitor.longestStall)s during analysis")

        // A blank video has nobody in it, so analysis should fail with the
        // diagnostic no-body error rather than a misleading reader error.
        guard case .failure(let error) = result,
              case let .noBodyDetected(usableFrames, framesWithPerson, totalFrames)? = error as? VideoAnalysisError else {
            Issue.record("Expected noBodyDetected, got \(result)")
            return
        }
        #expect(usableFrames == 0)
        #expect(framesWithPerson == 0)
        #expect(totalFrames == 240)
        #expect(error.localizedDescription.hasPrefix("No person was detected"))
    }

    // MARK: - Helpers

    /// Writes a black H.264 video to a temporary file.
    private func makeBlankVideo(frameCount: Int, fps: Int32) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blank_\(UUID().uuidString).mov")
        let width = 640
        let height = 360

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pool = try #require(adaptor.pixelBufferPool)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            let buffer = try #require(pixelBuffer)

            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 0, CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }

        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed, "Video writer failed: \(String(describing: writer.error))")
        return url
    }
}

/// Records the longest gap between main-run-loop timer ticks.
@MainActor
private final class MainThreadStallMonitor {
    private var timer: Timer?
    private var lastTick = Date()
    private(set) var longestStall: TimeInterval = 0

    func start() {
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        tick()
    }

    private func tick() {
        let now = Date()
        longestStall = max(longestStall, now.timeIntervalSince(lastTick))
        lastTick = now
    }
}
