//
//  AppColors.swift
//  JumpersEdge
//
//  Kinetic Lab design system color tokens.
//

import UIKit

enum AppColors {

    // MARK: - Surfaces (dark, tonal layering)
    static let surface                   = UIColor(hex: "#0e0e0e") // root view backgrounds
    static let surfaceContainerLowest    = UIColor(hex: "#000000") // camera BG
    static let surfaceContainerLow       = UIColor(hex: "#131313") // nav bar
    static let surfaceContainer          = UIColor(hex: "#1a1a1a") // cards
    static let surfaceContainerHigh      = UIColor(hex: "#20201f") // jump cards, dividers
    static let surfaceContainerHighest   = UIColor(hex: "#262626") // input fields
    static let surfaceBright             = UIColor(hex: "#2c2c2c") // active states / modals

    // MARK: - Primary (Electric Lime)
    static let primaryContainer          = UIColor(hex: "#cafd00") // CTA button bg
    static let primaryFixed              = UIColor(hex: "#cafd00")
    static let primary                   = UIColor(hex: "#f3ffca") // lime body text
    static let primaryDim                = UIColor(hex: "#beee00") // pressed/hover state
    static let onPrimaryFixed            = UIColor(hex: "#3a4a00") // dark olive — text ON lime

    // MARK: - Secondary (High-Voltage Gold)
    static let secondary                 = UIColor(hex: "#fdbf35") // gold — PR moments / air time metric
    static let tertiaryContainer         = UIColor(hex: "#fce047") // amber

    // MARK: - Error / Destructive
    static let error                     = UIColor(hex: "#ff7351") // delete buttons, record button

    // MARK: - Text
    static let onSurface                 = UIColor(hex: "#ffffff") // primary text
    static let onSurfaceVariant          = UIColor(hex: "#adaaaa") // secondary text

    // MARK: - Structure
    static let outline                   = UIColor(hex: "#767575") // quaternary metric bar
    static let outlineVariant            = UIColor(hex: "#484847") // dividers, progress tracks
}

// MARK: - UIColor hex initializer

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8)  & 0xFF) / 255.0
        let b = CGFloat(int         & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
