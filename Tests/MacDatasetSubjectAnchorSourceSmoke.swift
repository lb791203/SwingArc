import CoreGraphics
import Foundation

@main
struct MacDatasetSubjectAnchorSourceSmoke {
    @MainActor
    static func main() async throws {
        testAspectFitCandidateGeometry()
        testLoadedAnchorsRequireExplicitSelection()
        testAnchorControllerSelectionAndClickValidation()
        testAnchorControllerSaveAndAppend()
        await testPredictionRunGeneratorPipeline()
        print("All MacDatasetSubjectAnchorSource tests passed.")
    }

    static func testLoadedAnchorsRequireExplicitSelection() {
        let controller = DatasetSubjectAnchorController()
        let anchors = [
            GolfSubjectAnchorDecision(
                anchorID: "old-anchor",
                clipID: "clip-A",
                mediaSHA256: "media",
                timelineSHA256: "timeline",
                sourceFrameIndex: 0,
                candidateIndex: 0,
                normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
                visionFrameworkVersion: "v1",
                visionRequestRevision: "r1",
                annotatorID: "u1",
                decidedAt: Date()
            )
        ]
        controller.replaceLoadedAnchors(anchors)
        precondition(
            controller.selectedAnchorIDs.isEmpty,
            "Historical anchors must not become active implicitly"
        )
        controller.replaceLoadedAnchors(
            anchors,
            selectingAnchorID: "old-anchor"
        )
        precondition(controller.selectedAnchorIDs == ["old-anchor"])
    }

    static func testAspectFitCandidateGeometry() {
        let imageSize = CGSize(width: 1920, height: 1080)
        let containerSize = CGSize(width: 400, height: 350)
        let imageRect = DatasetSubjectAnchorGeometry.aspectFitRect(
            imageSize: imageSize,
            containerSize: containerSize
        )
        precondition(abs(imageRect.minY - 62.5) < 0.001)
        precondition(abs(imageRect.height - 225) < 0.001)

        precondition(
            DatasetSubjectAnchorGeometry.normalizedImagePoint(
                at: CGPoint(x: 200, y: 20),
                imageRect: imageRect
            ) == nil,
            "Letterbox clicks must be rejected"
        )

        let center = DatasetSubjectAnchorGeometry.normalizedImagePoint(
            at: CGPoint(x: 200, y: 175),
            imageRect: imageRect
        )
        precondition(center == GolfNormalizedPoint(x: 0.5, y: 0.5))

        let candidateRect = DatasetSubjectAnchorGeometry.screenRect(
            for: GolfNormalizedRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6),
            in: imageRect
        )
        precondition(candidateRect == CGRect(x: 100, y: 107.5, width: 200, height: 135))
    }

    static func testAnchorControllerSelectionAndClickValidation() {
        let candidates = [
            GolfPoseCandidateFrame(
                sourceFrameIndex: 0,
                sourceTime: 0.0,
                candidateIndex: 0,
                bodyCenter: GolfNormalizedPoint(x: 0.25, y: 0.25),
                bodyBounds: GolfNormalizedRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1),
                bodyScale: 0.1,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.05, hipWidth: 0.05, torsoLength: 0.1),
                handCenter: nil,
                identityConfidence: 0.9
            ),
            GolfPoseCandidateFrame(
                sourceFrameIndex: 0,
                sourceTime: 0.0,
                candidateIndex: 1,
                bodyCenter: GolfNormalizedPoint(x: 0.75, y: 0.75),
                bodyBounds: GolfNormalizedRect(x: 0.7, y: 0.7, width: 0.1, height: 0.1),
                bodyScale: 0.1,
                jointGeometry: GolfCandidateJointGeometry(shoulderWidth: 0.05, hipWidth: 0.05, torsoLength: 0.1),
                handCenter: nil,
                identityConfidence: 0.9
            )
        ]

        let controller = DatasetSubjectAnchorController()
        // Click on candidate 0
        let hit0 = controller.findCandidate(at: GolfNormalizedPoint(x: 0.22, y: 0.22), in: candidates)
        precondition(hit0?.candidateIndex == 0)

        // Click on candidate 1
        let hit1 = controller.findCandidate(at: GolfNormalizedPoint(x: 0.72, y: 0.72), in: candidates)
        precondition(hit1?.candidateIndex == 1)

        // Click blank space
        let hitBlank = controller.findCandidate(at: GolfNormalizedPoint(x: 0.5, y: 0.5), in: candidates)
        precondition(hitBlank == nil)
    }

    static func testAnchorControllerSaveAndAppend() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = GolfDatasetStore(rootDirectory: tempDir)

        let clipID = "clip-A"
        let mediaSHA = "mSHA"
        let timelineSHA = "tSHA"
        try! store.saveClip(
            GolfClipIdentity(
                clipID: clipID,
                golferID: "golfer-A",
                media: GolfMediaIdentity(
                    fileName: "clip.mov",
                    sha256: mediaSHA,
                    timelineSHA256: timelineSHA,
                    frameCount: 1,
                    orientedWidth: 1920,
                    orientedHeight: 1080,
                    sourceTimescale: 600
                ),
                view: .downTheLine,
                handedness: .right,
                authorization: .trainingAllowed,
                pPointTruthSHA256: String(repeating: "c", count: 64)
            )
        )

        let anchor1 = GolfSubjectAnchorDecision(
            anchorID: "anchor-1",
            clipID: clipID,
            mediaSHA256: mediaSHA,
            timelineSHA256: timelineSHA,
            sourceFrameIndex: 0,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.22, y: 0.22),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "u1",
            decidedAt: Date()
        )

        try! store.appendSubjectAnchor(anchor1, clipID: clipID)
        let loaded = try! store.loadSubjectAnchors(clipID: clipID)
        precondition(loaded.count == 1)
        precondition(loaded[0].anchorID == "anchor-1")

        // Collision test: append duplicate anchorID must throw
        do {
            try store.appendSubjectAnchor(anchor1, clipID: clipID)
            preconditionFailure("Expected collision error")
        } catch GolfDatasetStoreError.anchorAlreadyExists {
            // expected
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    @MainActor
    static func testPredictionRunGeneratorPipeline() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = GolfDatasetStore(rootDirectory: tempDir)

        let golfer = GolferRecord(golferID: "golfer-001", split: .training, splitLockedAt: Date())
        let registry = GolferRegistry(datasetID: "dataset-001", golfers: [golfer])
        try! store.saveRegistry(registry)

        let media = GolfMediaIdentity(
            fileName: "clip-001.mp4",
            sha256: String(repeating: "a", count: 64),
            timelineSHA256: String(repeating: "b", count: 64),
            frameCount: 10,
            orientedWidth: 1080,
            orientedHeight: 1920,
            sourceTimescale: 600
        )
        let clip = GolfClipIdentity(
            clipID: "clip-001",
            golferID: "golfer-001",
            media: media,
            view: .downTheLine,
            handedness: .right,
            authorization: .trainingAllowed,
            pPointTruthSHA256: String(repeating: "c", count: 64)
        )
        try! store.saveClip(clip)

        let anchor = GolfSubjectAnchorDecision(
            anchorID: "anchor-001",
            clipID: "clip-001",
            mediaSHA256: media.sha256,
            timelineSHA256: media.timelineSHA256,
            sourceFrameIndex: 0,
            candidateIndex: 0,
            normalizedClickPoint: GolfNormalizedPoint(x: 0.5, y: 0.5),
            visionFrameworkVersion: "v1",
            visionRequestRevision: "r1",
            annotatorID: "annotator-1",
            decidedAt: Date()
        )
        try! store.appendSubjectAnchor(anchor, clipID: "clip-001")

        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let frameSource = DatasetPredictionFrameSource(
            frameCount: 10,
            orientedFrameSize: CGSize(width: 1080, height: 1920),
            frameAt: { frameIndex in
                DatasetPredictionSourceFrame(
                    image: image,
                    sourceTime: Double(frameIndex) / 30
                )
            }
        )
        let generator = DatasetPredictionRunGenerator(
            frameSourceLoader: { _ in frameSource },
            candidateExtractor: { _, frameIndex, sourceTime in
                [
                    GolfPoseCandidateFrame(
                        sourceFrameIndex: frameIndex,
                        sourceTime: sourceTime,
                        candidateIndex: 0,
                        bodyCenter: GolfNormalizedPoint(x: 0.5, y: 0.5),
                        bodyBounds: GolfNormalizedRect(
                            x: 0.3,
                            y: 0.2,
                            width: 0.4,
                            height: 0.6
                        ),
                        bodyScale: 0.45,
                        jointGeometry: GolfCandidateJointGeometry(
                            shoulderWidth: 0.25,
                            hipWidth: 0.2,
                            torsoLength: 0.35
                        ),
                        handCenter: nil,
                        identityConfidence: 0.9
                    )
                ]
            },
            visionFrameworkVersion: "v1",
            visionRequestVersion: "r1"
        )
        let buildResult = await generator.generateManualBootstrapRun(
            clip: clip,
            store: store,
            anchors: [anchor],
            videoURL: URL(fileURLWithPath: "/tmp/fake-clip.mov")
        )

        switch buildResult {
        case .success(let run):
            precondition(run.frames.count == 10, "Run must contain 10 frames")
            precondition(run.runKind == GolfPredictionRunKind.manualBootstrap)
            precondition(run.modelSHA256 == nil)

            let loadedRun = try! store.loadPrediction(clipID: "clip-001", predictionRunID: run.predictionRunID)
            precondition(loadedRun == run, "Loaded run must match generated run")
            let repeated = await generator.generateManualBootstrapRun(
                clip: clip,
                store: store,
                anchors: [anchor],
                videoURL: URL(fileURLWithPath: "/tmp/fake-clip.mov")
            )
            switch repeated {
            case .success(let repeatedRun):
                precondition(
                    repeatedRun.predictionRunID == run.predictionRunID,
                    "Repeated generation must be idempotent"
                )
            case .failure(let error):
                preconditionFailure(
                    "Repeated generation must succeed: \(error)"
                )
            }

        case .failure(let err):
            preconditionFailure("Generator pipeline build failed: \(err)")
        }
    }
}
