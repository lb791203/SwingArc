import CoreGraphics
import Foundation

struct SwingInputQualitySignals: Equatable {
    let poseFrameCoverage: Double
    let fullBodyCoverage: Double
    let clubCoverage: Double?
    let cameraMotion: Double
    let medianBlurScore: Double
}

struct SwingInputQualityPoint: Equatable {
    let x: Double
    let y: Double
}

struct SwingInputQualityFrame: Equatable {
    let poseDetected: Bool
    let fullBodyVisible: Bool
    let subjectCenter: SwingInputQualityPoint?
    let blurScore: Double
}

struct SwingInputLuminanceGrid: Equatable {
    let values: [Double]
    let width: Int
    let height: Int
}

enum SwingInputQualityIssue: String, Codable, Equatable {
    case personNotStable
    case fullBodyNotVisible
    case clubNotVisible
    case clubVisibilityNotAssessed
    case cameraMoved
    case motionBlur
}

enum SwingMotionBlurDisposition {
    case blocking
    case warning
}

struct SwingInputQualityReport: Equatable {
    let blockingIssues: [SwingInputQualityIssue]
    let warnings: [SwingInputQualityIssue]

    var issues: [SwingInputQualityIssue] {
        blockingIssues + warnings
    }

    var isSupported: Bool {
        blockingIssues.isEmpty
    }
}

enum SwingInputQualityEvaluator {
    private static let requiredFullBodyLandmarks: Set<String> = [
        "leftShoulder", "rightShoulder",
        "leftHip", "rightHip",
        "leftKnee", "rightKnee",
        "leftAnkle", "rightAnkle"
    ]

    static func isFullBodyVisible(landmarks: Set<String>) -> Bool {
        let hasHeadReference = landmarks.contains("nose") || landmarks.contains("neck")
        return hasHeadReference && requiredFullBodyLandmarks.isSubset(of: landmarks)
    }

    static func luminanceGrid(
        from image: CGImage,
        maximumDimension: Int = 32
    ) -> SwingInputLuminanceGrid? {
        guard maximumDimension >= 3, image.width > 0, image.height > 0 else { return nil }
        let scale = min(
            1,
            Double(maximumDimension) / Double(max(image.width, image.height))
        )
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let created = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else { return nil }
        return SwingInputLuminanceGrid(
            values: pixels.map { Double($0) / 255 },
            width: width,
            height: height
        )
    }

    static func blurScore(
        luminance: [Double],
        width: Int,
        height: Int
    ) -> Double {
        guard width >= 3,
              height >= 3,
              luminance.count == width * height else { return 0 }

        var squaredLaplacianSum = 0.0
        var sampleCount = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = luminance[y * width + x]
                let laplacian = center * 4
                    - luminance[(y - 1) * width + x]
                    - luminance[(y + 1) * width + x]
                    - luminance[y * width + x - 1]
                    - luminance[y * width + x + 1]
                squaredLaplacianSum += laplacian * laplacian
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return 0 }
        let rootMeanSquare = sqrt(squaredLaplacianSum / Double(sampleCount))
        return min(1, max(0, rootMeanSquare / 0.75))
    }

    static func summarize(
        frames: [SwingInputQualityFrame],
        clubCoverage: Double?
    ) -> SwingInputQualitySignals {
        guard !frames.isEmpty else {
            return SwingInputQualitySignals(
                poseFrameCoverage: 0,
                fullBodyCoverage: 0,
                clubCoverage: clubCoverage,
                cameraMotion: 1,
                medianBlurScore: 0
            )
        }

        let frameCount = Double(frames.count)
        let centers = frames.compactMap(\.subjectCenter)
        let centerDistances = zip(centers, centers.dropFirst()).map { first, second in
            hypot(second.x - first.x, second.y - first.y)
        }

        return SwingInputQualitySignals(
            poseFrameCoverage: Double(frames.filter(\.poseDetected).count) / frameCount,
            fullBodyCoverage: Double(frames.filter(\.fullBodyVisible).count) / frameCount,
            clubCoverage: clubCoverage,
            cameraMotion: median(centerDistances) ?? 0,
            medianBlurScore: median(frames.map(\.blurScore)) ?? 0
        )
    }

    static func evaluate(
        _ signal: SwingInputQualitySignals,
        motionBlurDisposition: SwingMotionBlurDisposition = .blocking
    ) -> SwingInputQualityReport {
        var blocking: [SwingInputQualityIssue] = []
        var warnings: [SwingInputQualityIssue] = []

        if signal.poseFrameCoverage < 0.85 {
            blocking.append(.personNotStable)
        }
        if signal.fullBodyCoverage < 0.85 {
            blocking.append(.fullBodyNotVisible)
        }
        if let clubCoverage = signal.clubCoverage {
            if clubCoverage < 0.80 {
                blocking.append(.clubNotVisible)
            }
        } else {
            warnings.append(.clubVisibilityNotAssessed)
        }
        if signal.cameraMotion > 0.04 {
            blocking.append(.cameraMoved)
        }
        if signal.medianBlurScore < 0.35 {
            switch motionBlurDisposition {
            case .blocking:
                blocking.append(.motionBlur)
            case .warning:
                warnings.append(.motionBlur)
            }
        }

        return SwingInputQualityReport(
            blockingIssues: blocking,
            warnings: warnings
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
