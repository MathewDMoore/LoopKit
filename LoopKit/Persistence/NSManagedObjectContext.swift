//
//  NSManagedObjectContext.swift
//  LoopKit
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreData


extension NSManagedObjectContext {

    /// Deletes all saved objects matching the specified type and predicate from the context's persistent store
    ///
    /// - Parameters:
    ///   - type: The object type to delete
    ///   - predicate: The predicate to match
    /// - Returns: The number of deleted objects
    /// - Throws: NSBatchDeleteRequest exeuction errors
    internal func purgeObjects<T: NSManagedObject>(of type: T.Type, matching predicate: NSPredicate? = nil) throws -> Int {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = T.fetchRequest()
        fetchRequest.predicate = predicate

        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs

        let result = try execute(deleteRequest)
        guard let deleteResult = result as? NSBatchDeleteResult,
            let objectIDs = deleteResult.result as? [NSManagedObjectID]
        else {
            return 0
        }

        if objectIDs.count > 0 {
            let changes = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
            self.refreshAllObjects()
        }

        return objectIDs.count
    }
}

extension NSManagedObjectContext {

    /// Returns the modification counter. The modification counter is a monotonically increasing integer
    /// that auto-increments on every call to this property. The global value is stored in the first
    /// peristent store associated with this context.
    ///
    /// - Return: The next modification counter for the persistent store associated with this context.
    internal var modificationCounter: Int64? {
        get {
            guard let persistentStoreCoordinator = persistentStoreCoordinator,
                let persistentStore = persistentStoreCoordinator.persistentStores.first
                else {
                    return nil
            }

            return NSManagedObjectContext.modificationCounterLock.withLock {
                var metadata = persistentStoreCoordinator.metadata(for: persistentStore)

                var modificationCounter: Int64
                if let previousModificationCounter = metadata[NSManagedObjectContext.modificationCounterMetadataKey] as? Int64 {
                    modificationCounter = previousModificationCounter + 1
                } else {
                    modificationCounter = 1
                }

                metadata[NSManagedObjectContext.modificationCounterMetadataKey] = modificationCounter

                persistentStoreCoordinator.setMetadata(metadata, for: persistentStore)

                return modificationCounter
            }
        }
    }

    private static let modificationCounterMetadataKey = "modificationCounter"

    private static let modificationCounterLock = UnfairLock()

}
