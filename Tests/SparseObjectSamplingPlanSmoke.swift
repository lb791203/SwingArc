import Foundation

@main
struct SparseObjectSamplingPlanSmoke {
    static func main() {
        let references = (350...520).map {
            FineFrameReference(sourceFrameIndex: $0, time: Double($0) / 30)
        }
        let candidates = [
            candidate(.address, sourceFrameIndex: 375, score: 0.80),
            candidate(.takeaway, sourceFrameIndex: 414, score: 0.78),
            candidate(.impact, sourceFrameIndex: 478, score: 0.62),
            candidate(.impact, sourceFrameIndex: 480, score: 0.88),
            candidate(.impact, sourceFrameIndex: 481, score: 0.92),
            candidate(.followThrough, sourceFrameIndex: 496, score: 0.76),
            candidate(.top, sourceFrameIndex: 450, score: 1.00)
        ]

        let selected = SparseObjectSamplingPlan.frames(
            from: references,
            candidates: candidates
        )

        precondition(!selected.isEmpty)
        precondition(selected.count <= 32, "Contour detection must stay bounded regardless of window length")
        precondition(Set(selected.map(\.sourceFrameIndex)).count == selected.count)
        precondition(selected.map(\.time) == selected.map(\.time).sorted())
        precondition(selected.map(\.sourceFrameIndex) == selected.map(\.sourceFrameIndex).sorted())
        precondition(Set(selected.map(\.sourceFrameIndex)).isSuperset(of: [
            374, 375, 376,
            413, 414, 415,
            477, 478, 479, 480, 481, 482,
            495, 496, 497
        ]))
        precondition(!selected.contains { $0.sourceFrameIndex == 450 })

        let overBudgetCandidates = [20, 30, 40, 50, 60].map {
            candidate(.impact, sourceFrameIndex: $0, score: 0.40)
        } + [80, 90, 100, 110, 120, 130, 140, 150].enumerated().map { offset, frame in
            candidate(
                offset.isMultiple(of: 3) ? .address : (offset % 3 == 1 ? .takeaway : .followThrough),
                sourceFrameIndex: frame,
                score: 1 - Double(offset) * 0.05
            )
        }
        let overBudget = SparseObjectSamplingPlan.frames(
            from: (0...170).map {
                FineFrameReference(sourceFrameIndex: $0, time: Double($0) / 30)
            },
            candidates: overBudgetCandidates
        )
        precondition(overBudget.count <= 32)
        for center in [20, 30, 40, 50, 60] {
            precondition(Set(overBudget.map(\.sourceFrameIndex)).isSuperset(of: [center - 1, center, center + 1]))
        }
        precondition(Set(overBudget.map(\.sourceFrameIndex)).isSuperset(of: [79, 80, 81]))
        precondition(!overBudget.contains { $0.sourceFrameIndex == 150 })

        let fallback = SparseObjectSamplingPlan.frames(from: references, candidates: [])
        precondition(fallback.count == 12)
        precondition(fallback.map(\.sourceFrameIndex) == fallback.map(\.sourceFrameIndex).sorted())
        let unsupportedOnly = SparseObjectSamplingPlan.frames(
            from: references,
            candidates: [candidate(.top, sourceFrameIndex: 450, score: 1)]
        )
        precondition(unsupportedOnly.isEmpty, "Fallback is reserved for a completely absent candidate list")

        let legacyDetections = SwingStage.allCases.enumerated().map { offset, stage in
            SwingStageDetection(
                stage: stage,
                time: Double(370 + offset * 12) / 30,
                confidence: 0.8,
                status: .confirmed
            )
        }
        let legacy = SparseObjectSamplingPlan.frames(
            from: references,
            preliminaryResult: SwingAnalysisResult(
                detectedMarkers: legacyDetections.compactMap(\.marker),
                unresolvedStages: [],
                detections: legacyDetections
            )
        )
        precondition(!legacy.isEmpty && legacy.count <= 32)

        let visionRegion = SwingObjectRegionPolicy.visionRegion(points: [
            CGPoint(x: 0.42, y: 0.34),
            CGPoint(x: 0.58, y: 0.70)
        ])
        precondition(visionRegion.width < 0.75 && visionRegion.height < 0.90)
        precondition(visionRegion.minX >= 0 && visionRegion.maxX <= 1)
        precondition(visionRegion.minY >= 0 && visionRegion.maxY <= 1)
        precondition(SwingObjectRegionPolicy.maximumImageDimension <= 320)
    }

    private static func candidate(
        _ stage: SwingStage,
        sourceFrameIndex: Int,
        score: Double
    ) -> StageCandidate {
        StageCandidate(
            stage: stage,
            evidenceIndex: sourceFrameIndex,
            sourceFrameIndex: sourceFrameIndex,
            time: Double(sourceFrameIndex) / 30,
            score: score,
            requirementsSatisfied: true,
            maximumStatus: .confirmed,
            hasClubEvidence: stage == .impact,
            hasBallEvidence: stage == .impact
        )
    }
}
