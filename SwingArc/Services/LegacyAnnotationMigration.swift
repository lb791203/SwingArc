import Foundation

struct LegacyAnnotationMigrationResult: Equatable {
    let markers: [KeyframeMarker]
    let sanitizedPackage: AnnotationPackage
    let discardedUnreviewedFrameLabelCount: Int
}

enum LegacyAnnotationMigration {
    private static let completionPrefix =
        "com.liangbo.swingarc.legacy-annotation-migrated."

    static func migrate(
        package: AnnotationPackage,
        frameTimes: [Int: Double],
        existingMarkers: [KeyframeMarker]
    ) -> LegacyAnnotationMigrationResult {
        let sanitized = sanitize(package)
        let discarded = (package.activeDraft?.frameLabels.count ?? 0)
            - (sanitized.activeDraft?.frameLabels.count ?? 0)
        guard let pass = preferredPass(in: package) else {
            return .init(
                markers: existingMarkers,
                sanitizedPackage: sanitized,
                discardedUnreviewedFrameLabelCount: max(0, discarded)
            )
        }

        let selections = pass.stages.compactMap {
            selection -> (PPointCode, Int)? in
            guard selection.status == .manual,
                  let code = PPointCode(rawValue: selection.stage),
                  let frame = selection.sourceFrameIndex,
                  (0..<package.media.frameCount).contains(frame),
                  let time = frameTimes[frame],
                  time.isFinite,
                  time >= 0 else {
                return nil
            }
            return (code, frame)
        }
        let ordered = selections.sorted {
            $0.0.ordinal < $1.0.ordinal
        }
        guard zip(ordered, ordered.dropFirst()).allSatisfy({
            $0.0.1 < $0.1.1
        }) else {
            return .init(
                markers: existingMarkers,
                sanitizedPackage: sanitized,
                discardedUnreviewedFrameLabelCount: max(0, discarded)
            )
        }

        var markers = existingMarkers
        for (code, frame) in ordered {
            let stage = SwingStage.pStages[code.ordinal]
            if markers.contains(where: {
                $0.stage == stage.rawValue && $0.source == .manual
            }) {
                continue
            }
            markers.removeAll { $0.stage == stage.rawValue }
            markers.append(
                KeyframeMarker(
                    time: frameTimes[frame]!,
                    stage: stage,
                    source: .manual
                )
            )
        }
        markers.sort { $0.time < $1.time }
        return .init(
            markers: markers,
            sanitizedPackage: sanitized,
            discardedUnreviewedFrameLabelCount: max(0, discarded)
        )
    }

    static func sourceFrameIndices(
        package: AnnotationPackage
    ) -> [Int] {
        guard let pass = preferredPass(in: package) else { return [] }
        return Array(Set(pass.stages.compactMap { selection in
            guard selection.status == .manual,
                  let frame = selection.sourceFrameIndex,
                  (0..<package.media.frameCount).contains(frame) else {
                return nil
            }
            return frame
        })).sorted()
    }

    static func isCompleted(
        mediaSHA256: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: completionKey(mediaSHA256))
    }

    static func markCompleted(
        mediaSHA256: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: completionKey(mediaSHA256))
    }

    private static func sanitize(
        _ package: AnnotationPackage
    ) -> AnnotationPackage {
        var copy = package
        if var draft = copy.activeDraft {
            draft.frameLabels.removeAll { !$0.reviewed }
            copy.activeDraft = draft
        }
        return copy
    }

    private static func preferredPass(
        in package: AnnotationPackage
    ) -> AnnotationPass? {
        if let active = package.activeDraft {
            return active
        }
        return package.passes.max {
            let leftDate = $0.submittedAt ?? .distantPast
            let rightDate = $1.submittedAt ?? .distantPast
            if leftDate == rightDate {
                return $0.revision < $1.revision
            }
            return leftDate < rightDate
        }
    }

    private static func completionKey(_ mediaSHA256: String) -> String {
        completionPrefix + mediaSHA256
    }
}
