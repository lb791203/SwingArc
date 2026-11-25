import AVFoundation
import Foundation

/// Regression check for exact source-frame reading on real clips.
/// Every source frame must decode to itself, including passthrough-trimmed
/// clips (edit lists) and B-frame H.264.
///
/// Run with:
///   xcrun swiftc -parse-as-library \
///     SwingArc/Models/FrameExtractionTolerancePolicy.swift \
///     SwingArc/Services/ExactVideoFrameProvider.swift \
///     Tests/ExactFrameTimelineDiagnostics.swift -o /tmp/exact-frames && \
///   /tmp/exact-frames <video> [<video> ...]
@main
struct ExactFrameTimelineDiagnostics {
    static func main() throws {
        let paths = Array(CommandLine.arguments.dropFirst())
        precondition(!paths.isEmpty, "Pass one or more video paths")
        var anyFailure = false
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let provider = try ExactVideoFrameProvider.load(url: url)
            var failures: [Int] = []
            for index in 0..<provider.frameCount {
                do {
                    let frame = try provider.frame(at: index)
                    if frame.sourceFrameIndex != index { failures.append(index) }
                } catch {
                    failures.append(index)
                }
            }
            let firstTime = provider.timeline.presentationTime(sourceFrameIndex: 0)?.seconds ?? .nan
            print("\(url.lastPathComponent): frames=\(provider.frameCount) first=\(firstTime)s failures=\(failures.count) \(failures.prefix(10))")
            anyFailure = anyFailure || !failures.isEmpty
        }
        precondition(!anyFailure, "Some source frames did not decode to themselves")
    }
}
