import Foundation

/// Lightweight, on-device impact gate. It learns a slow-moving room-noise
/// floor and only emits one trigger per cooldown interval.
struct ImpactTriggerPolicy: Equatable {
    private static let minimumSamplesForBaseline = 6
    private static let minimumAbsoluteRMS = 0.025
    private static let relativeMultiplier = 4.0
    private static let cooldown: TimeInterval = 0.75

    private var baselineSamples: [Double] = []
    private var noiseFloor: Double = 0
    private var lastImpactTime: TimeInterval?

    mutating func ingest(rms: Double, at time: TimeInterval) -> Bool {
        guard rms.isFinite, rms >= 0, time.isFinite else { return false }
        if baselineSamples.count < Self.minimumSamplesForBaseline {
            baselineSamples.append(rms)
            noiseFloor = median(baselineSamples)
            return false
        }

        let threshold = max(Self.minimumAbsoluteRMS, noiseFloor * Self.relativeMultiplier)
        guard rms >= threshold else {
            // Background conditions can change gradually outdoors; smooth only
            // values that were not significant enough to be an impact.
            noiseFloor = noiseFloor * 0.90 + rms * 0.10
            return false
        }
        guard lastImpactTime.map({ time - $0 >= Self.cooldown }) ?? true else {
            return false
        }
        lastImpactTime = time
        return true
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
