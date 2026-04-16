//
//  AthleteStore.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 3/7/26.
//

import Foundation
import CoreData
import os

class AthleteStore {
    static let shared = AthleteStore()

    private let context = CoreDataStack.shared.context

    var athletes: [Athlete] {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(request)

            // Backfill UUIDs for athletes created before V3 migration in a single
            // pass, then save once. Previously this saved inside the map closure,
            // producing O(N) writes on first launch after migration.
            var needsSave = false
            for entity in entities where entity.id == nil {
                entity.id = UUID()
                needsSave = true
            }
            if needsSave { CoreDataStack.shared.saveContext() }

            return entities.compactMap { entity in
                guard let id = entity.id else { return nil }

                let event = JumpEvent(rawValue: entity.event ?? "Long Jump") ?? .longJump
                let videoPaths = entity.videoURLsData ?? []
                let videoURLs = videoPaths.map { URL(fileURLWithPath: $0) }

                let analysisEntities = entity.jumpAnalyses?.allObjects as? [JumpAnalysisEntity] ?? []
                let analyses = analysisEntities
                    .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                    .map { ae in
                        JumpAnalysis(
                            id: ae.id ?? UUID(),
                            approachSpeed: ae.approachSpeed,
                            strideLength: ae.strideLength,
                            airTime: ae.airTime,
                            date: ae.date ?? Date(),
                            videoURL: URL(fileURLWithPath: ae.videoPath ?? "")
                        )
                    }

                return Athlete(
                    id: id,
                    firstName: entity.firstName ?? "",
                    lastName: entity.lastName ?? "",
                    event: event,
                    height: entity.height,
                    jumpAnalyses: analyses,
                    videoURLs: videoURLs
                )
            }
        } catch {
            Logger.store.error("Failed to fetch athletes: \(error.localizedDescription)")
            return []
        }
    }

    private init() {
        seedIfNeeded()
    }

    // MARK: - CRUD

    func add(_ athlete: Athlete) {
        let entity = AthleteEntity(context: context)
        entity.id = athlete.id
        entity.firstName = athlete.firstName
        entity.lastName = athlete.lastName
        entity.event = athlete.event.rawValue
        entity.height = athlete.height
        entity.videoURLsData = athlete.videoURLs.map { $0.path }
        entity.createdAt = Date()
        CoreDataStack.shared.saveContext()
    }

    func update(_ athlete: Athlete) {
        guard let entity = entity(for: athlete.id) else { return }
        entity.firstName = athlete.firstName
        entity.lastName = athlete.lastName
        entity.event = athlete.event.rawValue
        entity.height = athlete.height
        entity.videoURLsData = athlete.videoURLs.map { $0.path }
        CoreDataStack.shared.saveContext()
    }

    func delete(id athleteID: UUID) {
        guard let entity = entity(for: athleteID) else { return }

        let videoPaths = entity.videoURLsData ?? []
        let fileManager = FileManager.default
        for path in videoPaths {
            try? fileManager.removeItem(atPath: path)
        }

        let analyses = entity.jumpAnalyses?.allObjects as? [JumpAnalysisEntity] ?? []
        for analysis in analyses {
            if let path = analysis.videoPath {
                try? fileManager.removeItem(atPath: path)
            }
        }

        context.delete(entity)
        CoreDataStack.shared.saveContext()
    }

    // MARK: - Video

    func addVideo(_ url: URL, toAthleteID athleteID: UUID) {
        guard let entity = entity(for: athleteID) else { return }
        var paths = entity.videoURLsData ?? []
        paths.append(url.path)
        entity.videoURLsData = paths
        CoreDataStack.shared.saveContext()
    }

    // MARK: - Jump Analysis

    func addJumpAnalysis(_ analysis: JumpAnalysis, toAthleteID athleteID: UUID) {
        guard let athleteEntity = entity(for: athleteID) else { return }

        let analysisEntity = JumpAnalysisEntity(context: context)
        analysisEntity.id = analysis.id
        analysisEntity.approachSpeed = analysis.approachSpeed
        analysisEntity.strideLength = analysis.strideLength
        analysisEntity.airTime = analysis.airTime
        analysisEntity.date = analysis.date
        analysisEntity.videoPath = analysis.videoURL.path
        analysisEntity.athlete = athleteEntity

        CoreDataStack.shared.saveContext()
    }

    func deleteJumpAnalysis(id analysisID: UUID) {
        let request: NSFetchRequest<JumpAnalysisEntity> = JumpAnalysisEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", analysisID as CVarArg)

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
            Logger.store.error("Failed to delete jump analysis: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func entity(for athleteID: UUID) -> AthleteEntity? {
        let request: NSFetchRequest<AthleteEntity> = AthleteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", athleteID as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
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
