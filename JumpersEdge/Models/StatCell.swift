//
//  StatCell.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 2/10/26.
//

import UIKit

class StatCell: UICollectionViewCell {

    // Kept for storyboard outlet connections — hidden in awakeFromNib
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var speedLabel: UILabel!
    @IBOutlet weak var staminaLabel: UILabel!
    @IBOutlet weak var strengthLabel: UILabel!

    // Custom card views
    private let avatarView = UIView()
    private let initialLabel = UILabel()
    private let athleteNameLabel = UILabel()
    private let divider = UIView()
    private var progressBars: [UIProgressView] = []
    private var valueLabels: [UILabel] = []

    override func awakeFromNib() {
        super.awakeFromNib()
        [nameLabel, speedLabel, staminaLabel, strengthLabel].forEach { $0?.isHidden = true }
        setupCard()
    }

    // MARK: - Card Setup

    private func setupCard() {
        // Card background
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 14
        contentView.layer.masksToBounds = true

        // Shadow on outer layer (not contentView, so it's visible outside clip bounds)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6
        layer.masksToBounds = false

        setupAvatar()
        setupNameLabel()
        setupDivider()
        setupStatRows()
    }

    private func setupAvatar() {
        avatarView.backgroundColor = .systemBlue
        avatarView.layer.cornerRadius = 22
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        initialLabel.font = .systemFont(ofSize: 18, weight: .bold)
        initialLabel.textColor = .white
        initialLabel.textAlignment = .center
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addSubview(initialLabel)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            initialLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
        ])
    }

    private func setupNameLabel() {
        athleteNameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        athleteNameLabel.textColor = .label
        athleteNameLabel.textAlignment = .center
        athleteNameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(athleteNameLabel)

        NSLayoutConstraint.activate([
            athleteNameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 8),
            athleteNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            athleteNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])
    }

    private func setupDivider() {
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: athleteNameLabel.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func setupStatRows() {
        let stats: [(String, UIColor)] = [
            ("Speed", .systemBlue),
            ("Stamina", .systemGreen),
            ("Strength", .systemOrange),
        ]

        var lastAnchor = divider.bottomAnchor

        for (name, color) in stats {
            let row = makeStatRow(name: name, color: color)
            contentView.addSubview(row)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: lastAnchor, constant: 10),
                row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                row.heightAnchor.constraint(equalToConstant: 20),
            ])

            lastAnchor = row.bottomAnchor
        }
    }

    private func makeStatRow(name: String, color: UIColor) -> UIStackView {
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabel
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let progress = UIProgressView(progressViewStyle: .bar)
        progress.tintColor = color
        progress.trackTintColor = UIColor.systemFill
        progress.layer.cornerRadius = 2
        progress.layer.masksToBounds = true
        progressBars.append(progress)

        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 12, weight: .bold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        valueLabels.append(valueLabel)

        let stack = UIStackView(arrangedSubviews: [nameLabel, progress, valueLabel])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - Configure

    func configure(with athlete: Athlete) {
        initialLabel.text = String(athlete.name.prefix(1)).uppercased()
        athleteNameLabel.text = athlete.name

        let values = [athlete.speed, athlete.stamina, athlete.strength]
        for (i, value) in values.enumerated() {
            progressBars[i].progress = Float(value / 10.0)
            valueLabels[i].text = String(format: "%.1f", value)
        }
    }
}
