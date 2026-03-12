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
    var athletes: [Athlete] {
        return AthleteStore.shared.athletes
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Athletes"

        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.contentInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        // Disable automatic sizing so sizeForItemAt is used
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.estimatedItemSize = .zero
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView.reloadData()
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
        cell.configure(with: athletes[indexPath.item])
        return cell
    }

    // MARK: - Layout

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let inset = collectionView.contentInset.left + collectionView.contentInset.right
        let spacing: CGFloat = 12
        let width = (collectionView.bounds.width - inset - spacing * 2) / 3
        return CGSize(width: width, height: width * 1.3)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let detailVC = AthleteDetailViewController()
        detailVC.athlete = athletes[indexPath.item]
        detailVC.athleteIndex = indexPath.item
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 12
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 12
    }
}
