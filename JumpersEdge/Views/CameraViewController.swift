//
//  CameraViewController.swift
//  JumpersEdge
//

import UIKit
import AVFoundation
import os

class CameraViewController: UIViewController {

    var onVideoRecorded: ((URL) -> Void)?

    private let session = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var selectedFrameRate: Int = 60
    private var isCancelling = false
    private var supports120fps = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?

    /// Longest shutter time auto-exposure may use. At the default (up to 1/60s
    /// at 60fps) a sprinter's ankles smear across the frame and Vision can't
    /// place them. Auto-exposure raises ISO to compensate; shorten this for
    /// outdoor-only use, lengthen it if indoor footage comes out too dark.
    private static let maxExposureDuration = CMTime(value: 1, timescale: 250)

    // MARK: - Controls

    private let recordButton = UIButton()
    private let fpsToggle = UISegmentedControl(items: ["60fps", "120fps"])
    private let cancelButton = UIButton(type: .system)
    private let fpsUnavailableLabel = UILabel()
    private let cameraUnavailableLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.surfaceContainerLowest
        requestPermissionsAndSetup()
        setupControls()
        observeSessionInterruptions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Permissions

    private func requestPermissionsAndSetup() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] videoGranted in
            guard videoGranted else {
                DispatchQueue.main.async { self?.showPermissionDeniedAlert() }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                // Audio is best-effort; proceed regardless
                DispatchQueue.main.async {
                    self?.setupSession()
                    self?.setupPreview()
                }
            }
        }
    }

    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to record jumps.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - Session Setup

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        // Check 120fps availability for UI state
        supports120fps = device.formats.contains { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supportsFPS = format.videoSupportedFrameRateRanges.contains {
                $0.maxFrameRate >= 120
            }
            return dims.width >= 1920 && supportsFPS
        }

        configureFrameRate(device: device, fps: 60)
        session.commitConfiguration()
    }

    private func configureFrameRate(device: AVCaptureDevice, fps: Int) {
        let formats = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supportsFPS = format.videoSupportedFrameRateRanges.contains {
                $0.maxFrameRate >= Double(fps)
            }
            return dims.width >= 1920 && supportsFPS
        }

        guard let best = formats.last else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            limitExposureDuration(device: device)
            device.unlockForConfiguration()
        } catch {
            Logger.camera.error("Frame rate configuration failed: \(error.localizedDescription)")
        }
    }

    /// Caps auto-exposure's shutter time to reduce motion blur. Must be called
    /// while the device is locked for configuration and after `activeFormat` is
    /// set, because changing the format resets the cap.
    private func limitExposureDuration(device: AVCaptureDevice) {
        let format = device.activeFormat
        // Setting a value outside the format's supported range throws, so clamp.
        device.activeMaxExposureDuration = CMTimeMaximum(
            format.minExposureDuration,
            CMTimeMinimum(Self.maxExposureDuration, format.maxExposureDuration)
        )
    }

    // MARK: - Preview

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        setupRotationCoordinator()
    }

    // MARK: - Rotation

    /// Uses RotationCoordinator (gravity-based) instead of UIDevice orientation,
    /// which reports faceUp/faceDown/unknown when the phone is flat or tilted
    /// down — common when filming a runway from stands — leaving the recorded
    /// file's rotation metadata wrong and breaking body-pose detection.
    private func setupRotationCoordinator() {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                guard let connection = self?.previewLayer?.connection,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }
    }

    // MARK: - Controls Setup

    private func setupControls() {
        // Record button
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.backgroundColor = AppColors.error
        recordButton.layer.cornerRadius = 36
        recordButton.layer.borderWidth = 4
        recordButton.layer.borderColor = UIColor.white.cgColor
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        view.addSubview(recordButton)

        // FPS toggle
        fpsToggle.translatesAutoresizingMaskIntoConstraints = false
        fpsToggle.selectedSegmentIndex = 0
        fpsToggle.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        fpsToggle.selectedSegmentTintColor = .white
        let normalAttr: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        let selectedAttr: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.black]
        fpsToggle.setTitleTextAttributes(normalAttr, for: .normal)
        fpsToggle.setTitleTextAttributes(selectedAttr, for: .selected)
        fpsToggle.addTarget(self, action: #selector(switchFrameRate(_:)), for: .valueChanged)
        fpsToggle.setEnabled(supports120fps, forSegmentAt: 1)
        view.addSubview(fpsToggle)

        // 120fps unavailable label
        fpsUnavailableLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsUnavailableLabel.text = "120fps not available on this device"
        fpsUnavailableLabel.font = .systemFont(ofSize: 12)
        fpsUnavailableLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        fpsUnavailableLabel.isHidden = supports120fps
        view.addSubview(fpsUnavailableLabel)

        // Cancel button
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        // Explains why recording is blocked while the camera is interrupted
        cameraUnavailableLabel.translatesAutoresizingMaskIntoConstraints = false
        cameraUnavailableLabel.font = .systemFont(ofSize: 17, weight: .medium)
        cameraUnavailableLabel.textColor = .white
        cameraUnavailableLabel.textAlignment = .center
        cameraUnavailableLabel.numberOfLines = 0
        cameraUnavailableLabel.isHidden = true
        view.addSubview(cameraUnavailableLabel)

        NSLayoutConstraint.activate([
            cameraUnavailableLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cameraUnavailableLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cameraUnavailableLabel.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -64),

            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            recordButton.widthAnchor.constraint(equalToConstant: 72),
            recordButton.heightAnchor.constraint(equalToConstant: 72),

            fpsToggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fpsToggle.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -24),
            fpsToggle.widthAnchor.constraint(equalToConstant: 200),

            fpsUnavailableLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fpsUnavailableLabel.topAnchor.constraint(equalTo: fpsToggle.bottomAnchor, constant: 6),

            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func switchFrameRate(_ sender: UISegmentedControl) {
        guard !movieOutput.isRecording else { return }
        selectedFrameRate = sender.selectedSegmentIndex == 0 ? 60 : 120
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        session.beginConfiguration()
        configureFrameRate(device: device, fps: selectedFrameRate)
        session.commitConfiguration()
    }

    @objc private func toggleRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            updateRecordingUI(isRecording: false)
        } else {
            // startRecording raises an exception (crashing the app) when the video
            // connection isn't live — before setup finishes or while interrupted.
            guard let movieConnection = movieOutput.connection(with: .video),
                  movieConnection.isActive,
                  movieConnection.isEnabled else {
                showAlert(title: "Camera Not Ready",
                          message: "The camera isn't ready to record yet. Try again in a moment.")
                return
            }

            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("JumpVideos", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let url = dir.appendingPathComponent("jump_\(UUID().uuidString).mov")

            // Ensure the recorded video has the correct orientation before starting.
            // The angle is fixed for the duration of the recording so the file's
            // rotation metadata stays consistent even if the phone rotates mid-jump.
            if let coordinator = rotationCoordinator {
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                if movieConnection.isVideoRotationAngleSupported(angle) {
                    movieConnection.videoRotationAngle = angle
                }
            }

            movieOutput.startRecording(to: url, recordingDelegate: self)
            updateRecordingUI(isRecording: true)
        }
    }

    private func updateRecordingUI(isRecording: Bool) {
        if isRecording {
            recordButton.backgroundColor = AppColors.error.withAlphaComponent(0.6)
            recordButton.layer.cornerRadius = 8
            fpsToggle.isUserInteractionEnabled = false
            fpsUnavailableLabel.isHidden = true
        } else {
            recordButton.backgroundColor = AppColors.error
            recordButton.layer.cornerRadius = 36
            fpsToggle.isUserInteractionEnabled = true
            fpsUnavailableLabel.isHidden = supports120fps
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func cancelTapped() {
        if movieOutput.isRecording {
            isCancelling = true
            movieOutput.stopRecording()
            // Teardown happens in fileOutput(_:didFinishRecordingTo:)
        } else {
            session.stopRunning()
            dismiss(animated: true)
        }
    }

    // MARK: - Interruptions

    /// The camera can be taken away mid-session: iPad multitasking (Split View,
    /// Slide Over, Stage Manager), another app using the camera, or overheating.
    /// While that lasts, show why and block recording.
    private func observeSessionInterruptions() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted(_:)),
                                               name: AVCaptureSession.wasInterruptedNotification,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded(_:)),
                                               name: AVCaptureSession.interruptionEndedNotification,
                                               object: session)
    }

    // AVFoundation doesn't promise these arrive on the main thread.
    @objc private nonisolated func sessionWasInterrupted(_ notification: Notification) {
        let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
            .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        let message = Self.interruptionMessage(for: reason)
        DispatchQueue.main.async {
            self.setCameraUnavailableMessage(message)
        }
    }

    @objc private nonisolated func sessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async {
            self.setCameraUnavailableMessage(nil)
        }
    }

    private nonisolated static func interruptionMessage(for reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "The camera isn't available while Jumpers Edge shares the screen with other apps. Make it full screen to record."
        case .videoDeviceInUseByAnotherClient:
            return "The camera is being used by another app."
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "The camera paused because the iPad is too hot. Let it cool down, then try again."
        default:
            return "The camera is temporarily unavailable."
        }
    }

    /// Pass nil once the camera is available again.
    private func setCameraUnavailableMessage(_ message: String?) {
        cameraUnavailableLabel.text = message
        cameraUnavailableLabel.isHidden = message == nil
        recordButton.isEnabled = message == nil
        recordButton.alpha = message == nil ? 1.0 : 0.4
    }

}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // An error doesn't always mean the clip is lost: when recording is cut
        // short (app backgrounded, camera interrupted, storage nearly full),
        // AVFoundation still finalizes a playable file and says so in userInfo.
        let recordingIsUsable: Bool = {
            guard let error else { return true }
            return (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
        }()

        if recordingIsUsable {
            session.stopRunning()
        }
        DispatchQueue.main.async {
            if !recordingIsUsable && !self.isCancelling {
                // Stay on the camera so the coach can record again right away.
                try? FileManager.default.removeItem(at: url)
                self.updateRecordingUI(isRecording: false)
                self.showAlert(title: "Recording Failed",
                               message: "\(error?.localizedDescription ?? "The video couldn't be saved.")\n\nPlease try again.")
                return
            }
            self.dismiss(animated: true) {
                if self.isCancelling {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    self.onVideoRecorded?(url)
                }
            }
        }
    }
}
