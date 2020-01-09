//
//  StatusStore.swift
//  LoopKit
//
//  Created by Darin Krauss on 10/14/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit

public protocol StatusStoreDelegate: AnyObject {
    
    /**
     Informs the delegate that the status store has updated status data.
     
     - Parameter statusStore: The status store that has updated status data.
     */
    func statusStoreHasUpdatedStatusData(_ statusStore: StatusStore)
    
}

public protocol StatusStoreCacheStore: AnyObject {

    /// The status store modification counter
    var statusStoreModificationCounter: Int64? { get set }

}

public class StatusStore {
    
    public weak var delegate: StatusStoreDelegate?
    
    private let lock = UnfairLock()

    private let storeCache: StatusStoreCacheStore

    private var status: [Int64: StoredStatus]
    
    private var modificationCounter: Int64 {
        didSet {
            storeCache.statusStoreModificationCounter = modificationCounter
        }
    }
    
    public init(storeCache: StatusStoreCacheStore) {
        self.storeCache = storeCache
        self.status = [:]
        self.modificationCounter = storeCache.statusStoreModificationCounter ?? 0
    }
    
    public func storeStatus(_ status: StoredStatus, completion: @escaping () -> Void) {
        lock.withLock {
            self.modificationCounter += 1
            self.status[self.modificationCounter] = status
        }
        self.delegate?.statusStoreHasUpdatedStatusData(self)
        completion()
    }
    
}

extension StatusStore {
    
    public struct QueryAnchor: RawRepresentable {
        
        public typealias RawValue = [String: Any]
        
        public var modificationCounter: Int64
        
        public init() {
            self.modificationCounter = 0
        }
        
        public init?(rawValue: RawValue) {
            guard let modificationCounter = rawValue["modificationCounter"] as? Int64 else {
                return nil
            }
            self.modificationCounter = modificationCounter
        }
        
        public var rawValue: RawValue {
            var rawValue: RawValue = [:]
            rawValue["modificationCounter"] = modificationCounter
            return rawValue
        }
    }
    
    public enum StatusQueryResult {
        case success(QueryAnchor, [StoredStatus])
        case failure(Error)
    }
    
    public func executeStatusQuery(fromQueryAnchor queryAnchor: QueryAnchor?, limit: Int, completion: @escaping (StatusQueryResult) -> Void) {
        var queryAnchor = queryAnchor ?? QueryAnchor()
        var queryResult = [StoredStatus]()

        guard limit > 0 else {
            completion(.success(queryAnchor, queryResult))
            return
        }

        lock.withLock {
            if queryAnchor.modificationCounter < self.modificationCounter {
                let startModificationCounter = queryAnchor.modificationCounter + 1
                var endModificationCounter = self.modificationCounter
                if limit <= endModificationCounter - startModificationCounter {
                    endModificationCounter = queryAnchor.modificationCounter + Int64(limit)
                }
                for modificationCounter in (startModificationCounter...endModificationCounter) {
                    if let status = self.status[modificationCounter] {
                        queryResult.append(status)
                    }
                }
                
                queryAnchor.modificationCounter = endModificationCounter
            }
        }
        
        completion(.success(queryAnchor, queryResult))
    }
    
}

public struct StoredStatus {
    
    public let date: Date = Date()
    
    public var insulinOnBoard: InsulinValue?
    
    public var carbsOnBoard: CarbValue?
    
    public var predictedGlucose: [PredictedGlucoseValue]?
    
    public var tempBasalRecommendationDate: TempBasalRecommendationDate?
    
    public var recommendedBolus: Double?
    
    public var lastReservoirValue: LastReservoirValue?
    
    public var pumpManagerStatus: PumpManagerStatus?
    
    public var glucoseTargetRangeSchedule: GlucoseRangeSchedule?
    
    public var scheduleOverride: TemporaryScheduleOverride?
    
    public var glucoseTargetRangeScheduleApplyingOverrideIfActive: GlucoseRangeSchedule?
    
    public var error: Error?

    public var syncIdentifier: String

    public var syncVersion: Int

    public init() {
        self.syncIdentifier = UUID().uuidString
        self.syncVersion = 1
    }
    
}

public struct TempBasalRecommendationDate {
    
    public let recommendation: TempBasalRecommendation
    
    public let date: Date
    
    public init(recommendation: TempBasalRecommendation, date: Date) {
        self.recommendation = recommendation
        self.date = date
    }
    
}

public struct LastReservoirValue {
    
    public let startDate: Date
    
    public let unitVolume: Double
    
    public init(startDate: Date, unitVolume: Double) {
        self.startDate = startDate
        self.unitVolume = unitVolume
    }
    
}

extension UserDefaults: StatusStoreCacheStore {
    
    private enum Key: String {
        case statusStoreModificationCounter = "com.loopkit.StatusStore.ModificationCounter"
    }
    
    public var statusStoreModificationCounter: Int64? {
        get {
            guard let value = object(forKey: Key.statusStoreModificationCounter.rawValue) as? NSNumber else {
                return nil
            }
            return value.int64Value
        }
        set {
            if let newValue = newValue {
                set(NSNumber(value: newValue), forKey: Key.statusStoreModificationCounter.rawValue)
            } else {
                removeObject(forKey: Key.statusStoreModificationCounter.rawValue)
            }
        }
    }
    
}