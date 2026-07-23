import Foundation
import CoreGraphics

enum AnnotationStep: String, CaseIterable {
    case setup
    case stages
    case landmarks
    case adjudication
    case export
}

struct AnnotationPredictionSnapshot: Equatable {
    var stages: [AnnotationStageSelection]
    var frameLabels: [AnnotationFrameLabel]
}

struct AnnotationWorkspaceState: Equatable {
    var step: AnnotationStep
    var currentSourceFrameIndex: Int
    var activePass: AnnotationPass?
    var submittedPasses: [AnnotationPass]
    var archivedPassRevisions: [AnnotationPass]
    var adjudications: [AnnotationAdjudication]
    var frameQueue: [Int]
    var protectedFrameIndices: Set<Int>
    var prediction: AnnotationPredictionSnapshot

    static let empty = AnnotationWorkspaceState(
        step: .setup,
        currentSourceFrameIndex: 0,
        activePass: nil,
        submittedPasses: [],
        archivedPassRevisions: [],
        adjudications: [],
        frameQueue: [],
        protectedFrameIndices: [],
        prediction: .init(stages: [], frameLabels: [])
    )

    func visibleComparison(
        for stage: String
    ) -> [AnnotationStageSelection]? {
        guard activePass == nil, submittedPasses.count >= 2 else {
            return nil
        }
        return submittedPasses.compactMap {
            $0.stages.first(where: { $0.stage == stage })
        }
    }

    var adjudicationQueue: [String] {
        AnnotationPackageValidator.stageCodes.filter { stage in
            guard !adjudications.contains(where: { $0.stage == stage }),
                  submittedPasses.count >= 2 else {
                return false
            }
            let frames = submittedPasses.prefix(2).compactMap {
                $0.stages.first(where: {
                    $0.stage == stage
                })?.sourceFrameIndex
            }
            return frames.count != 2 || abs(frames[0] - frames[1]) > 2
        }
    }
}

enum AnnotationWorkflowAction {
    case beginPass(annotatorID: String)
    case beginRevision(annotatorID: String)
    case updatePrediction(AnnotationPredictionSnapshot)
    case replaceFrameQueue([Int], protectedFrames: Set<Int>)
    case addFrameToQueue(Int)
    case removeFrameFromQueue(Int)
    case setStage(stage: String, sourceFrameIndex: Int?)
    case setPoint(
        landmark: String,
        sourceFrameIndex: Int,
        point: AnnotationPoint
    )
    case reviewFrame(sourceFrameIndex: Int, reviewerID: String)
    case submitActivePass
    case adjudicate(
        stage: String,
        sourceFrameIndex: Int?,
        adjudicatorID: String,
        note: String
    )
}

enum AnnotationWorkflowReducer {
    static func reduce(
        state: inout AnnotationWorkspaceState,
        action: AnnotationWorkflowAction
    ) {
        switch action {
        case let .beginPass(annotatorID):
            guard state.activePass == nil,
                  !state.submittedPasses.contains(where: {
                      $0.annotatorID == annotatorID
                  }) else {
                return
            }
            state.activePass = AnnotationPass(
                id: UUID(),
                annotatorID: annotatorID,
                revision: 1,
                submittedAt: nil,
                stages: AnnotationPackageValidator.stageCodes.map {
                    .init(
                        stage: $0,
                        sourceFrameIndex: nil,
                        status: .unresolved,
                        note: nil
                    )
                },
                frameLabels: []
            )
            state.step = .stages

        case let .beginRevision(annotatorID):
            guard state.activePass == nil,
                  let previous = state.submittedPasses.first(where: {
                      $0.annotatorID == annotatorID
                  }) else {
                return
            }
            state.activePass = AnnotationPass(
                id: UUID(),
                annotatorID: annotatorID,
                revision: previous.revision + 1,
                submittedAt: nil,
                stages: previous.stages,
                frameLabels: previous.frameLabels
            )
            state.step = .stages

        case let .updatePrediction(prediction):
            state.prediction = prediction

        case let .replaceFrameQueue(frames, protectedFrames):
            state.frameQueue = Array(Set(frames)).sorted()
            state.protectedFrameIndices = protectedFrames

        case let .addFrameToQueue(frame):
            state.frameQueue = Array(
                Set(state.frameQueue + [frame])
            ).sorted()

        case let .removeFrameFromQueue(frame):
            guard !state.protectedFrameIndices.contains(frame) else {
                return
            }
            state.frameQueue.removeAll { $0 == frame }

        case let .setStage(stage, sourceFrameIndex):
            guard var pass = state.activePass,
                  let index = pass.stages.firstIndex(where: {
                      $0.stage == stage
                  }) else {
                return
            }
            pass.stages[index].sourceFrameIndex = sourceFrameIndex
            pass.stages[index].status = sourceFrameIndex == nil
                ? .unresolved
                : .manual
            state.activePass = pass

        case let .setPoint(landmark, sourceFrameIndex, point):
            guard var pass = state.activePass else { return }
            let frameIndex = pass.frameLabels.firstIndex {
                $0.sourceFrameIndex == sourceFrameIndex
            }
            if let frameIndex {
                pass.frameLabels[frameIndex].landmarks[landmark] = point
                pass.frameLabels[frameIndex].reviewed = false
                pass.frameLabels[frameIndex].reviewerID = nil
            } else {
                pass.frameLabels.append(.init(
                    sourceFrameIndex: sourceFrameIndex,
                    landmarks: [landmark: point],
                    reviewerID: nil,
                    reviewed: false
                ))
            }
            state.activePass = pass

        case let .reviewFrame(sourceFrameIndex, reviewerID):
            guard var pass = state.activePass,
                  let index = pass.frameLabels.firstIndex(where: {
                      $0.sourceFrameIndex == sourceFrameIndex
                  }) else {
                return
            }
            pass.frameLabels[index].reviewed = true
            pass.frameLabels[index].reviewerID = reviewerID
            state.activePass = pass

        case .submitActivePass:
            guard let active = state.activePass else { return }
            let submitted = AnnotationPass(
                id: active.id,
                annotatorID: active.annotatorID,
                revision: active.revision,
                submittedAt: Date(),
                stages: active.stages,
                frameLabels: active.frameLabels
            )
            if let currentIndex = state.submittedPasses.firstIndex(where: {
                $0.annotatorID == submitted.annotatorID
            }) {
                state.archivedPassRevisions.append(
                    state.submittedPasses[currentIndex]
                )
                state.submittedPasses[currentIndex] = submitted
            } else {
                state.submittedPasses.append(submitted)
            }
            state.activePass = nil
            state.step = state.submittedPasses.count >= 2
                ? .adjudication
                : .setup

        case let .adjudicate(
            stage,
            sourceFrameIndex,
            adjudicatorID,
            note
        ):
            let originals = state.submittedPasses.prefix(2).compactMap {
                $0.stages.first(where: { $0.stage == stage })
            }
            state.adjudications.removeAll { $0.stage == stage }
            state.adjudications.append(.init(
                stage: stage,
                sourceFrameIndex: sourceFrameIndex,
                adjudicatorID: adjudicatorID,
                decidedAt: Date(),
                originalSelections: originals,
                note: note
            ))
        }
    }
}

enum AnnotationFrameQueueBuilder {
    static func build(
        stageFrames: [String: Int],
        flaggedFrames: Set<Int>,
        userAddedFrames: Set<Int>,
        protectedFrames: Set<Int>,
        frameCount: Int,
        policy: AnnotationFrameQueuePolicy
    ) -> [Int] {
        guard frameCount > 0 else { return [] }
        var frames = Set(stageFrames.values)
        func appendStride(
            from start: Int?,
            through end: Int?,
            stride: Int
        ) {
            guard let start, let end, start <= end else { return }
            for frame in Swift.stride(
                from: start,
                through: end,
                by: max(1, stride)
            ) {
                frames.insert(frame)
            }
        }
        appendStride(
            from: stageFrames["P1"],
            through: stageFrames["P5"],
            stride: policy.p1ThroughP5Stride
        )
        appendStride(
            from: stageFrames["P5"],
            through: stageFrames["P8"],
            stride: policy.p5ThroughP8Stride
        )
        frames.formUnion(flaggedFrames)
        frames.formUnion(userAddedFrames)
        frames.formUnion(protectedFrames)
        return frames.filter {
            (0..<frameCount).contains($0)
        }.sorted()
    }
}

enum AnnotationStepPresentation {
    static func title(for step: AnnotationStep) -> String {
        switch step {
        case .setup: return "任务资料"
        case .stages: return "P1–P8"
        case .landmarks: return "关键点"
        case .adjudication: return "分歧裁定"
        case .export: return "冻结与导出"
        }
    }
}

enum AnnotationLandmarkCatalog {
    static let body = [
        "head", "leftShoulder", "rightShoulder",
        "leftElbow", "rightElbow",
        "leftWrist", "rightWrist", "handCenter",
        "leftHip", "rightHip",
        "leftKnee", "rightKnee",
        "leftAnkle", "rightAnkle"
    ]

    static let golf = [
        "grip", "shaftStart", "shaftEnd", "clubhead", "ball"
    ]
}

enum AnnotationFrameStepPolicy {
    static func target(
        current: Int,
        delta: Int,
        frameCount: Int
    ) -> Int {
        max(0, min(max(0, frameCount - 1), current + delta))
    }
}

enum AnnotationCanvasGeometry {
    static func aspectFitRect(
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }
        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func normalizedPoint(
        location: CGPoint,
        imageRect: CGRect
    ) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else {
            return .zero
        }
        return CGPoint(
            x: min(
                1,
                max(0, (location.x - imageRect.minX) / imageRect.width)
            ),
            y: min(
                1,
                max(0, (location.y - imageRect.minY) / imageRect.height)
            )
        )
    }
}
