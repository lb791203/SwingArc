import CoreGraphics
import Foundation

private struct FakeGolfProvider: GolfObjectObservationProvider {
    let observation: GolfObjectObservation

    func observe(
        image: CGImage,
        pose: PoseEstimationResult?
    ) throws -> GolfObjectObservation {
        observation
    }
}

@main
struct GolfObjectObservationProviderSmoke {
    static func main() throws {
        let detected = TrackedSwingPoint(
            point: .init(x: 0.7, y: 0.6),
            confidence: 0.95,
            state: .detected,
            source: .coreMLGolf
        )
        let observation = GolfObjectObservation(points: [.clubhead: detected])
        let provider = FakeGolfProvider(observation: observation)
        let returned = try provider.observe(image: makeImage(), pose: nil)
        precondition(returned.points[.clubhead]?.state == .detected)

        let contour = ContourGolfObjectObservationAdapter.observation(from: .init(
            shaft: ClubShaftEvidence(
                start: CGPoint(x: 0.4, y: 0.5),
                end: CGPoint(x: 0.7, y: 0.6),
                confidence: 0.8
            ),
            ball: BallEvidence(
                center: CGPoint(x: 0.8, y: 0.9),
                radius: 0.01,
                confidence: 0.7
            ),
            stableBall: nil,
            ballLocalChange: 0
        ))
        precondition(contour.points[.shaftStart]?.source == .contour)
        precondition(contour.points[.shaftEnd]?.source == .contour)
        precondition(contour.points[.ball]?.source == .contour)
        precondition(contour.points[.clubhead] == nil)

        let transform = AspectFitImageTransform(
            sourceWidth: 320,
            sourceHeight: 180,
            targetSize: 256
        )
        let sourcePoint = NormalizedPoint(x: 0.25, y: 0.75)
        let modelPoint = transform.modelPoint(fromSource: sourcePoint)
        let roundTrip = transform.sourcePoint(fromModel: modelPoint)
        precondition(abs(roundTrip.x - sourcePoint.x) < 0.000_001)
        precondition(abs(roundTrip.y - sourcePoint.y) < 0.000_001)

        do {
            _ = try CoreMLGolfObjectDetector(modelURL: nil)
            preconditionFailure("An unavailable promoted model must not be fabricated")
        } catch let error as GolfObjectProviderError {
            precondition(error == .modelUnavailable)
        }
    }

    private static func makeImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 2,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }
}
