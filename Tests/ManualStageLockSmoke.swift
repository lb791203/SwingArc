import Foundation

@main
struct ManualStageLockSmoke {
    static func main() {
        let manual = KeyframeMarker(time: 0.42, stage: .top, source: .manual)
        let automatic = KeyframeMarker(time: 0.55, stage: .top, source: .automatic)
        let merged = StageMarkerMerger.merge(existing: [manual], automatic: [automatic])
        precondition(merged == [manual])
    }
}
