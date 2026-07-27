import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

public enum GolfManualBootstrapRunError: Error, Equatable, CustomStringConvertible {
    case invalidAnchor(GolfSubjectAnchorValidationResult)
    case trackingFailed(PrimaryGolferTrackResolverError)
    case roiFailed(StableSwingROIError)
    case validationFailed(String)

    public var description: String {
        switch self {
        case .invalidAnchor(let res):
            return "Subject anchor validation failed: \(res)"
        case .trackingFailed(let err):
            return "Primary golfer tracking failed: \(err)"
        case .roiFailed(let err):
            return "Stable ROI generation failed: \(err)"
        case .validationFailed(let msg):
            return "Run validation failed: \(msg)"
        }
    }
}

public enum GolfManualBootstrapRunBuilder {
    public static func build(
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String,
        anchors: [GolfSubjectAnchorDecision],
        candidates: [GolfPoseCandidateFrame],
        visionFrameworkVersion: String,
        visionRequestVersion: String,
        orientedFrameSize: CGSize,
        targetSize: Double
    ) -> Result<GolfPredictionRun, GolfManualBootstrapRunError> {
        let anchorResolver = GolfSubjectAnchorResolver()
        let anchorCheck = anchorResolver.validateAnchors(anchors)
        guard anchorCheck == .valid else {
            return .failure(.invalidAnchor(anchorCheck))
        }

        let sortedAnchors = anchors.sorted {
            if $0.sourceFrameIndex != $1.sourceFrameIndex {
                return $0.sourceFrameIndex < $1.sourceFrameIndex
            }
            return $0.anchorID < $1.anchorID
        }

        for anchor in sortedAnchors {
            let val = anchorResolver.validateAnchor(
                anchor,
                against: candidates,
                clipID: clipID,
                mediaSHA256: mediaSHA256,
                timelineSHA256: timelineSHA256
            )
            guard val == .valid else {
                return .failure(.invalidAnchor(val))
            }
        }

        let identifiers = sortedAnchors.map {
            GolfPoseCandidateIdentifier(
                sourceFrameIndex: $0.sourceFrameIndex,
                candidateIndex: $0.candidateIndex
            )
        }

        let trackResult = PrimaryGolferTrackResolver.resolve(
            candidates: candidates,
            manualAnchors: identifiers
        )
        let poseFrames: [GolfPoseTrackFrame]
        switch trackResult {
        case .success(let frames):
            poseFrames = frames
        case .failure(let err):
            return .failure(.trackingFailed(err))
        }

        let roiTrack: StableSwingROITrack
        do {
            roiTrack = try StableSwingROIBuilder.build(
                poseFrames: poseFrames,
                orientedFrameSize: orientedFrameSize,
                targetSize: Int(targetSize)
            )
        } catch let roiErr as StableSwingROIError {
            return .failure(.roiFailed(roiErr))
        } catch {
            return .failure(.roiFailed(.coverageFailed))
        }

        let roiAlgorithmVersion = StableSwingROIBuilder.algorithmVersion
        let roiConfigSHA = StableSwingROIBuilder.configurationSHA256(
            orientedFrameSize: orientedFrameSize,
            targetSize: targetSize
        )
        let decoderVersion = "AVFoundation.AVAssetReader"
        let trackerVersion = "PrimaryGolferTrackResolver.v1"

        let predictionFrames = roiTrack.frames.map { roiFrame in
            GolfPredictionFrame(
                sourceFrameIndex: roiFrame.sourceFrameIndex,
                sourceTime: roiFrame.sourceTime,
                roiTransform: roiFrame.transform,
                points: [:],
                anomalyReason: nil
            )
        }
        let anchorReferences = sortedAnchors.map {
            GolfManualBootstrapAnchorReference(
                anchorID: $0.anchorID,
                sourceFrameIndex: $0.sourceFrameIndex,
                candidateIndex: $0.candidateIndex,
                normalizedClickX: $0.normalizedClickPoint.x,
                normalizedClickY: $0.normalizedClickPoint.y
            )
        }

        let provenanceHash = computeProvenanceHash(
            clipID: clipID,
            mediaSHA256: mediaSHA256,
            timelineSHA256: timelineSHA256,
            anchors: anchorReferences,
            visionFrameworkVersion: visionFrameworkVersion,
            visionRequestVersion: visionRequestVersion,
            roiAlgorithmVersion: roiAlgorithmVersion,
            roiConfigSHA256: roiConfigSHA,
            decoderVersion: decoderVersion,
            trackerVersion: trackerVersion,
            frames: predictionFrames
        )

        let run = GolfPredictionRun(
            schemaVersion: 2,
            runKind: .manualBootstrap,
            predictionRunID: provenanceHash,
            clipID: clipID,
            mediaSHA256: mediaSHA256,
            timelineSHA256: timelineSHA256,
            visionFrameworkVersion: visionFrameworkVersion,
            visionRequestVersion: visionRequestVersion,
            roiAlgorithmVersion: roiAlgorithmVersion,
            roiConfigSHA256: roiConfigSHA,
            modelSHA256: nil,
            decoderVersion: decoderVersion,
            trackerVersion: trackerVersion,
            createdAt: Date(),
            frames: predictionFrames,
            manualBootstrapAnchors: anchorReferences,
            provenanceHash: provenanceHash
        )

        return .success(run)
    }

    public static func computeProvenanceHash(
        clipID: String,
        mediaSHA256: String,
        timelineSHA256: String,
        anchors: [GolfManualBootstrapAnchorReference],
        visionFrameworkVersion: String,
        visionRequestVersion: String,
        roiAlgorithmVersion: String,
        roiConfigSHA256: String,
        decoderVersion: String,
        trackerVersion: String,
        frames: [GolfPredictionFrame]
    ) -> String {
        let canonicalString = GolfManualBootstrapProvenance.canonicalString(
            clipID: clipID,
            mediaSHA256: mediaSHA256,
            timelineSHA256: timelineSHA256,
            anchors: anchors,
            visionFrameworkVersion: visionFrameworkVersion,
            visionRequestVersion: visionRequestVersion,
            roiAlgorithmVersion: roiAlgorithmVersion,
            roiConfigSHA256: roiConfigSHA256,
            decoderVersion: decoderVersion,
            trackerVersion: trackerVersion,
            frames: frames
        )
        return StableSwingROIBuilder.sha256Hex(canonicalString)
    }
}
