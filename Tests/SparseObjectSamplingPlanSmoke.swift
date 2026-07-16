import Foundation

@main
struct SparseObjectSamplingPlanSmoke {
    static func main() {
        let references = (0..<170).map {
            FineFrameReference(sourceFrameIndex: 412 + $0, time: 13.733 + Double($0) / 30)
        }
        let times = [13.767, 14.000, 14.367, 14.833, 15.533, 16.000, 16.533, 17.100]
        let detections = zip(SwingStage.allCases, times).map { stage, time in
            SwingStageDetection(
                stage: stage,
                time: time,
                sourceFrameIndex: Int((time * 30).rounded()),
                confidence: 0.8,
                status: .confirmed
            )
        }
        let result = SwingAnalysisResult(
            detectedMarkers: detections.compactMap(\.marker),
            unresolvedStages: [],
            detections: detections
        )

        let selected = SparseObjectSamplingPlan.frames(
            from: references,
            preliminaryResult: result
        )

        precondition(!selected.isEmpty)
        precondition(selected.count <= 32, "Contour detection must stay bounded regardless of window length")
        precondition(zip(selected, selected.dropFirst()).allSatisfy {
            $0.sourceFrameIndex < $1.sourceFrameIndex
        })
        for time in times {
            precondition(selected.contains { abs($0.time - time) <= 1.0 / 30 + 0.000_1 })
        }

        let visionRegion = SwingObjectRegionPolicy.visionRegion(points: [
            CGPoint(x: 0.42, y: 0.34),
            CGPoint(x: 0.58, y: 0.70)
        ])
        precondition(visionRegion.width < 0.75 && visionRegion.height < 0.90)
        precondition(visionRegion.minX >= 0 && visionRegion.maxX <= 1)
        precondition(visionRegion.minY >= 0 && visionRegion.maxY <= 1)
        precondition(SwingObjectRegionPolicy.maximumImageDimension <= 320)
    }
}
