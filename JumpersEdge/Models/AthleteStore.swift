//
//  AthleteStore.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 3/7/26.
//

import Foundation
import CoreData

class AthleteStore {
    static let shared = AthleteStore()

    private let context = CoreDataStack.shared.context

    var athletes: [Athlete] {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(request)
            return entities.map { entity in
                let event = JumpEvent(rawValue: entity.event ?? "Long Jump") ?? .longJump
                let videoPaths = entity.videoURLsData as? [String] ?? []
                let videoURLs = videoPaths.map { URL(fileURLWithPath: $0) }

                return Athlete(
                    firstName: entity.firstName ?? "",
                    lastName: entity.lastName ?? "",
                    event: event,
                    speed: entity.speed,
                    stamina: entity.stamina,
                    strength: entity.strength,
                    videoURLs: videoURLs
                )
            }
        } catch {
            print("Failed to fetch athletes: \(error.localizedDescription)")
            return []
        }
    }

    private init() {
        seedIfNeeded()
    }

    func add(_ athlete: Athlete) {
        let entity = AthleteEntity(context: context)
        entity.firstName = athlete.firstName
        entity.lastName = athlete.lastName
        entity.event = athlete.event.rawValue
        entity.speed = athlete.speed
        entity.stamina = athlete.stamina
        entity.strength = athlete.strength
        entity.videoURLsData = athlete.videoURLs.map { $0.path }
        entity.createdAt = Date()
        CoreDataStack.shared.saveContext()
    }

    func addVideo(_ url: URL, toAthleteAt index: Int) {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(request)
            guard entities.indices.contains(index) else { return }
            let entity = entities[index]
            var paths = entity.videoURLsData as? [String] ?? []
            paths.append(url.path)
            entity.videoURLsData = paths
            CoreDataStack.shared.saveContext()
        } catch {
            print("Failed to add video: \(error.localizedDescription)")
        }
    }

    // MARK: - Seed Data

    private func seedIfNeeded() {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        let count = (try? context.count(for: request)) ?? 0
        guard count == 0 else { return }

        let samples = [
            Athlete(firstName: "Logan", lastName: "", event: .longJump, speed: 8.2, stamina: 7.5, strength: 9.1),
            Athlete(firstName: "Mike", lastName: "", event: .tripleJump, speed: 6.8, stamina: 8.9, strength: 7.0),
            Athlete(firstName: "Chris", lastName: "", event: .both, speed: 9.0, stamina: 6.5, strength: 8.3),
            Athlete(firstName: "Sam", lastName: "", event: .longJump, speed: 7.1, stamina: 9.2, strength: 6.4),
        ]

        for athlete in samples {
            add(athlete)
        }
    }
}
