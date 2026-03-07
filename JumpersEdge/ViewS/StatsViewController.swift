//
//  StatsViewController.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 2/10/26.
//

import UIKit

class StatsViewController: UIViewController,
                           UICollectionViewDelegate,
                           UICollectionViewDataSource,
                           UICollectionViewDelegateFlowLayout {

    @IBOutlet weak var collectionView: UICollectionView!

    // MARK: - Athlete Data
    var athletes: [Athlete] = [
        Athlete(name: "Logan", speed: 8.2, stamina: 7.5, strength: 9.1),
        Athlete(name: "Mike", speed: 6.8, stamina: 8.9, strength: 7.0),
        Athlete(name: "Chris", speed: 9.0, stamina: 6.5, strength: 8.3),
        Athlete(name: "Sam", speed: 7.1, stamina: 9.2, strength: 6.4)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.delegate = self
        collectionView.dataSource = self

    }


    // MARK: - Collection View Data
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
            return 1
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            return athletes.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! StatCell

            // Configure the cell with athlete data
            let athlete = athletes[indexPath.item]
            cell.configure(with: athlete)

            return cell
        }

    // MARK: - 3 Column Layout

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        let spacing: CGFloat = 10
        let totalSpacing = spacing * 4
        let width = (collectionView.frame.width - totalSpacing) / 3

        return CGSize(width: width, height: width)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }
}
