//
//  AthleteFormStyle.swift
//  JumpersEdge
//
//  Shared form UI helpers used by both AddAthleteViewController
//  and AthleteDetailViewController.
//

import UIKit

enum AthleteFormStyle {

    /// A standard form field label styled for the athlete forms.
    static func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = AppColors.onSurface
        return label
    }

    /// Applies the shared athlete-form text field styling and a 44pt height.
    static func styleTextField(_ field: UITextField, placeholder: String) {
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: AppColors.onSurfaceVariant]
        )
        field.borderStyle = .none
        field.backgroundColor = AppColors.surfaceContainerHighest
        field.textColor = AppColors.onSurface
        field.font = .systemFont(ofSize: 16)
        field.layer.cornerRadius = 8
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
}
