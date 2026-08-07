import CoreGraphics
import CoreML
import CoreVideo
import Foundation

struct AspectFitImageTransform: Equatable {
    let sourceWidth: Int
    let sourceHeight: Int
    let targetSize: Int
    let contentWidth: Int
    let contentHeight: Int
    let offsetX: Int
    let offsetY: Int

    init(sourceWidth: Int, sourceHeight: Int, targetSize: Int) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.targetSize = targetSize
        let scale = min(
            Double(targetSize) / Double(max(1, sourceWidth)),
            Double(targetSize) / Double(max(1, sourceHeight))
        )
        contentWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
        contentHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))
        offsetX = (targetSize - contentWidth) / 2
        offsetY = (targetSize - contentHeight) / 2
    }

    func modelPoint(fromSource point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(
            x: (point.x * Double(contentWidth) + Double(offsetX)) / Double(targetSize),
            y: (point.y * Double(contentHeight) + Double(offsetY)) / Double(targetSize)
        )
    }

    func sourcePoint(fromModel point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(
            x: min(1, max(0,
                (point.x * Double(targetSize) - Double(offsetX)) / Double(contentWidth)
            )),
            y: min(1, max(0,
                (point.y * Double(targetSize) - Double(offsetY)) / Double(contentHeight)
            ))
        )
    }
}

final class CoreMLGolfObjectDetector: GolfObjectObservationProvider {
    private static let inputSize = 256
    private static let landmarkOrder: [SwingLandmark] = [
        .grip, .shaftStart, .shaftEnd, .clubhead, .ball
    ]

    private let model: MLModel

    init(modelURL: URL?) throws {
        guard let modelURL else {
            throw GolfObjectProviderError.modelUnavailable
        }
        do {
            model = try MLModel(contentsOf: modelURL)
        } catch {
            throw GolfObjectProviderError.modelUnavailable
        }
    }

    func observe(
        image: CGImage,
        pose: PoseEstimationResult?
    ) throws -> GolfObjectObservation {
        _ = pose
        let transform = AspectFitImageTransform(
            sourceWidth: image.width,
            sourceHeight: image.height,
            targetSize: Self.inputSize
        )
        let pixelBuffer = try makePixelBuffer(image: image, transform: transform)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let output: MLFeatureProvider
        do {
            output = try model.prediction(from: input)
        } catch {
            throw GolfObjectProviderError.invalidOutput
        }
        guard let coordinates = output.featureValue(for: "coordinates")?.multiArrayValue,
              let visibility = output.featureValue(for: "visibility")?.multiArrayValue,
              coordinates.count >= Self.landmarkOrder.count * 2,
              visibility.count >= Self.landmarkOrder.count else {
            throw GolfObjectProviderError.invalidOutput
        }

        var points: [SwingLandmark: TrackedSwingPoint] = [:]
        for (index, landmark) in Self.landmarkOrder.enumerated() {
            let probability = sigmoid(visibility[index].doubleValue)
            guard probability >= 0.5 else { continue }
            let modelPoint = NormalizedPoint(
                x: coordinates[index * 2].doubleValue,
                y: coordinates[index * 2 + 1].doubleValue
            )
            guard modelPoint.x.isFinite, modelPoint.y.isFinite else {
                throw GolfObjectProviderError.invalidOutput
            }
            points[landmark] = TrackedSwingPoint(
                point: transform.sourcePoint(fromModel: modelPoint),
                confidence: probability,
                state: .detected,
                source: .coreMLGolf
            )
        }
        return GolfObjectObservation(points: points)
    }

    private func makePixelBuffer(
        image: CGImage,
        transform: AspectFitImageTransform
    ) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            transform.targetSize,
            transform.targetSize,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw GolfObjectProviderError.invalidOutput
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: baseAddress,
                width: transform.targetSize,
                height: transform.targetSize,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            throw GolfObjectProviderError.invalidOutput
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(
            x: 0,
            y: 0,
            width: transform.targetSize,
            height: transform.targetSize
        ))
        context.translateBy(x: 0, y: CGFloat(transform.targetSize))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: transform.offsetX,
            y: transform.offsetY,
            width: transform.contentWidth,
            height: transform.contentHeight
        ))
        return buffer
    }

    private func sigmoid(_ value: Double) -> Double {
        1 / (1 + exp(-value))
    }
}
