import Foundation

enum AnnotationPredictionAdapter {
    static func snapshot(
        detections: [SwingStageDetection],
        frames: [SwingFrameObservation]
    ) -> AnnotationPredictionSnapshot {
        let stageMap: [(String, SwingStage)] = [
            ("P1", .address),
            ("P2", .takeaway),
            ("P3", .leadArmParallelBackswing),
            ("P4", .top),
            ("P5", .leadArmParallelDownswing),
            ("P6", .shaftParallelDownswing),
            ("P7", .impact),
            ("P8", .followThrough)
        ]
        let stageSelections = stageMap.map { code, stage in
            guard let detection = detections.first(where: {
                $0.stage == stage
            }) else {
                return AnnotationStageSelection(
                    stage: code,
                    sourceFrameIndex: nil,
                    status: .unresolved,
                    note: nil
                )
            }

            let needsShaft = ["P2", "P6", "P8"].contains(code)
            let needsImpact = code == "P7"
            let isResolvedDetection = detection.status != .unresolved
                && detection.sourceFrameIndex != nil
            let evidenceSatisfied = isResolvedDetection
                && (!needsShaft
                    || detection.evidence.sources.contains(.shaft))
                && (!needsImpact
                    || detection.hasBallEvidence
                    || detection.hasBallChangeEvidence)
            return .init(
                stage: code,
                sourceFrameIndex: evidenceSatisfied
                    ? detection.sourceFrameIndex
                    : nil,
                suggestedSourceFrameIndex: detection.sourceFrameIndex,
                suggestedRangeStart: detection.sourceFrameIndex.map {
                    max(0, $0 - 2)
                },
                suggestedRangeEnd: detection.sourceFrameIndex.map {
                    $0 + 2
                },
                status: evidenceSatisfied ? .predicted : .unresolved,
                note: evidenceSatisfied
                    ? nil
                    : missingEvidenceNote(
                        needsShaft: needsShaft,
                        needsImpact: needsImpact
                    )
            )
        }

        let frameLabels = frames.map { frame in
            AnnotationFrameLabel(
                sourceFrameIndex: frame.sourceFrameIndex,
                landmarks: Dictionary(uniqueKeysWithValues:
                    frame.landmarks.compactMap { landmark, tracked in
                        let visibility: AnnotationVisibility
                        switch tracked.state {
                        case .detected:
                            visibility = .visible
                        case .occluded:
                            visibility = .occluded
                        case .outOfFrame:
                            visibility = .outOfFrame
                        case .estimated, .missing:
                            visibility = .unresolved
                        }
                        guard tracked.point != nil
                            || visibility != .unresolved else {
                            return nil
                        }
                        return (
                            landmark.rawValue,
                            AnnotationPoint(
                                x: tracked.point?.x,
                                y: tracked.point?.y,
                                visibility: visibility,
                                source: .predicted,
                                confidence: tracked.confidence
                            )
                        )
                    }
                ),
                reviewerID: nil,
                reviewed: false
            )
        }
        return .init(
            stages: stageSelections,
            frameLabels: frameLabels
        )
    }

    private static func missingEvidenceNote(
        needsShaft: Bool,
        needsImpact: Bool
    ) -> String? {
        if needsShaft {
            return "缺少杆身证据，仅保留 Vision 候选帧"
        }
        if needsImpact {
            return "缺少杆头/球位变化证据，仅保留 Vision 候选帧"
        }
        return "现有分析未确认该阶段"
    }
}
