//
//  CameraViewController.swift
//  JumpersEdge
//

import UIKit
import AVFoundation

class CameraViewController: UIViewController {

    var onVideoRecorded: ((URL) -> Void)?

    private let session = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var selectedFrameRate: Int = 60
    private var isCancelling = false
    private var supports120fps = false

    // MARK: - Controls

    private let recordButton = UIButton()
    private let fpsToggle = UISegmentedControl(items: ["60fps", "120fps"])
    private let cancelButton = UIButton(type: .system)
    private let fpsUnavailableLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestPermissionsAndSetup()
        setupControls()
        setupOrientationObserver()
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
            device.unlockForConfiguration()
        } catch {
            print("Frame rate configuration failed: \(error)")
        }
    }

    // MARK: - Preview

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    // MARK: - Controls Setup

    private func setupControls() {
        // Record button
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.backgroundColor = .red
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

        NSLayoutConstraint.activate([
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
            recordButton.backgroundColor = .red
            recordButton.layer.cornerRadius = 36
            fpsToggle.isUserInteractionEnabled = true
            fpsUnavailableLabel.isHidden = supports120fps
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("JumpVideos", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let url = dir.appendingPathComponent("jump_\(UUID().uuidString).mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
            recordButton.backgroundColor = UIColor.red.withAlphaComponent(0.6)
            recordButton.layer.cornerRadius = 8
            fpsToggle.isUserInteractionEnabled = false
            fpsUnavailableLabel.isHidden = true
        }
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

    // MARK: - Orientation

    private func setupOrientationObserver() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil)
    }

    @objc private func orientationChanged() {
        guard let connection = previewLayer?.connection else { return }
        switch UIDevice.current.orientation {
        case .landscapeLeft:       connection.videoRotationAngle = 0
        case .landscapeRight:      connection.videoRotationAngle = 180
        case .portrait:            connection.videoRotationAngle = 90
        case .portraitUpsideDown:  connection.videoRotationAngle = 270
        default: break
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        session.stopRunning()
        DispatchQueue.main.async {
            self.dismiss(animated: true) {
                if !self.isCancelling && error == nil {
                    self.onVideoRecorded?(url)
                }
                if self.isCancelling {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}
