import Foundation

public enum GolfAnnotationQueueReason: String, Codable, Comparable, Sendable {
    case sparseP1P5 = "sparse-p1-p5"
    case sparseP5P8 = "sparse-p5-p8"
    case p6Dense = "p6-dense"
    case p8Dense = "p8-dense"
    case validationDense = "validation-dense"
    case anomaly = "anomaly"
    case preSwingNegative = "pre-swing-negative"
    case postSwingNegative = "post-swing-negative"

    public static func < (lhs: GolfAnnotationQueueReason, rhs: GolfAnnotationQueueReason) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct GolfAnnotationQueueItem: Equatable, Sendable {
    public let sourceFrameIndex: Int
    public let reasons: [GolfAnnotationQueueReason]
    public let isProtected: Bool

    public init(sourceFrameIndex: Int, reasons: [GolfAnnotationQueueReason], isProtected: Bool) {
        self.sourceFrameIndex = sourceFrameIndex
        self.reasons = reasons
        self.isProtected = isProtected
    }
}

public struct GolfAnnotationQueueInput: Sendable {
    public let split: GolfDatasetSplit
    public let p1: Int?
    public let p5: Int?
    public let p6: Int?
    public let p8: Int?
    public let totalFrames: Int
    public let anomalyFrames: [Int]
    public let preSwingNegativeSamples: [Int]
    public let postSwingNegativeSamples: [Int]

    public init(
        split: GolfDatasetSplit,
        p1: Int?,
        p5: Int?,
        p6: Int?,
        p8: Int?,
        totalFrames: Int,
        anomalyFrames: [Int],
        preSwingNegativeSamples: [Int],
        postSwingNegativeSamples: [Int]
    ) {
        self.split = split
        self.p1 = p1
        self.p5 = p5
        self.p6 = p6
        self.p8 = p8
        self.totalFrames = totalFrames
        self.anomalyFrames = anomalyFrames
        self.preSwingNegativeSamples = preSwingNegativeSamples
        self.postSwingNegativeSamples = postSwingNegativeSamples
    }
}

public enum GolfAnnotationFrameQueueBuilder {
    private static let maxNegativeSamples = 10
    private static let denseWindowRadius = 12

    public static func build(input: GolfAnnotationQueueInput) -> [GolfAnnotationQueueItem] {
        guard let p1 = input.p1, let p5 = input.p5, let p6 = input.p6, let p8 = input.p8 else {
            return []
        }

        var frameReasons: [Int: [GolfAnnotationQueueReason]] = [:]
        var protectedFrames: Set<Int> = []

        func addFrame(_ frame: Int, reason: GolfAnnotationQueueReason, protected: Bool) {
            guard frame >= 0, frame < input.totalFrames else { return }
            frameReasons[frame, default: []].append(reason)
            if protected {
                protectedFrames.insert(frame)
            }
        }

        func addProtectedFrame(_ frame: Int, reason: GolfAnnotationQueueReason) {
            addFrame(frame, reason: reason, protected: true)
        }

        func addUnprotectedFrame(_ frame: Int, reason: GolfAnnotationQueueReason) {
            addFrame(frame, reason: reason, protected: false)
        }

        // P1–P5 stride 4
        for frame in stride(from: p1, through: p5, by: 4) {
            addUnprotectedFrame(frame, reason: .sparseP1P5)
        }

        // P5–P8 stride 2
        for frame in stride(from: p5, through: p8, by: 2) {
            addUnprotectedFrame(frame, reason: .sparseP5P8)
        }

        // P-stage endpoints are protected
        for frame in [p1, p5, p6, p8] {
            protectedFrames.insert(frame)
        }

        // P6 ±12 dense (protected)
        let p6Start = max(0, p6 - denseWindowRadius)
        let p6End = min(input.totalFrames - 1, p6 + denseWindowRadius)
        for frame in p6Start...p6End {
            addProtectedFrame(frame, reason: .p6Dense)
        }

        // P8 ±12 dense (protected)
        let p8Start = max(0, p8 - denseWindowRadius)
        let p8End = min(input.totalFrames - 1, p8 + denseWindowRadius)
        for frame in p8Start...p8End {
            addProtectedFrame(frame, reason: .p8Dense)
        }

        // Validation/held-out: P5-12 to P8+12 all dense (protected)
        if input.split == .validation || input.split == .heldOut {
            let denseStart = max(0, p5 - denseWindowRadius)
            let denseEnd = min(input.totalFrames - 1, p8 + denseWindowRadius)
            for frame in denseStart...denseEnd {
                addProtectedFrame(frame, reason: .validationDense)
            }
        }

        // Anomaly frames (unprotected)
        for frame in input.anomalyFrames {
            addUnprotectedFrame(frame, reason: .anomaly)
        }

        // Pre-swing negative samples (unprotected, capped)
        let preSwing = input.preSwingNegativeSamples
            .filter { $0 >= 0 && $0 < input.totalFrames }
            .sorted()
            .prefix(Self.maxNegativeSamples)
        for frame in preSwing {
            addUnprotectedFrame(frame, reason: .preSwingNegative)
        }

        // Post-swing negative samples (unprotected, capped)
        let postSwing = input.postSwingNegativeSamples
            .filter { $0 >= 0 && $0 < input.totalFrames }
            .sorted()
            .prefix(Self.maxNegativeSamples)
        for frame in postSwing {
            addUnprotectedFrame(frame, reason: .postSwingNegative)
        }

        // Build items sorted by frame, reasons sorted deterministically
        let sortedFrames = frameReasons.keys.sorted()
        return sortedFrames.map { frame in
            let sortedReasons = frameReasons[frame]!.sorted()
            let isProtected = protectedFrames.contains(frame)
            return GolfAnnotationQueueItem(
                sourceFrameIndex: frame,
                reasons: sortedReasons,
                isProtected: isProtected
            )
        }
    }
}
