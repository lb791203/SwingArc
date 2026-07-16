import Foundation

struct SwingPoseSample: Equatable {
    let time: Double
    let wristY: CGFloat
}

struct SwingAnalysisResult: Equatable {
    let detectedMarkers: [KeyframeMarker]
    let unresolvedStages: Set<SwingStage>
}

enum SwingStageDetector {
    private static let finishStabilityThreshold: CGFloat = 0.04

    static func detect(samples rawSamples: [SwingPoseSample]) -> SwingAnalysisResult {
        let samples = rawSamples.sorted { $0.time < $1.time }
        guard samples.count >= 9,
              zip(samples, samples.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            return unresolvedResult()
        }

        var resolved: [SwingStage: SwingPoseSample] = [:]
        guard let p4Index = samples.indices.min(by: { samples[$0].wristY < samples[$1].wristY }) else {
            return unresolvedResult()
        }

        if p4Index >= 3 {
            let beforeTop = Array(samples[..<p4Index])
            if let p1 = beforeTop.max(by: { $0.wristY < $1.wristY }),
               let p1Index = samples.firstIndex(of: p1),
               p1Index + 2 < p4Index {
                let p2 = samples[p1Index + 1]
                let p3 = samples[p1Index + 2]
                let p4 = samples[p4Index]
                if p1.wristY > p2.wristY,
                   p2.wristY > p3.wristY,
                   p3.wristY > p4.wristY {
                    resolved[.address] = p1
                    resolved[.takeaway] = p2
                    resolved[.leadArmParallelBackswing] = p3
                    resolved[.top] = p4
                }
            }
        }

        let p5Index = p4Index + 1
        if samples.indices.contains(p5Index), samples[p5Index].wristY > samples[p4Index].wristY {
            resolved[.leadArmParallelDownswing] = samples[p5Index]

            let finalIndices = (samples.count - 3)..<samples.count
            let impactCandidates = samples.indices.filter { $0 >= p5Index && !finalIndices.contains($0) }
            if let p6Index = impactCandidates.max(by: { samples[$0].wristY < samples[$1].wristY }),
               samples[p6Index].wristY > samples[p5Index].wristY {
                resolved[.impact] = samples[p6Index]

                let p7Index = p6Index + 1
                if samples.indices.contains(p7Index), samples[p7Index].wristY < samples[p6Index].wristY {
                    resolved[.followThrough] = samples[p7Index]

                    let penultimate = samples[samples.count - 2]
                    let finish = samples[samples.count - 1]
                    if abs(penultimate.wristY - finish.wristY) <= finishStabilityThreshold,
                       finish.wristY < samples[p7Index].wristY {
                        resolved[.finish] = finish
                    }
                }
            }
        }

        let markers = SwingStage.allCases.compactMap { stage in
            resolved[stage].map { KeyframeMarker(time: $0.time, stage: stage) }
        }
        let unresolved = Set(SwingStage.allCases).subtracting(resolved.keys)
        return SwingAnalysisResult(detectedMarkers: markers, unresolvedStages: unresolved)
    }

    private static func unresolvedResult() -> SwingAnalysisResult {
        SwingAnalysisResult(detectedMarkers: [], unresolvedStages: Set(SwingStage.allCases))
    }
}
