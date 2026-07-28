import Foundation

@main
struct LegacyFeedbackRoundTripSmoke {
    static func main() throws {
        let legacyJSON = """
        {
          "drawings": [],
          "keyframes": [],
          "isKeyframeMode": false,
          "showPoseSkeleton": true,
          "showHeadStability": false,
          "showSpineAngle": true,
          "showGrid": false,
          "practiceCameraView": "downTheLine",
          "stageCorrections": [],
          "feedbackConfiguration": {
            "activeMetric": "headPosition",
            "enabledCheckpoints": [
              {
                "metric": "headPosition",
                "stage": "上杆顶点 (Top)"
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let opened = try JSONDecoder().decode(
            LocalAnalysisProject.self,
            from: legacyJSON
        )
        guard let opaque = opened.legacyFeedbackConfiguration else {
            preconditionFailure("Legacy configuration must decode")
        }

        let edited = LocalAnalysisProject(
            drawings: opened.drawings,
            keyframes: [
                KeyframeMarker(
                    time: 1.2,
                    stage: .impact,
                    source: .manual,
                    sourceFrameIndex: 72
                )
            ],
            isKeyframeMode: true,
            showPoseSkeleton: opened.showPoseSkeleton,
            showHeadStability: opened.showHeadStability,
            showSpineAngle: opened.showSpineAngle,
            showGrid: opened.showGrid,
            practiceCameraView: opened.practiceCameraView,
            stageCorrections: opened.stageCorrections,
            legacyFeedbackConfiguration: opaque
        )
        let reencoded = try JSONEncoder().encode(edited)
        let reopened = try JSONDecoder().decode(
            LocalAnalysisProject.self,
            from: reencoded
        )
        precondition(reopened.legacyFeedbackConfiguration == opaque)
        precondition(reopened.keyframes.first?.isLocked == true)

        let reencodedObject = try JSONSerialization.jsonObject(
            with: reencoded
        ) as! [String: Any]
        precondition(reencodedObject["feedbackConfiguration"] != nil)

        let newProject = LocalAnalysisProject(
            drawings: [],
            keyframes: [],
            isKeyframeMode: false,
            showPoseSkeleton: false,
            showHeadStability: false,
            showSpineAngle: false,
            showGrid: false
        )
        let newObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(newProject)
        ) as! [String: Any]
        precondition(newObject["feedbackConfiguration"] == nil)

        let content = try String(
            contentsOfFile: "SwingArc/Views/ContentView.swift",
            encoding: .utf8
        )
        precondition(
            content.contains(
                "@State private var legacyFeedbackConfiguration: FeedbackConfiguration?"
            )
        )
        precondition(
            content.contains(
                "legacyFeedbackConfiguration = saved.legacyFeedbackConfiguration"
            )
        )
        precondition(
            content.contains(
                "legacyFeedbackConfiguration: legacyFeedbackConfiguration"
            )
        )
    }
}
