import Foundation

@main
struct PersonalCalibrationSmoke {
    static func main() {
        let corrections = (0..<8).flatMap { index in
            [
                StageCorrection(
                    stage: .top,
                    view: .downTheLine,
                    automaticFrameIndex: 100 + index,
                    manualFrameIndex: 103 + index
                ),
                StageCorrection(
                    stage: .impact,
                    view: .downTheLine,
                    automaticFrameIndex: 200 + index,
                    manualFrameIndex: 200 + index
                )
            ]
        }
        let calibration = PersonalCalibrationPolicy.update(
            current: .empty,
            corrections: corrections,
            view: .downTheLine
        )
        precondition(calibration.offsetFrames[.top] == 3)
        precondition(calibration.offsetFrames[.impact] == 0)

        let insufficient = PersonalCalibrationPolicy.update(
            current: .empty,
            corrections: Array(corrections.prefix(2)),
            view: .downTheLine
        )
        precondition(insufficient == .empty)

        let wrongView = PersonalCalibrationPolicy.update(
            current: .empty,
            corrections: corrections,
            view: .faceOn
        )
        precondition(wrongView == .empty)

        let clamped = PersonalCalibrationPolicy.update(
            current: .empty,
            corrections: (0..<8).map {
                StageCorrection(
                    stage: .top,
                    view: .downTheLine,
                    automaticFrameIndex: $0,
                    manualFrameIndex: $0 + 20
                )
            },
            view: .downTheLine
        )
        precondition(clamped.offsetFrames[.top] == 6)
    }
}
