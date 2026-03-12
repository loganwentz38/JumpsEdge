//
//  AthleteDetailViewController.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 3/10/26.
//

import UIKit
import AVKit

class AthleteDetailViewController: UIViewController {

    var athlete: Athlete!
    var athleteIndex: Int!

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let firstNameField = UITextField()
    private let lastNameField = UITextField()
    private let eventSegment = UISegmentedControl(items: ["Long Jump", "Triple Jump", "Both"])
    private let heightField = UITextField()

    private let saveButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit Athlete"
        view.backgroundColor = .systemBackground
        setupScrollView()
        setupForm()
        populateFields()
    }

    // MARK: - Layout

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -32),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -64),
        ])
    }

    private func setupForm() {
        // First Name
        contentStack.addArrangedSubview(makeLabel("First Name"))
        styleTextField(firstNameField, placeholder: "Enter first name")
        firstNameField.autocapitalizationType = .words
        contentStack.addArrangedSubview(firstNameField)

        // Last Name
        contentStack.addArrangedSubview(makeLabel("Last Name"))
        styleTextField(lastNameField, placeholder: "Enter last name")
        lastNameField.autocapitalizationType = .words
        contentStack.addArrangedSubview(lastNameField)

        // Event
        contentStack.addArrangedSubview(makeLabel("Event"))
        contentStack.addArrangedSubview(eventSegment)

        // Height
        contentStack.addArrangedSubview(makeLabel("Height (meters)"))
        styleTextField(heightField, placeholder: "e.g. 1.83")
        heightField.keyboardType = .decimalPad
        contentStack.addArrangedSubview(heightField)

        // Aggregate Stats Section
        contentStack.addArrangedSubview(makeSectionHeader("Jump Statistics"))
        contentStack.addArrangedSubview(makeStatsSection())

        // Jump History Section
        contentStack.addArrangedSubview(makeSectionHeader("Jump History"))
        contentStack.addArrangedSubview(makeJumpHistorySection())

        // Spacer
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        contentStack.addArrangedSubview(spacer)

        // Save Button
        saveButton.setTitle("Save Changes", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        saveButton.backgroundColor = .systemBlue
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.layer.cornerRadius = 10
        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(saveButton)

        // Delete Button
        deleteButton.setTitle("Delete Athlete", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        deleteButton.backgroundColor = .systemRed
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.layer.cornerRadius = 10
        deleteButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(deleteButton)
    }

    private func populateFields() {
        firstNameField.text = athlete.firstName
        lastNameField.text = athlete.lastName

        let events: [JumpEvent] = [.longJump, .tripleJump, .both]
        if let idx = events.firstIndex(of: athlete.event) {
            eventSegment.selectedSegmentIndex = idx
        }

        heightField.text = athlete.height > 0 ? String(format: "%.2f", athlete.height) : ""
    }

    // MARK: - Stats Section

    private func makeStatsSection() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8

        let stats: [(String, String)] = [
            ("Avg Approach Speed", formatOptional(athlete.averageApproachSpeed, format: "%.1f m/s")),
            ("Avg Air Time", formatOptional(athlete.averageAirTime, format: "%.2f s")),
            ("Avg Takeoff Angle", formatOptional(athlete.averageTakeoffAngle, format: "%.1f\u{00B0}")),
            ("Consistency", formatOptional(athlete.consistencyScore.map { $0 * 10 }, format: "%.1f / 10")),
            ("Total Jumps", "\(athlete.jumpCount)"),
        ]

        for (label, value) in stats {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .equalSpacing

            let nameLabel = UILabel()
            nameLabel.text = label
            nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
            nameLabel.textColor = .secondaryLabel

            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            valueLabel.textColor = .label
            valueLabel.textAlignment = .right

            row.addArrangedSubview(nameLabel)
            row.addArrangedSubview(valueLabel)
            stack.addArrangedSubview(row)
        }

        if athlete.jumpCount == 0 {
            let emptyLabel = UILabel()
            emptyLabel.text = "No jumps recorded yet. Record a jump to see statistics."
            emptyLabel.font = .systemFont(ofSize: 14)
            emptyLabel.textColor = .tertiaryLabel
            emptyLabel.numberOfLines = 0
            emptyLabel.textAlignment = .center
            stack.addArrangedSubview(emptyLabel)
        }

        return stack
    }

    // MARK: - Jump History

    private func makeJumpHistorySection() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        if athlete.jumpAnalyses.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No jumps recorded yet."
            emptyLabel.font = .systemFont(ofSize: 14)
            emptyLabel.textColor = .tertiaryLabel
            emptyLabel.textAlignment = .center
            stack.addArrangedSubview(emptyLabel)
            return stack
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for (index, analysis) in athlete.jumpAnalyses.reversed().enumerated() {
            let card = makeJumpCard(analysis: analysis, number: athlete.jumpAnalyses.count - index, dateFormatter: dateFormatter)
            stack.addArrangedSubview(card)
        }

        return stack
    }

    private func makeJumpCard(analysis: JumpAnalysis, number: Int, dateFormatter: DateFormatter) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 10

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        // Header: Jump # and date
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.distribution = .equalSpacing

        let titleLabel = UILabel()
        titleLabel.text = "Jump #\(number)"
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .label

        let dateLabel = UILabel()
        dateLabel.text = dateFormatter.string(from: analysis.date)
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .secondaryLabel

        headerRow.addArrangedSubview(titleLabel)
        headerRow.addArrangedSubview(dateLabel)
        stack.addArrangedSubview(headerRow)

        // Stat rows
        let metrics: [(String, String)] = [
            ("Approach Speed", String(format: "%.1f m/s", analysis.approachSpeed)),
            ("Air Time", String(format: "%.2f s", analysis.airTime)),
            ("Takeoff Angle", String(format: "%.1f\u{00B0}", analysis.takeoffAngle)),
        ]

        for (name, value) in metrics {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .equalSpacing

            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = .systemFont(ofSize: 13)
            nameLabel.textColor = .secondaryLabel

            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            valueLabel.textColor = .label

            row.addArrangedSubview(nameLabel)
            row.addArrangedSubview(valueLabel)
            stack.addArrangedSubview(row)
        }

        // Play Video button
        if FileManager.default.fileExists(atPath: analysis.videoURL.path) {
            let playButton = UIButton(type: .system)
            playButton.setTitle("Play Video", for: .normal)
            playButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            playButton.tag = analysis.videoURL.hashValue
            playButton.addTarget(self, action: #selector(playVideoTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(playButton)

            // Store the URL so we can retrieve it on tap
            objc_setAssociatedObject(playButton, &AssociatedKeys.videoURL, analysis.videoURL, .OBJC_ASSOCIATION_RETAIN)
        }

        return card
    }

    private struct AssociatedKeys {
        static var videoURL = "videoURL"
    }

    @objc private func playVideoTapped(_ sender: UIButton) {
        guard let url = objc_getAssociatedObject(sender, &AssociatedKeys.videoURL) as? URL else { return }
        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        present(playerVC, animated: true) {
            player.play()
        }
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        return label
    }

    private func makeSectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        return label
    }

    private func styleTextField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func formatOptional(_ value: Double?, format: String) -> String {
        guard let value = value else { return "—" }
        return String(format: format, value)
    }

    // MARK: - Save

    @objc private func saveTapped() {
        guard let firstName = firstNameField.text, !firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
            showAlert("Please enter a first name.")
            return
        }

        let lastName = lastNameField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let events: [JumpEvent] = [.longJump, .tripleJump, .both]
        let selectedEvent = events[eventSegment.selectedSegmentIndex]

        let heightText = heightField.text ?? "0"
        let height = Double(heightText) ?? 0

        let updated = Athlete(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName,
            event: selectedEvent,
            height: height,
            jumpAnalyses: athlete.jumpAnalyses,
            videoURLs: athlete.videoURLs
        )

        AthleteStore.shared.update(updated, at: athleteIndex)
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Delete

    @objc private func deleteTapped() {
        let alert = UIAlertController(
            title: "Delete \(athlete.name)?",
            message: "This will permanently remove this athlete and all their data, including recorded videos. This action cannot be undone.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            AthleteStore.shared.delete(at: self.athleteIndex)
            self.navigationController?.popViewController(animated: true)
        })

        present(alert, animated: true)
    }

    // MARK: - Alert

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
