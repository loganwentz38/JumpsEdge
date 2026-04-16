//
//  CoreDataStack.swift
//  JumpersEdge
//
//  Created by Logan Wentz on 3/9/26.
//

import CoreData
import os

class CoreDataStack {
    static let shared = CoreDataStack()

    let persistentContainer: NSPersistentContainer

    private init() {
        persistentContainer = NSPersistentContainer(name: "JumpersEdge")

        // Enable lightweight migration
        if let description = persistentContainer.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        persistentContainer.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true

        // Post-migration cleanup: any rows that held a takeoffAngle value (0–90°)
        // now live in the strideLength column. Valid stride lengths are 0–3.5m, so
        // clamp anything implausibly large (>10.0) to 0.0 to mark it as undetectable.
        let context = persistentContainer.viewContext
        let batchUpdate = NSBatchUpdateRequest(entityName: "JumpAnalysisEntity")
        batchUpdate.predicate = NSPredicate(format: "strideLength > 10.0")
        batchUpdate.propertiesToUpdate = ["strideLength": 0.0]
        batchUpdate.resultType = .updatedObjectIDsResultType
        _ = try? context.execute(batchUpdate)
    }

    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                Logger.coreData.error("Core Data save error: \(error.localizedDescription)")
            }
        }
    }
}
