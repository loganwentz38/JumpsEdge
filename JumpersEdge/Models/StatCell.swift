//
//  StatCell.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 2/10/26.
//

import UIKit

class StatCell: UICollectionViewCell {

    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var speedLabel: UILabel!
    @IBOutlet weak var staminaLabel: UILabel!
    @IBOutlet weak var strengthLabel: UILabel!

    func configure(with athlete: Athlete) {
        nameLabel?.text = athlete.name
        speedLabel?.text = String(format: "Speed: %.1f", athlete.speed)
        staminaLabel?.text = String(format: "Stamina: %.1f", athlete.stamina)
        strengthLabel?.text = String(format: "Strength: %.1f", athlete.strength)
    }

}
