//
//  ViewController.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 1/15/26.
//

import UIKit
import UniformTypeIdentifiers
import AVFoundation

class ViewController: UIViewController,
                      UIImagePickerControllerDelegate,
                      UINavigationControllerDelegate {

    private var selectedAthleteIndex: Int?
    private let analyzer = VideoAnalyzer()

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func viewStatsButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "goToStats", sender: self)
    }

    @IBAction func addAthleteButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "goToAddAthlete", sender: self)
    }

    @IBAction func recordJumpButtonTapped(_ sender: UIButton) {
        let athletes = AthleteStore.shared.athletes
        guard !athletes.isEmpty else {
            showAlert("No athletes available. Please add an athlete first.")
            return
        }

        let sheet = UIAlertController(
            title: "Select Athlete",
            message: "Choose an athlete for this jump recording",
            preferredStyle: .actionSheet
        )

        for (index, athlete) in athletes.enumerated() {
            sheet.addAction(UIAlertAction(title: athlete.name, style: .default) { [weak self] _ in
                self?.selectedAthleteIndex = index
                self?.presentCamera()
            })
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }

        present(sheet, animated: true)
    }

    // MARK: - Camera

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showAlert("Camera is not available on this device.")
            return
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeMedium
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)

        guard let videoURL = info[.mediaURL] as? URL,
              let athleteIndex = selectedAthleteIndex else { return }

        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let jumpVideosDir = documentsDir.appendingPathComponent("JumpVideos", isDirectory: true)

        if !fileManager.fileExists(atPath: jumpVideosDir.path) {
            try? fileManager.createDirectory(at: jumpVideosDir, withIntermediateDirectories: true)
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "jump_\(timestamp).mov"
        let destinationURL = jumpVideosDir.appendingPathComponent(fileName)

        do {
            try fileManager.moveItem(at: videoURL, to: destinationURL)
            AthleteStore.shared.addVideo(destinationURL, toAthleteAt: athleteIndex)

            // Trigger Vision analysis
            let athlete = AthleteStore.shared.athletes[athleteIndex]
            analyzeVideo(at: destinationURL, forAthleteAt: athleteIndex, athleteHeight: athlete.height)
        } catch {
            showAlert("Failed to save video: \(error.localizedDescription)")
        }

        selectedAthleteIndex = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        selectedAthleteIndex = nil
    }

    // MARK: - Video Analysis

    private func analyzeVideo(at url: URL, forAthleteAt index: Int, athleteHeight: Double) {
        let progressAlert = UIAlertController(
            title: "Analyzing Jump",
            message: "Processing video...\n\n",
            preferredStyle: .alert
        )

        let progressView = UIProgressView(progressViewStyle: .bar)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressAlert.view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: progressAlert.view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: progressAlert.view.trailingAnchor, constant: -20),
            progressView.bottomAnchor.constraint(equalTo: progressAlert.view.bottomAnchor, constant: -20),
        ])

        present(progressAlert, animated: true)

        analyzer.analyze(videoURL: url, athleteHeight: athleteHeight, progress: { value in
            progressView.setProgress(value, animated: true)
        }) { [weak self] result in
            progressAlert.dismiss(animated: true) {
                switch result {
                case .success(let analysis):
                    AthleteStore.shared.addJumpAnalysis(analysis, toAthleteAt: index)
                    let athleteName = AthleteStore.shared.athletes[index].name
                    let message = String(
                        format: "Analysis complete for %@!\nApproach Speed: %.1f m/s\nAir Time: %.2f s\nTakeoff Angle: %.1f\u{00B0}",
                        athleteName, analysis.approachSpeed, analysis.airTime, analysis.takeoffAngle
                    )
                    self?.showAlert(message)

                case .failure(let error):
                    let athleteName = AthleteStore.shared.athletes[index].name
                    self?.showAlert("Video saved for \(athleteName), but analysis failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Alerts

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
