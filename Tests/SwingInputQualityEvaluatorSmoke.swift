import CoreGraphics
import Foundation

@main
struct SwingInputQualityEvaluatorSmoke {
    static func main() {
        let rejected = SwingInputQualityEvaluator.evaluate(.init(
            poseFrameCoverage: 0.95,
            fullBodyCoverage: 0.60,
            clubCoverage: 0.90,
            cameraMotion: 0.01,
            medianBlurScore: 0.80
        ))
        precondition(!rejected.isSupported)
        precondition(rejected.issues == [.fullBodyNotVisible])

        let accepted = SwingInputQualityEvaluator.evaluate(.init(
            poseFrameCoverage: 0.95,
            fullBodyCoverage: 0.95,
            clubCoverage: 0.92,
            cameraMotion: 0.01,
            medianBlurScore: 0.80
        ))
        precondition(accepted.isSupported)
        precondition(accepted.issues.isEmpty)

        let unassessedClub = SwingInputQualityEvaluator.evaluate(.init(
            poseFrameCoverage: 0.95,
            fullBodyCoverage: 0.95,
            clubCoverage: nil,
            cameraMotion: 0.01,
            medianBlurScore: 0.80
        ))
        precondition(unassessedClub.isSupported)
        precondition(unassessedClub.warnings == [.clubVisibilityNotAssessed])

        let boundary = SwingInputQualityEvaluator.evaluate(.init(
            poseFrameCoverage: 0.85,
            fullBodyCoverage: 0.85,
            clubCoverage: 0.80,
            cameraMotion: 0.04,
            medianBlurScore: 0.35
        ))
        precondition(boundary.isSupported)
        precondition(boundary.issues.isEmpty)

        let allBlocking = SwingInputQualityEvaluator.evaluate(.init(
            poseFrameCoverage: 0.20,
            fullBodyCoverage: 0.20,
            clubCoverage: 0.20,
            cameraMotion: 0.20,
            medianBlurScore: 0.10
        ))
        precondition(allBlocking.blockingIssues == [
            .personNotStable,
            .fullBodyNotVisible,
            .clubNotVisible,
            .cameraMoved,
            .motionBlur
        ])

        let summarized = SwingInputQualityEvaluator.summarize(
            frames: [
                .init(poseDetected: true, fullBodyVisible: true, subjectCenter: .init(x: 0.50, y: 0.50), blurScore: 0.80),
                .init(poseDetected: true, fullBodyVisible: true, subjectCenter: .init(x: 0.51, y: 0.50), blurScore: 0.60),
                .init(poseDetected: false, fullBodyVisible: false, subjectCenter: nil, blurScore: 0.90),
                .init(poseDetected: true, fullBodyVisible: false, subjectCenter: .init(x: 0.53, y: 0.50), blurScore: 0.70)
            ],
            clubCoverage: nil
        )
        precondition(summarized.poseFrameCoverage == 0.75)
        precondition(summarized.fullBodyCoverage == 0.50)
        precondition(abs(summarized.cameraMotion - 0.015) < 0.000_001)
        precondition(abs(summarized.medianBlurScore - 0.75) < 0.000_001)
        precondition(summarized.clubCoverage == nil)

        let requiredBody: Set<String> = [
            "nose", "leftShoulder", "rightShoulder", "leftHip", "rightHip",
            "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"
        ]
        precondition(SwingInputQualityEvaluator.isFullBodyVisible(landmarks: requiredBody))
        precondition(SwingInputQualityEvaluator.isFullBodyVisible(
            landmarks: requiredBody.subtracting(["nose"]).union(["neck"])
        ))
        precondition(!SwingInputQualityEvaluator.isFullBodyVisible(
            landmarks: requiredBody.subtracting(["rightAnkle"])
        ))
        precondition(!SwingInputQualityEvaluator.isFullBodyVisible(
            landmarks: requiredBody.subtracting(["nose"])
        ))

        let flat = Array(repeating: 0.5, count: 25)
        precondition(SwingInputQualityEvaluator.blurScore(
            luminance: flat,
            width: 5,
            height: 5
        ) == 0)
        let sharp: [Double] = [
            0, 1, 0, 1, 0,
            1, 0, 1, 0, 1,
            0, 1, 0, 1, 0,
            1, 0, 1, 0, 1,
            0, 1, 0, 1, 0
        ]
        precondition(SwingInputQualityEvaluator.blurScore(
            luminance: sharp,
            width: 5,
            height: 5
        ) > 0.90)

        let grayBytes = Data(repeating: 128, count: 8 * 4)
        let provider = CGDataProvider(data: grayBytes as CFData)!
        let grayImage = CGImage(
            width: 8,
            height: 4,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let grid = SwingInputQualityEvaluator.luminanceGrid(
            from: grayImage,
            maximumDimension: 4
        )
        precondition(grid?.width == 4)
        precondition(grid?.height == 2)
        precondition(grid?.values.allSatisfy { abs($0 - (128.0 / 255.0)) < 0.01 } == true)
    }
}
