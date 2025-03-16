//
//  HealthKitManager.swift
//  AlonIOS
//
//  Created by Lucas Gaston Lober Boeris on 13/6/24.
//

import HealthKit


@available(macOS 13.0, *)
public class AlonIOS {
    private let healthStore = HKHealthStore()
    
    public init() {}

    public func requestAuthorization(completion: @escaping @Sendable (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device"]))
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes, completion: completion)
    }

    public func fetchStepsData(completion: @escaping @Sendable (Double?) -> Void) {
        let stepsQuantityType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepsQuantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count())
            completion(steps)
        }
        
        healthStore.execute(query)
    }

    public func fetchHRVData(completion: @escaping @Sendable (Double?) -> Void) {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: hrvType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
            let avgHRV = result?.averageQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli))
            completion(avgHRV)
        }
        
        healthStore.execute(query)
    }

    private func fetchSleepScore(completion: @escaping @Sendable (Double?) -> Void) {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let sleepSamples = samples as? [HKCategorySample] ?? []
            let totalScore = sleepSamples.reduce(0.0) { $0 + Double($1.value) }
            let avgScore = sleepSamples.isEmpty ? nil : totalScore / Double(sleepSamples.count)
            completion(avgScore)
        }
        
        healthStore.execute(query)
    }

    public func calculateHealthScore(completion: @escaping @Sendable (Double?) -> Void) {
        var totalScore = 0.0
        
        // Fetch data and calculate health score
        let dispatchGroup = DispatchGroup()
        
        var sleepScore: Double?
        var hrv: Double?
        var steps: Double?
        
        // Use DispatchQueue to ensure safe mutation of captured variables
        dispatchGroup.enter()
        fetchSleepScore { score in
            DispatchQueue.main.async {
                sleepScore = score
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.enter()
        fetchHRVData { value in
            DispatchQueue.main.async {
                hrv = value
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.enter()
        fetchStepsData { value in
            DispatchQueue.main.async {
                steps = value
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            // Calculate score based on fetched values
            if let sleepScore = sleepScore {
                if sleepScore >= 90 { totalScore += 40 }
                else if sleepScore >= 80 { totalScore += 35 }
                else if sleepScore >= 70 { totalScore += 30 }
                else if sleepScore >= 60 { totalScore += 20 }
                else if sleepScore >= 50 { totalScore += 15 }
                else if sleepScore >= 20 { totalScore += 10 }
            }
            
            if let hrv = hrv {
                if hrv >= 70 { totalScore += 30 }
                else if hrv >= 50 { totalScore += 20 }
                else if hrv >= 40 { totalScore += 10 }
                else if hrv > 20 { totalScore += 5 }
            }
            
            if let steps = steps {
                if steps >= 15000 { totalScore += 30 }
                else if steps >= 10000 { totalScore += 25 }
                else if steps >= 8000 { totalScore += 20 }
                else if steps >= 5000 { totalScore += 15 }
                else if steps >= 3000 { totalScore += 5 }
            }
            
            // Return final health score
            completion(totalScore)
        }
    }


}
