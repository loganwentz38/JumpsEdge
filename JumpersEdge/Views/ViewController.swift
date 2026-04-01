//
//  ViewController.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 1/15/26.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    private var selectedAthleteID: UUID?
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
            let alert = UIAlertController(
                title: "No Athletes",
                message: "Please add an athlete before recording a jump.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Add Athlete", style: .default) { [weak self] _ in
                self?.performSegue(withIdentifier: "goToAddAthlete", sender: self)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
            return
        }

        let sheet = UIAlertController(
            title: "Select Athlete",
            message: "Choose an athlete for this jump recording",
            preferredStyle: .actionSheet
        )

        for athlete in athletes {
            sheet.addAction(UIAlertAction(title: athlete.name, style: .default) { [weak self] _ in
                self?.selectedAthleteID = athlete.id
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
        let cameraVC = CameraViewController()
        cameraVC.modalPresentationStyle = .fullScreen
        cameraVC.onVideoRecorded = { [weak self] url in
            guard let self, let athleteID = self.selectedAthleteID else { return }
            self.selectedAthleteID = nil
            self.handleRecordedVideo(at: url, forAthleteID: athleteID)
        }
        present(cameraVC, animated: true)
    }

    private func handleRecordedVideo(at videoURL: URL, forAthleteID athleteID: UUID) {
        guard let athlete = AthleteStore.shared.athletes.first(where: { $0.id == athleteID }) else { return }
        analyzeVideo(at: videoURL, forAthleteID: athleteID, athleteHeight: athlete.height)
    }

    // MARK: - Video Analysis

    private func analyzeVideo(at url: URL, forAthleteID athleteID: UUID, athleteHeight: Double) {
        let progressAlert = UIAlertController(
            title: "Analyzing Jump",
            message: "Processing video...\n\n",
            preferredStyle: .alert
        )

        let progressView = UIProgressView(progressViewStyle: .bar)
        progressView.progressTintColor = AppColors.primaryContainer
        progressView.trackTintColor = AppColors.outlineVariant
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressAlert.view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: progressAlert.view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: progressAlert.view.trailingAnchor, constant: -20),
            progressView.bottomAnchor.constraint(equalTo: progressAlert.view.bottomAnchor, constant: -20),
        ])

        present(progressAlert, animated: true)

        analyzer.analyze(videoURL: url, athleteHeight: athleteHeight, progress: { value in
            DispatchQueue.main.async {
                progressView.setProgress(value, animated: true)
            }
        }) { [weak self] result in
            DispatchQueue.main.async {
                progressAlert.dismiss(animated: true) {
                    let athleteName = AthleteStore.shared.athletes.first(where: { $0.id == athleteID })?.name ?? "Athlete"
                    switch result {
                    case .success(let analysis):
                        AthleteStore.shared.addVideo(url, toAthleteID: athleteID)
                        AthleteStore.shared.addJumpAnalysis(analysis, toAthleteID: athleteID)
                        let strideLengthText = analysis.strideLength > 0
                            ? String(format: "%.2f m", analysis.strideLength)
                            : "—"
                        let message = String(
                            format: "Analysis complete for %@!\nApproach Speed: %.1f m/s\nAir Time: %.2f s\nStride Length: %@",
                            athleteName, analysis.approachSpeed, analysis.airTime, strideLengthText
                        )
                        self?.showAlert(message)

                    case .failure(let error):
                        try? FileManager.default.removeItem(at: url)
                        self?.showAlert("Analysis failed for \(athleteName): \(error.localizedDescription)")
                    }
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
