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
            candidate(.shaftParallelDownswing, sourceFrameIndex: 471, score: 0.81),
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
            470, 471, 472,
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

        let denseProductionLikeCandidates = [
            candidate(.address, sourceFrameIndex: 375, score: 0.93),
            candidate(.takeaway, sourceFrameIndex: 425, score: 0.52),
            candidate(.takeaway, sourceFrameIndex: 420, score: 0.42),
            candidate(.takeaway, sourceFrameIndex: 423, score: 0.41),
            candidate(.takeaway, sourceFrameIndex: 414, score: 0.40),
            candidate(.takeaway, sourceFrameIndex: 375, score: 0.40),
            candidate(.takeaway, sourceFrameIndex: 376, score: 0.40),
            candidate(.shaftParallelDownswing, sourceFrameIndex: 470, score: 0.75),
            candidate(.shaftParallelDownswing, sourceFrameIndex: 471, score: 0.73),
            candidate(.impact, sourceFrameIndex: 472, score: 0.34),
            candidate(.impact, sourceFrameIndex: 477, score: 0.33),
            candidate(.impact, sourceFrameIndex: 478, score: 0.34),
            candidate(.impact, sourceFrameIndex: 483, score: 0.33),
            candidate(.impact, sourceFrameIndex: 485, score: 0.31),
            candidate(.followThrough, sourceFrameIndex: 494, score: 0.76),
            candidate(.followThrough, sourceFrameIndex: 495, score: 0.74),
            candidate(.followThrough, sourceFrameIndex: 493, score: 0.67),
            candidate(.followThrough, sourceFrameIndex: 492, score: 0.65),
            candidate(.followThrough, sourceFrameIndex: 489, score: 0.40)
        ]
        let denseProductionLike = SparseObjectSamplingPlan.frames(
            from: references,
            candidates: denseProductionLikeCandidates
        )
        precondition(
            denseProductionLike.contains { $0.sourceFrameIndex == 414 },
            "A dense impact neighborhood must not starve the third P2 candidate center"
        )
        precondition(
            denseProductionLike.contains { $0.sourceFrameIndex == 470 },
            "A bounded sparse pass must retain the provisional P6 delivery neighborhood"
        )

        let p6StarvationCandidates = [20, 40, 60, 80, 100].map {
            candidate(.impact, sourceFrameIndex: $0, score: 1.00)
        } + [120, 135, 150, 165, 180].map {
            candidate(.address, sourceFrameIndex: $0, score: 0.95)
        } + [195, 205, 215, 225, 235].map {
            candidate(.takeaway, sourceFrameIndex: $0, score: 0.90)
        } + [245, 255, 265, 275, 285].map {
            candidate(.followThrough, sourceFrameIndex: $0, score: 0.85)
        } + [
            candidate(.shaftParallelDownswing, sourceFrameIndex: 240, score: 0.32)
        ]
        let p6StarvationSelection = SparseObjectSamplingPlan.frames(
            from: (0...300).map {
                FineFrameReference(sourceFrameIndex: $0, time: Double($0) / 30)
            },
            candidates: p6StarvationCandidates
        )
        precondition(
            p6StarvationSelection.contains { $0.sourceFrameIndex == 240 },
            "Impact and pose candidate density must never starve the only provisional P6 shaft neighborhood"
        )

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
            hasClubEvidence: stage == .shaftParallelDownswing
                || stage == .impact
                || stage == .followThrough,
            hasBallEvidence: stage == .impact
        )
    }
}
