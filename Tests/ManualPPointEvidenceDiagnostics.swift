import Foundation

@main
struct ManualPPointEvidenceDiagnostics {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            fputs(
                "usage: manual-p-evidence <video-path> <frame> [frame...]\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let frameIndices = CommandLine.arguments.dropFirst(2).compactMap(Int.init)
        let provider = try ExactVideoFrameProvider.load(url: videoURL)
        let detector = VisionPoseDetector()
        let required = [
            "nose", "neck",
            "leftShoulder", "rightShoulder",
            "leftElbow", "rightElbow",
            "leftWrist", "rightWrist",
            "leftHip", "rightHip",
            "leftKnee", "rightKnee",
            "leftAnkle", "rightAnkle"
        ]

        for frameIndex in frameIndices {
            let frame = try provider.frame(at: frameIndex)
            guard let pose = detector.detectPose(
                in: frame.image,
                orientation: .up
            ) else {
                print("frame=\(frameIndex) pose=none")
                continue
            }
            let confidences = required.map {
                "\($0)=\(String(format: "%.3f", pose.keypoints[$0]?.confidence ?? 0))"
            }.joined(separator: " ")
            let conclusionGrade = required.filter {
                (pose.keypoints[$0]?.confidence ?? 0) >= 0.65
            }.count
            print(
                "frame=\(frameIndex) " +
                "time=\(String(format: "%.3f", frame.presentationTime.seconds)) " +
                "aggregate=\(String(format: "%.3f", pose.aggregateConfidence)) " +
                "grade=\(conclusionGrade)/\(required.count) " +
                confidences
            )
        }
    }
}
