//
//  ViewController.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 1/15/26.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Home screen setup (nothing special needed here yet)
    }

    @IBAction func viewStatsButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "goToStats", sender: self)
    }

    @IBAction func addAthleteButtonTapped(_ sender: UIButton) {
        // We will connect this later
        print("Add Athlete tapped")
    }
}
