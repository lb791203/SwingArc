import Foundation

@main
struct SimplifiedFeedbackPersistenceSmoke {
    static func main() throws {
        let legacyJSON = """
        {
          "drawings": [],
          "keyframes": [],
          "isKeyframeMode": false,
          "showPoseSkeleton": true,
          "showHeadStability": true,
          "showSpineAngle": true,
          "showGrid": false,
          "practiceCameraView": "downTheLine",
          "stageCorrections": [],
          "feedbackConfiguration": {
            "activeMetric": "headPosition",
            "enabledCheckpoints": []
          }
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(
            LocalAnalysisProject.self,
            from: legacyJSON
        )
        precondition(legacy.practiceCameraView == .downTheLine)
        precondition(
            legacy.legacyFeedbackConfiguration?.activeMetric == .headPosition
        )

        let correction = StageCorrection(
            stage: .impact,
            view: .downTheLine,
            automaticFrameIndex: 80,
            manualFrameIndex: 84
        )
        let current = LocalAnalysisProject(
            drawings: [],
            keyframes: [],
            isKeyframeMode: false,
            showPoseSkeleton: true,
            showHeadStability: true,
            showSpineAngle: true,
            showGrid: false,
            practiceCameraView: .downTheLine,
            stageCorrections: [correction]
        )
        let data = try JSONEncoder().encode(current)
        let roundTrip = try JSONDecoder().decode(
            LocalAnalysisProject.self,
            from: data
        )
        precondition(roundTrip.stageCorrections == [correction])
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(object["feedbackConfiguration"] == nil)
    }
}
