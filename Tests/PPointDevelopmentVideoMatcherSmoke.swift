import Foundation

@main
struct PPointDevelopmentVideoMatcherSmoke {
    static func main() throws {
        let truth = PPointGroundTruthMedia(
            fileName: "phone-import.mp4",
            sha256: "exact-media",
            timelineSHA256: "timeline-a",
            frameCount: 200,
            width: 1920,
            height: 1080
        )
        let candidates = [
            PPointDevelopmentVideoCandidate(
                url: URL(fileURLWithPath: "/tmp/renamed.mov"),
                sha256: "different-container",
                timelineSHA256: "timeline-a",
                frameCount: 200
            ),
            PPointDevelopmentVideoCandidate(
                url: URL(fileURLWithPath: "/tmp/exact-copy.mp4"),
                sha256: "exact-media",
                timelineSHA256: "timeline-a",
                frameCount: 200
            )
        ]

        let exact = try PPointDevelopmentVideoMatcher.match(
            truth: truth,
            candidates: candidates
        )
        precondition(exact.url.lastPathComponent == "exact-copy.mp4")

        let timelineOnly = try PPointDevelopmentVideoMatcher.match(
            truth: PPointGroundTruthMedia(
                fileName: truth.fileName,
                sha256: "missing-media",
                timelineSHA256: truth.timelineSHA256,
                frameCount: truth.frameCount,
                width: truth.width,
                height: truth.height
            ),
            candidates: Array(candidates.prefix(1))
        )
        precondition(timelineOnly.url.lastPathComponent == "renamed.mov")

        do {
            _ = try PPointDevelopmentVideoMatcher.match(
                truth: truth,
                candidates: [
                    PPointDevelopmentVideoCandidate(
                        url: URL(fileURLWithPath: "/tmp/wrong.mov"),
                        sha256: "wrong",
                        timelineSHA256: "wrong-timeline",
                        frameCount: 200
                    )
                ]
            )
            preconditionFailure("Unmatched video must fail")
        } catch let error as PPointDevelopmentRunnerError {
            precondition(error == .videoNotFound("exact-media"))
        }
    }
}
