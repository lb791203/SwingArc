import Foundation
import CoreGraphics
import CoreMedia

@main
struct VideoAnalysisMediaPipelineSmoke {
    static func main() {
        let integerRateRequest = SourceFrameRequestTimePolicy.time(
            sourceFrameIndex: 131,
            sourceFrameRate: 30
        )
        precondition(
            integerRateRequest == CMTime(value: 131, timescale: 30),
            "Integer frame-rate requests must preserve the exact frame rational"
        )
        let fractionalRateRequest = SourceFrameRequestTimePolicy.time(
            sourceFrameIndex: 240,
            sourceFrameRate: 119.88
        )
        precondition(
            abs(fractionalRateRequest.seconds - 240.0 / 119.88) < 1.0 / 60_000.0,
            "Fractional rates must use a high-resolution request time"
        )

        let sourceFrameRate = 60.0
        precondition(
            SourceFrameMatchPolicy.validate(
                requestedSourceFrameIndex: 120,
                actualTime: 2.0,
                sourceFrameRate: sourceFrameRate
            ) == .matched(sourceFrameIndex: 120)
        )
        precondition(
            SourceFrameMatchPolicy.validate(
                requestedSourceFrameIndex: 120,
                actualTime: 120.5 / sourceFrameRate,
                sourceFrameRate: sourceFrameRate
            ) == .failed(.frameExtractionFailed),
            "A half-frame boundary is ambiguous and must not be labeled as the requested frame"
        )
        precondition(
            SourceFrameMatchPolicy.validate(
                requestedSourceFrameIndex: 120,
                actualTime: 121.0 / sourceFrameRate,
                sourceFrameRate: sourceFrameRate
            ) == .failed(.frameExtractionFailed),
            "An adjacent decoded frame must fail exact source-index matching"
        )

        precondition(
            SwingVideoAnalysisValidationPolicy.prioritizedFailure(
                frameExtractionFailed: true,
                evidenceFailure: .missingAddressBoundary
            ) == .frameExtractionFailed
        )
        precondition(
            SwingVideoAnalysisValidationPolicy.prioritizedFailure(
                frameExtractionFailed: true,
                evidenceFailure: .noImpactCorridor
            ) == .frameExtractionFailed
        )

        guard let sourceImage = makeImage(width: 640, height: 360) else {
            preconditionFailure("Fixture image creation failed")
        }
        let cache = FineFrameImageCache(maximumEntryCount: 3)
        var decodeCount = 0
        for sourceFrameIndex in 100...102 {
            let load = cache.load(sourceFrameIndex: sourceFrameIndex) {
                decodeCount += 1
                return sourceImage
            }
            guard case .decoded = load else {
                preconditionFailure("The first fine pass must decode each source frame once")
            }
        }
        precondition(cache.count == 3)
        for sourceFrameIndex in [100, 102] {
            guard let contourImage = cache.contourImage(sourceFrameIndex: sourceFrameIndex) else {
                preconditionFailure("Sparse object evidence requires the first-pass cache")
            }
            precondition(max(contourImage.width, contourImage.height) <= 256)
        }
        precondition(decodeCount == 3, "Sparse object evidence must not trigger a second AV decode")
        if case .failed = cache.load(sourceFrameIndex: 103, decoder: { sourceImage }) {
            // The maximum-entry guard is part of the memory bound.
        } else {
            preconditionFailure("The fine-frame cache must reject growth beyond its frame budget")
        }

        let decodeLedger = SourceFrameDecodeLedger()
        precondition(decodeLedger.registerDecode(sourceFrameIndex: 100, pass: .coarse))
        precondition(decodeLedger.registerDecode(sourceFrameIndex: 101, pass: .coarse))
        precondition(
            !decodeLedger.registerDecode(sourceFrameIndex: 100, pass: .fine),
            "A source frame decoded in coarse analysis cannot be decoded again in fine analysis"
        )
        precondition(decodeLedger.registerDecode(sourceFrameIndex: 102, pass: .fine))
        precondition(decodeLedger.totalDecodeCount == 3)
        precondition(decodeLedger.decodeCount(for: .coarse) == 2)
        precondition(decodeLedger.decodeCount(for: .fine) == 1)
        precondition(decodeLedger.maximumDecodeCountPerSourceFrame == 1)

        guard let prepared = FineFrameImageCache.prepareContourImage(sourceImage) else {
            preconditionFailure("Coarse contour preparation failed")
        }
        let adoptionCache = FineFrameImageCache(maximumEntryCount: 1)
        precondition(adoptionCache.storePrepared(sourceFrameIndex: 100, image: prepared))
        precondition(adoptionCache.contourImage(sourceFrameIndex: 100) != nil)
        precondition(!adoptionCache.storePrepared(sourceFrameIndex: 101, image: prepared))

        let shiftingCache = FineFrameImageCache(maximumEntryCount: 241)
        let shiftingLedger = SourceFrameDecodeLedger()
        for shift in 0...3 {
            let lower = 300 + shift * 15
            let retained = Set(lower...(lower + 240))
            shiftingCache.retainSourceFrames(retained)
            for frame in retained where shiftingCache.contourImage(sourceFrameIndex: frame) == nil {
                precondition(shiftingLedger.registerDecode(sourceFrameIndex: frame, pass: .fine))
                precondition(shiftingCache.storePrepared(sourceFrameIndex: frame, image: prepared))
            }
            precondition(shiftingCache.count == 241)
        }
        precondition(shiftingLedger.maximumDecodeCountPerSourceFrame == 1)
        precondition(
            shiftingLedger.totalDecodeCount == 286,
            "Three monotonic half-second shifts must add only 45 new 30-FPS frames"
        )

        let golferAtCore = pose(centerX: 0.32, scale: 0.56, confidence: 0.99)
        let coarseBackgroundGolfer = pose(centerX: 0.72, scale: 0.30, confidence: 0.70)
        let backgroundGolfer = pose(centerX: 0.72, scale: 0.50, confidence: 0.99)
        let tracker = PrimaryGolferTracker()
        precondition(tracker.select(from: [golferAtCore, coarseBackgroundGolfer], stableBall: nil) == golferAtCore)
        precondition(tracker.lockIdentityAnchor(to: golferAtCore))

        let expandedGolfer = pose(centerX: 0.35, scale: 0.44, confidence: 0.74)
        precondition(
            tracker.select(from: [backgroundGolfer, expandedGolfer], stableBall: nil) == expandedGolfer,
            "A backwards adaptive-window jump must retain the golfer anchored near the swing core"
        )
        precondition(
            tracker.select(from: [backgroundGolfer], stableBall: nil) == nil,
            "The tracker must miss rather than switch to an off-anchor background golfer"
        )
    }

    private static func makeImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func pose(
        centerX: CGFloat,
        scale: CGFloat,
        confidence: Float
    ) -> PoseEstimationResult {
        let halfWidth = scale * 0.25
        let shoulderY: CGFloat = 0.35
        let hipY: CGFloat = 0.58
        let points: [(String, CGPoint)] = [
            ("leftShoulder", CGPoint(x: centerX - halfWidth, y: shoulderY)),
            ("rightShoulder", CGPoint(x: centerX + halfWidth, y: shoulderY)),
            ("leftHip", CGPoint(x: centerX - halfWidth * 0.75, y: hipY)),
            ("rightHip", CGPoint(x: centerX + halfWidth * 0.75, y: hipY)),
            ("leftAnkle", CGPoint(x: centerX - halfWidth * 0.65, y: shoulderY + scale)),
            ("rightAnkle", CGPoint(x: centerX + halfWidth * 0.65, y: shoulderY + scale))
        ]
        var result = PoseEstimationResult()
        result.keypoints = Dictionary(uniqueKeysWithValues: points.map { name, point in
            (name, JointKeypoint(name: name, position: point, confidence: confidence))
        })
        result.shoulderMid = CGPoint(x: centerX, y: shoulderY)
        result.hipMid = CGPoint(x: centerX, y: hipY)
        return result
    }
}
