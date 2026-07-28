import SwiftUI

enum SwingTrajectorySegmentStyle: Equatable {
    case measured
    case estimated
    case hidden
}

enum SwingTrajectoryPresentationPolicy {
    static let measuredConfidenceThreshold = 0.65

    static func landmarks(
        for category: SwingFeedbackCategory
    ) -> [SwingLandmark] {
        category.trajectoryLandmarks
    }

    static func style(
        for point: TrackedSwingPoint
    ) -> SwingTrajectorySegmentStyle {
        guard point.point != nil,
              point.state != .missing,
              point.state != .occluded,
              point.state != .outOfFrame
        else {
            return .hidden
        }

        if point.isEstimated {
            return .estimated
        }

        guard point.isMeasured,
              point.confidence >= measuredConfidenceThreshold
        else {
            return .hidden
        }

        return .measured
    }

    static func style(
        from start: TrackedSwingPoint,
        to end: TrackedSwingPoint
    ) -> SwingTrajectorySegmentStyle {
        let styles = [style(for: start), style(for: end)]
        if styles.contains(.hidden) {
            return .hidden
        }
        if styles.contains(.estimated) {
            return .estimated
        }
        return .measured
    }
}

struct SwingTrajectoryStageTime {
    let stage: SwingStage
    let time: Double
}

struct SwingTrajectoryOverlay: View {
    let category: SwingFeedbackCategory
    let frames: [SwingFrameObservation]
    let stageTimes: [SwingTrajectoryStageTime]
    let videoRect: CGRect

    private struct Segment {
        let start: NormalizedPoint
        let end: NormalizedPoint
        let style: SwingTrajectorySegmentStyle
    }

    private var segments: [Segment] {
        SwingTrajectoryPresentationPolicy.landmarks(for: category).flatMap {
            segments(for: $0)
        }
    }

    var body: some View {
        Canvas { context, _ in
            for segment in segments {
                var path = Path()
                path.move(to: screenPoint(segment.start))
                path.addLine(to: screenPoint(segment.end))

                let color = AnalysisTheme.proTourSignal.opacity(
                    segment.style == .measured ? 0.92 : 0.55
                )
                let stroke = StrokeStyle(
                    lineWidth: segment.style == .measured ? 2.5 : 2,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: segment.style == .estimated ? [6, 5] : []
                )
                context.stroke(path, with: .color(color), style: stroke)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func segments(
        for landmark: SwingLandmark
    ) -> [Segment] {
        let samples = category.stages.compactMap { stage -> TrackedSwingPoint? in
            guard let stageTime = stageTimes.first(where: { $0.stage == stage }),
                  let frame = nearestFrame(to: stageTime.time)
            else {
                return nil
            }
            return frame.landmarks[landmark]
        }

        guard samples.count >= 2 else { return [] }

        return zip(samples, samples.dropFirst()).compactMap { start, end in
            let style = SwingTrajectoryPresentationPolicy.style(
                from: start,
                to: end
            )
            guard style != .hidden,
                  let startPoint = start.point,
                  let endPoint = end.point
            else {
                return nil
            }
            return Segment(start: startPoint, end: endPoint, style: style)
        }
    }

    private func nearestFrame(
        to time: Double
    ) -> SwingFrameObservation? {
        frames.min {
            abs($0.time - time) < abs($1.time - time)
        }
    }

    private func screenPoint(
        _ point: NormalizedPoint
    ) -> CGPoint {
        CGPoint(
            x: videoRect.minX + CGFloat(point.x) * videoRect.width,
            y: videoRect.minY + CGFloat(point.y) * videoRect.height
        )
    }

    private var accessibilitySummary: String {
        let measured = segments.filter { $0.style == .measured }.count
        let estimated = segments.filter { $0.style == .estimated }.count
        return "\(category.title)轨迹，\(measured)段实测，\(estimated)段估算"
    }
}
