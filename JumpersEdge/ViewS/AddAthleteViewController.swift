//
//  AddAthleteViewController.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 3/7/26.
//

import UIKit

class AddAthleteViewController: UIViewController {

    private let firstNameField = UITextField()
    private let lastNameField = UITextField()
    private let eventSegment = UISegmentedControl(items: ["Long Jump", "Triple Jump", "Both"])
    private let heightField = UITextField()
    private let saveButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add Athlete"
        view.backgroundColor = .systemBackground
        setupForm()
    }

    // MARK: - UI Setup

    private func setupForm() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        // First Name
        let firstNameLabel = makeLabel("First Name")
        styleTextField(firstNameField, placeholder: "Enter first name")
        firstNameField.autocapitalizationType = .words

        // Last Name
        let lastNameLabel = makeLabel("Last Name")
        styleTextField(lastNameField, placeholder: "Enter last name")
        lastNameField.autocapitalizationType = .words

        // Event
        let eventLabel = makeLabel("Event")
        eventSegment.selectedSegmentIndex = 0

        // Height
        let heightLabel = makeLabel("Height (meters)")
        styleTextField(heightField, placeholder: "e.g. 1.83")
        heightField.keyboardType = .decimalPad

        // Save Button
        saveButton.setTitle("Save Athlete", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        saveButton.backgroundColor = .systemBlue
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.layer.cornerRadius = 10
        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        // Add to stack
        stack.addArrangedSubview(firstNameLabel)
        stack.addArrangedSubview(firstNameField)
        stack.addArrangedSubview(lastNameLabel)
        stack.addArrangedSubview(lastNameField)
        stack.addArrangedSubview(eventLabel)
        stack.addArrangedSubview(eventSegment)
        stack.addArrangedSubview(heightLabel)
        stack.addArrangedSubview(heightField)

        // Extra spacing before save button
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 12).isActive = true
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(saveButton)
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        return label
    }

    private func styleTextField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
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

        let athlete = Athlete(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName,
            event: selectedEvent,
            height: height
        )

        AthleteStore.shared.add(athlete)
        navigationController?.popViewController(animated: true)
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
