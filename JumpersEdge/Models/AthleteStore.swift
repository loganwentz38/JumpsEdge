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

                // Convert JumpAnalysisEntity set to [JumpAnalysis]
                let analysisEntities = entity.jumpAnalyses?.allObjects as? [JumpAnalysisEntity] ?? []
                let analyses = analysisEntities
                    .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                    .map { ae in
                        JumpAnalysis(
                            id: ae.id ?? UUID(),
                            approachSpeed: ae.approachSpeed,
                            takeoffAngle: ae.takeoffAngle,
                            airTime: ae.airTime,
                            date: ae.date ?? Date(),
                            videoURL: URL(fileURLWithPath: ae.videoPath ?? "")
                        )
                    }

                return Athlete(
                    firstName: entity.firstName ?? "",
                    lastName: entity.lastName ?? "",
                    event: event,
                    height: entity.height,
                    jumpAnalyses: analyses,
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
        entity.height = athlete.height
        entity.videoURLsData = athlete.videoURLs.map { $0.path }
        entity.createdAt = Date()
        CoreDataStack.shared.saveContext()
    }

    func update(_ athlete: Athlete, at index: Int) {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(request)
            guard entities.indices.contains(index) else { return }
            let entity = entities[index]
            entity.firstName = athlete.firstName
            entity.lastName = athlete.lastName
            entity.event = athlete.event.rawValue
            entity.height = athlete.height
            entity.videoURLsData = athlete.videoURLs.map { $0.path }
            CoreDataStack.shared.saveContext()
        } catch {
            print("Failed to update athlete: \(error.localizedDescription)")
        }
    }

    func delete(at index: Int) {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(request)
            guard entities.indices.contains(index) else { return }
            let entity = entities[index]

            // Delete video files from legacy videoURLsData
            let videoPaths = entity.videoURLsData as? [String] ?? []
            let fileManager = FileManager.default
            for path in videoPaths {
                try? fileManager.removeItem(atPath: path)
            }

            // Delete video files referenced by JumpAnalysisEntity records
            // (The entities themselves are cascade-deleted by Core Data)
            let analyses = entity.jumpAnalyses?.allObjects as? [JumpAnalysisEntity] ?? []
            for analysis in analyses {
                if let path = analysis.videoPath {
                    try? fileManager.removeItem(atPath: path)
                }
            }

            context.delete(entity)
            CoreDataStack.shared.saveContext()
        } catch {
            print("Failed to delete athlete: \(error.localizedDescription)")
        }
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

    // MARK: - Jump Analysis

    func addJumpAnalysis(_ analysis: JumpAnalysis, toAthleteAt index: Int) {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(request)
            guard entities.indices.contains(index) else { return }
            let athleteEntity = entities[index]

            let analysisEntity = JumpAnalysisEntity(context: context)
            analysisEntity.id = analysis.id
            analysisEntity.approachSpeed = analysis.approachSpeed
            analysisEntity.takeoffAngle = analysis.takeoffAngle
            analysisEntity.airTime = analysis.airTime
            analysisEntity.date = analysis.date
            analysisEntity.videoPath = analysis.videoURL.path
            analysisEntity.athlete = athleteEntity

            CoreDataStack.shared.saveContext()
        } catch {
            print("Failed to add jump analysis: \(error.localizedDescription)")
        }
    }

    func deleteJumpAnalysis(id: UUID, fromAthleteAt index: Int) {
        let request: NSFetchRequest<JumpAnalysisEntity> = JumpAnalysisEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            let results = try context.fetch(request)
            if let entity = results.first {
                if let path = entity.videoPath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                context.delete(entity)
                CoreDataStack.shared.saveContext()
            }
        } catch {
            print("Failed to delete jump analysis: \(error.localizedDescription)")
        }
    }

    // MARK: - Seed Data

    private func seedIfNeeded() {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        let count = (try? context.count(for: request)) ?? 0
        guard count == 0 else { return }

        let samples = [
            Athlete(firstName: "Logan", lastName: "", event: .longJump, height: 1.83),
            Athlete(firstName: "Mike", lastName: "", event: .tripleJump, height: 1.78),
            Athlete(firstName: "Chris", lastName: "", event: .both, height: 1.91),
            Athlete(firstName: "Sam", lastName: "", event: .longJump, height: 1.75),
        ]

        for athlete in samples {
            add(athlete)
        }
    }
}
