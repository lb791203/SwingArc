import SwiftUI

struct WorkspaceHeaderView: View {
    let projectName: String
    let saveStatus: WorkspaceSaveStatus
    let hasResults: Bool
    let isRegularLayout: Bool
    let showsProjectSidebar: Bool
    let showsInspector: Bool
    let onBack: () -> Void
    let onToggleProjectSidebar: () -> Void
    let onToggleInspector: () -> Void
    let onShowResults: () -> Void
    let onAnnotate: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .background(AnalysisTheme.proTourSurface, in: Circle())
            }
            .accessibilityLabel("返回项目库")

            if isRegularLayout {
                Button(action: onToggleProjectSidebar) {
                    Image(systemName: showsProjectSidebar ? "sidebar.left" : "sidebar.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsProjectSidebar ? "收起项目栏" : "展开项目栏")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("ANALYSIS ROOM")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(AnalysisTheme.proTourSecondaryText)
                Text(projectName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if !saveStatus.label.isEmpty {
                    Label(saveStatus.label, systemImage: saveStatus == .failed ? "exclamationmark.circle" : "checkmark")
                        .font(.caption2)
                        .foregroundStyle(saveStatus == .failed ? AnalysisTheme.proTourPaused : AnalysisTheme.proTourSignal)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 4)

            if hasResults {
                Button(action: onShowResults) {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("查看分析结果")
            }

            Button(action: onAnnotate) {
                Text("标注")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("打开精确标注")

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
                    .background(AnalysisTheme.proTourSurface, in: Circle())
            }
            .accessibilityLabel("导出")

            if isRegularLayout {
                Button(action: onToggleInspector) {
                    Image(systemName: "sidebar.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsInspector ? "收起检查器" : "展开检查器")
            }
        }
        .fontWeight(.semibold)
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(AnalysisTheme.proTourBackground)
    }
}

struct StageTimelineView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    let keyframes: [KeyframeMarker]
    let presentation: AnalysisWorkspacePresentation
    let onStageTap: (SwingStage, KeyframeMarker?) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(formatTime(playbackManager.currentTime))
                Slider(
                    value: Binding(
                        get: { min(playbackManager.currentTime, max(playbackManager.duration, 0)) },
                        set: { playbackManager.seek(to: $0) }
                    ),
                    in: 0...max(playbackManager.duration, 0.001)
                )
                .tint(AnalysisTheme.proTourSignal)
                .accessibilityLabel("视频时间轴")
                Text(formatTime(playbackManager.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AnalysisTheme.proTourSecondaryText)

            HStack(spacing: 3) {
                ForEach(SwingStage.allCases) { stage in
                    let descriptor = StageDisplayDescriptor(
                        stage: stage,
                        keyframes: keyframes,
                        presentation: presentation,
                        currentTime: playbackManager.currentTime,
                        frameDuration: VideoFramePolicy.frameDuration(sourceFrameRate: playbackManager.sourceFrameRate)
                    )
                    Button {
                        onStageTap(stage, descriptor.marker)
                    } label: {
                        VStack(spacing: 3) {
                            Text(stage.pNumber)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                            Image(
                                systemName: StageStripPolicy
                                    .indicator(for: descriptor.resultState)
                                    .rawValue
                            )
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(descriptor.stageStripColor)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: StageStripPolicy.buttonHeight)
                        .background(AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    descriptor.isCurrent ? AnalysisTheme.proTourSignal : AnalysisTheme.proTourRaisedSurface,
                                    lineWidth: descriptor.isCurrent ? 1.5 : 1
                                )
                        }
                        .overlay(alignment: .bottom) {
                            if descriptor.isCurrent {
                                Capsule()
                                    .fill(AnalysisTheme.proTourSignal)
                                    .frame(height: 3)
                                    .padding(.horizontal, 5)
                                    .padding(.bottom, 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(descriptor.accessibilityLabel)
                    .accessibilityHint(descriptor.marker == nil ? "打开人工设置" : "跳到该阶段")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxHeight: StageStripPolicy.maximumTotalHeight)
        .background(AnalysisTheme.proTourBackground)
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "00:00.00" }
        let value = max(time, 0)
        let minutes = Int(value) / 60
        let seconds = Int(value) % 60
        let hundredths = Int((value.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }
}

/// Compact review controls stay visible on iPhone. Each P-stage is represented
/// by its own swing silhouette, while unresolved positions remain visible but
/// cannot be tapped until the analysis has evidence for them.
struct MobileReplayTimelineView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    let keyframes: [KeyframeMarker]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(formatTime(playbackManager.currentTime))
                Slider(
                    value: Binding(
                        get: { min(max(playbackManager.currentTime, 0), max(playbackManager.duration, 0.001)) },
                        set: { time in
                            playbackManager.pause()
                            playbackManager.seek(to: time)
                        }
                    ),
                    in: 0...max(playbackManager.duration, 0.001)
                )
                .tint(.white)
                .accessibilityLabel("视频进度")
                Text(formatTime(playbackManager.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.76))

            HStack(spacing: 0) {
                ForEach(SwingStage.allCases) { stage in
                    let marker = keyframes.first { $0.stage == stage.rawValue }
                    Button {
                        guard let marker else { return }
                        playbackManager.pause()
                        playbackManager.seek(to: marker.time)
                    } label: {
                        ZStack {
                            if isCurrent(marker) {
                                Circle()
                                    .stroke(.white, lineWidth: 1.5)
                                    .frame(width: 42, height: 42)
                            }

                            SwingStagePoseGlyph(
                                stage: stage,
                                isResolved: marker != nil
                            )
                            .frame(width: 40, height: 48)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(marker != nil)
                    .accessibilityLabel(
                        marker == nil
                            ? "\(stage.pNumber)，\(SwingStagePoseCue.description(for: stage))，尚未识别"
                            : "\(stage.pNumber)，\(SwingStagePoseCue.description(for: stage))，跳到该阶段"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "00:00" }
        let value = max(time, 0)
        return String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60)
    }

    private func isCurrent(_ marker: KeyframeMarker?) -> Bool {
        guard let marker else { return false }
        return abs(playbackManager.currentTime - marker.time) <= 0.18
    }
}

/// The replay rail is a pose legend, not eight copies of the same SF Symbol.
/// It follows the P1–P8 checkpoint sequence.  The body is deliberately drawn
/// heavier than the club so a golfer can read the movement at phone size.
private struct SwingStagePoseGlyph: View {
    let stage: SwingStage
    let isResolved: Bool

    var body: some View {
        Canvas { context, size in
            let pose = SwingStagePoseLibrary.pose(for: stage)
            let bodyColor = isResolved ? Color.white : Color.white.opacity(0.40)
            let clubColor = isResolved ? Color.white.opacity(0.88) : Color.white.opacity(0.30)
            let bodyLineWidth = max(2.25, min(size.width, size.height) * 0.065)
            let clubLineWidth = max(1.25, bodyLineWidth * 0.56)

            context.stroke(
                path(for: pose.spine, in: size),
                with: .color(bodyColor),
                style: StrokeStyle(lineWidth: bodyLineWidth * 1.12, lineCap: .round, lineJoin: .round)
            )
            for stroke in [pose.shoulders, pose.hips] {
                context.stroke(
                    path(for: stroke, in: size),
                    with: .color(bodyColor),
                    style: StrokeStyle(lineWidth: bodyLineWidth * 0.78, lineCap: .round, lineJoin: .round)
                )
            }
            for limb in pose.limbs {
                context.stroke(
                    path(for: limb, in: size),
                    with: .color(bodyColor),
                    style: StrokeStyle(lineWidth: bodyLineWidth, lineCap: .round, lineJoin: .round)
                )
            }
            context.stroke(
                path(for: pose.club, in: size),
                with: .color(clubColor),
                style: StrokeStyle(lineWidth: clubLineWidth, lineCap: .round, lineJoin: .round)
            )
            if let clubHead = clubHeadPath(for: pose.club, in: size) {
                context.stroke(
                    clubHead,
                    with: .color(clubColor),
                    style: StrokeStyle(lineWidth: clubLineWidth * 1.55, lineCap: .round)
                )
            }

            let headCenter = point(pose.head, in: size)
            let headDiameter = max(5.2, min(size.width, size.height) * 0.155)
            let head = CGRect(
                x: headCenter.x - headDiameter / 2,
                y: headCenter.y - headDiameter / 2,
                width: headDiameter,
                height: headDiameter
            )
            context.fill(Path(ellipseIn: head), with: .color(bodyColor))

            if let ball = pose.ball {
                let center = point(ball, in: size)
                let diameter = max(2.5, min(size.width, size.height) * 0.072)
                let rect = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(isResolved ? AnalysisTheme.proTourSignal : Color.white.opacity(0.35))
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func point(_ normalized: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    private func path(for normalizedPoints: [CGPoint], in size: CGSize) -> Path {
        guard let first = normalizedPoints.first else { return Path() }
        var path = Path()
        path.move(to: point(first, in: size))
        for next in normalizedPoints.dropFirst() {
            path.addLine(to: point(next, in: size))
        }
        return path
    }

    private func clubHeadPath(for club: [CGPoint], in size: CGSize) -> Path? {
        guard club.count >= 2 else { return nil }
        let tip = point(club[club.count - 1], in: size)
        let preceding = point(club[club.count - 2], in: size)
        let dx = tip.x - preceding.x
        let dy = tip.y - preceding.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return nil }

        let halfWidth = max(1.5, min(size.width, size.height) * 0.055)
        let perpendicular = CGPoint(
            x: -dy / length * halfWidth,
            y: dx / length * halfWidth
        )
        var path = Path()
        path.move(to: CGPoint(x: tip.x - perpendicular.x, y: tip.y - perpendicular.y))
        path.addLine(to: CGPoint(x: tip.x + perpendicular.x, y: tip.y + perpendicular.y))
        return path
    }
}

private enum SwingStagePoseCue {
    static func description(for stage: SwingStage) -> String {
        switch stage {
        case .address:
            return "准备：双膝微屈，杆头落在球后"
        case .takeaway:
            return "起杆：杆身在身后平行地面"
        case .leadArmParallelBackswing:
            return "上杆左臂平行：左臂平行地面，右肘收拢"
        case .top:
            return "上杆顶点：双手越过后肩，杆身横过肩线"
        case .leadArmParallelDownswing:
            return "下杆左臂平行：左臂平行地面，杆身从身后下落"
        case .shaftParallelDownswing:
            return "下杆杆身平行：双手降至前髋，杆身水平滞后"
        case .impact:
            return "击球：双臂伸向球位，杆身前倾"
        case .followThrough:
            return "送杆杆身平行：双臂越过身体，杆身再次平行"
        case .finish:
            return "收杆：重心落在前脚，杆身绕到背后"
        }
    }
}

private struct SwingStagePose {
    let head: CGPoint
    let spine: [CGPoint]
    let shoulders: [CGPoint]
    let hips: [CGPoint]
    let leadArm: [CGPoint]
    let trailArm: [CGPoint]
    let leadLeg: [CGPoint]
    let trailLeg: [CGPoint]
    let club: [CGPoint]
    let ball: CGPoint?

    var limbs: [[CGPoint]] {
        [leadArm, trailArm, leadLeg, trailLeg]
    }
}

private enum SwingStagePoseLibrary {
    static func pose(for stage: SwingStage) -> SwingStagePose {
        switch stage {
        case .address:
            return SwingStagePose(
                head: CGPoint(x: 0.44, y: 0.16),
                spine: [CGPoint(x: 0.46, y: 0.30), CGPoint(x: 0.53, y: 0.56)],
                shoulders: [CGPoint(x: 0.42, y: 0.31), CGPoint(x: 0.50, y: 0.32)],
                hips: [CGPoint(x: 0.48, y: 0.56), CGPoint(x: 0.58, y: 0.57)],
                leadArm: [CGPoint(x: 0.42, y: 0.32), CGPoint(x: 0.54, y: 0.45), CGPoint(x: 0.63, y: 0.59)],
                trailArm: [CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.56, y: 0.47), CGPoint(x: 0.63, y: 0.59)],
                leadLeg: [CGPoint(x: 0.48, y: 0.56), CGPoint(x: 0.39, y: 0.75), CGPoint(x: 0.34, y: 0.94)],
                trailLeg: [CGPoint(x: 0.58, y: 0.57), CGPoint(x: 0.63, y: 0.76), CGPoint(x: 0.70, y: 0.94)],
                club: [CGPoint(x: 0.63, y: 0.59), CGPoint(x: 0.87, y: 0.93)],
                ball: CGPoint(x: 0.90, y: 0.94)
            )
        case .takeaway:
            return SwingStagePose(
                head: CGPoint(x: 0.44, y: 0.16),
                spine: [CGPoint(x: 0.46, y: 0.30), CGPoint(x: 0.53, y: 0.56)],
                shoulders: [CGPoint(x: 0.42, y: 0.31), CGPoint(x: 0.50, y: 0.32)],
                hips: [CGPoint(x: 0.48, y: 0.56), CGPoint(x: 0.58, y: 0.57)],
                leadArm: [CGPoint(x: 0.42, y: 0.32), CGPoint(x: 0.31, y: 0.41), CGPoint(x: 0.18, y: 0.46)],
                trailArm: [CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.35, y: 0.46), CGPoint(x: 0.18, y: 0.46)],
                leadLeg: [CGPoint(x: 0.48, y: 0.56), CGPoint(x: 0.39, y: 0.75), CGPoint(x: 0.34, y: 0.94)],
                trailLeg: [CGPoint(x: 0.58, y: 0.57), CGPoint(x: 0.63, y: 0.76), CGPoint(x: 0.70, y: 0.94)],
                club: [CGPoint(x: 0.18, y: 0.46), CGPoint(x: 0.03, y: 0.46)],
                ball: nil
            )
        case .leadArmParallelBackswing:
            return SwingStagePose(
                head: CGPoint(x: 0.47, y: 0.15),
                spine: [CGPoint(x: 0.48, y: 0.30), CGPoint(x: 0.54, y: 0.56)],
                shoulders: [CGPoint(x: 0.44, y: 0.31), CGPoint(x: 0.53, y: 0.33)],
                hips: [CGPoint(x: 0.49, y: 0.56), CGPoint(x: 0.59, y: 0.57)],
                leadArm: [CGPoint(x: 0.44, y: 0.31), CGPoint(x: 0.31, y: 0.34), CGPoint(x: 0.14, y: 0.34)],
                trailArm: [CGPoint(x: 0.53, y: 0.33), CGPoint(x: 0.38, y: 0.43), CGPoint(x: 0.14, y: 0.34)],
                leadLeg: [CGPoint(x: 0.49, y: 0.56), CGPoint(x: 0.40, y: 0.76), CGPoint(x: 0.35, y: 0.94)],
                trailLeg: [CGPoint(x: 0.59, y: 0.57), CGPoint(x: 0.65, y: 0.77), CGPoint(x: 0.72, y: 0.94)],
                club: [CGPoint(x: 0.14, y: 0.34), CGPoint(x: 0.05, y: 0.04)],
                ball: nil
            )
        case .top:
            return SwingStagePose(
                head: CGPoint(x: 0.55, y: 0.17),
                spine: [CGPoint(x: 0.52, y: 0.30), CGPoint(x: 0.55, y: 0.57)],
                shoulders: [CGPoint(x: 0.47, y: 0.31), CGPoint(x: 0.57, y: 0.31)],
                hips: [CGPoint(x: 0.50, y: 0.57), CGPoint(x: 0.60, y: 0.57)],
                leadArm: [CGPoint(x: 0.47, y: 0.31), CGPoint(x: 0.32, y: 0.22), CGPoint(x: 0.20, y: 0.16)],
                trailArm: [CGPoint(x: 0.57, y: 0.31), CGPoint(x: 0.39, y: 0.21), CGPoint(x: 0.20, y: 0.16)],
                leadLeg: [CGPoint(x: 0.50, y: 0.57), CGPoint(x: 0.41, y: 0.77), CGPoint(x: 0.36, y: 0.94)],
                trailLeg: [CGPoint(x: 0.60, y: 0.57), CGPoint(x: 0.66, y: 0.77), CGPoint(x: 0.73, y: 0.94)],
                club: [CGPoint(x: 0.20, y: 0.16), CGPoint(x: 0.63, y: 0.12)],
                ball: nil
            )
        case .leadArmParallelDownswing:
            return SwingStagePose(
                head: CGPoint(x: 0.58, y: 0.17),
                spine: [CGPoint(x: 0.55, y: 0.30), CGPoint(x: 0.53, y: 0.56)],
                shoulders: [CGPoint(x: 0.51, y: 0.31), CGPoint(x: 0.60, y: 0.33)],
                hips: [CGPoint(x: 0.48, y: 0.56), CGPoint(x: 0.58, y: 0.57)],
                leadArm: [CGPoint(x: 0.51, y: 0.31), CGPoint(x: 0.66, y: 0.31), CGPoint(x: 0.80, y: 0.32)],
                trailArm: [CGPoint(x: 0.60, y: 0.33), CGPoint(x: 0.64, y: 0.45), CGPoint(x: 0.80, y: 0.32)],
                leadLeg: [CGPoint(x: 0.48, y: 0.56), CGPoint(x: 0.40, y: 0.76), CGPoint(x: 0.34, y: 0.94)],
                trailLeg: [CGPoint(x: 0.58, y: 0.57), CGPoint(x: 0.65, y: 0.77), CGPoint(x: 0.72, y: 0.94)],
                club: [CGPoint(x: 0.80, y: 0.32), CGPoint(x: 0.60, y: 0.05)],
                ball: nil
            )
        case .shaftParallelDownswing:
            return SwingStagePose(
                head: CGPoint(x: 0.58, y: 0.18),
                spine: [CGPoint(x: 0.55, y: 0.31), CGPoint(x: 0.52, y: 0.57)],
                shoulders: [CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.60, y: 0.34)],
                hips: [CGPoint(x: 0.47, y: 0.57), CGPoint(x: 0.57, y: 0.58)],
                leadArm: [CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.65, y: 0.45), CGPoint(x: 0.76, y: 0.54)],
                trailArm: [CGPoint(x: 0.60, y: 0.34), CGPoint(x: 0.65, y: 0.51), CGPoint(x: 0.76, y: 0.54)],
                leadLeg: [CGPoint(x: 0.47, y: 0.57), CGPoint(x: 0.41, y: 0.77), CGPoint(x: 0.35, y: 0.94)],
                trailLeg: [CGPoint(x: 0.57, y: 0.58), CGPoint(x: 0.65, y: 0.78), CGPoint(x: 0.73, y: 0.94)],
                club: [CGPoint(x: 0.76, y: 0.54), CGPoint(x: 0.34, y: 0.54)],
                ball: nil
            )
        case .impact:
            return SwingStagePose(
                head: CGPoint(x: 0.58, y: 0.18),
                spine: [CGPoint(x: 0.55, y: 0.31), CGPoint(x: 0.52, y: 0.57)],
                shoulders: [CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.60, y: 0.34)],
                hips: [CGPoint(x: 0.47, y: 0.57), CGPoint(x: 0.57, y: 0.58)],
                leadArm: [CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.65, y: 0.45), CGPoint(x: 0.82, y: 0.55)],
                trailArm: [CGPoint(x: 0.60, y: 0.34), CGPoint(x: 0.70, y: 0.48), CGPoint(x: 0.82, y: 0.55)],
                leadLeg: [CGPoint(x: 0.47, y: 0.57), CGPoint(x: 0.41, y: 0.77), CGPoint(x: 0.35, y: 0.94)],
                trailLeg: [CGPoint(x: 0.57, y: 0.58), CGPoint(x: 0.67, y: 0.77), CGPoint(x: 0.75, y: 0.91)],
                club: [CGPoint(x: 0.82, y: 0.55), CGPoint(x: 0.95, y: 0.86)],
                ball: CGPoint(x: 0.96, y: 0.88)
            )
        case .followThrough:
            return SwingStagePose(
                head: CGPoint(x: 0.58, y: 0.16),
                spine: [CGPoint(x: 0.55, y: 0.29), CGPoint(x: 0.58, y: 0.55)],
                shoulders: [CGPoint(x: 0.51, y: 0.30), CGPoint(x: 0.60, y: 0.31)],
                hips: [CGPoint(x: 0.52, y: 0.55), CGPoint(x: 0.63, y: 0.56)],
                leadArm: [CGPoint(x: 0.51, y: 0.30), CGPoint(x: 0.68, y: 0.36), CGPoint(x: 0.85, y: 0.40)],
                trailArm: [CGPoint(x: 0.60, y: 0.31), CGPoint(x: 0.70, y: 0.41), CGPoint(x: 0.85, y: 0.40)],
                leadLeg: [CGPoint(x: 0.52, y: 0.55), CGPoint(x: 0.44, y: 0.76), CGPoint(x: 0.39, y: 0.94)],
                trailLeg: [CGPoint(x: 0.63, y: 0.56), CGPoint(x: 0.72, y: 0.72), CGPoint(x: 0.81, y: 0.88)],
                club: [CGPoint(x: 0.85, y: 0.40), CGPoint(x: 0.99, y: 0.40)],
                ball: nil
            )
        case .finish:
            return SwingStagePose(
                head: CGPoint(x: 0.57, y: 0.15),
                spine: [CGPoint(x: 0.55, y: 0.29), CGPoint(x: 0.59, y: 0.55)],
                shoulders: [CGPoint(x: 0.51, y: 0.30), CGPoint(x: 0.60, y: 0.31)],
                hips: [CGPoint(x: 0.55, y: 0.55), CGPoint(x: 0.65, y: 0.56)],
                leadArm: [CGPoint(x: 0.51, y: 0.30), CGPoint(x: 0.37, y: 0.18), CGPoint(x: 0.24, y: 0.12)],
                trailArm: [CGPoint(x: 0.60, y: 0.31), CGPoint(x: 0.42, y: 0.20), CGPoint(x: 0.24, y: 0.12)],
                leadLeg: [CGPoint(x: 0.55, y: 0.55), CGPoint(x: 0.46, y: 0.76), CGPoint(x: 0.42, y: 0.94)],
                trailLeg: [CGPoint(x: 0.65, y: 0.56), CGPoint(x: 0.75, y: 0.70), CGPoint(x: 0.82, y: 0.88)],
                club: [CGPoint(x: 0.24, y: 0.12), CGPoint(x: 0.11, y: 0.02)],
                ball: nil
            )
        }
    }
}

struct PlaybackControlsView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    @Binding var interactionMode: WorkspaceInteractionMode
    let hasResults: Bool
    let onToggleDrawing: () -> Void
    let onAnalyze: () -> Void
    let onShowResults: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(PlaybackRate.allCases) { rate in
                    Button(rate.label) { playbackManager.setSpeed(rate.value) }
                }
            } label: {
                Text(speedLabel)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(minWidth: 48, minHeight: 44)
                    .background(AnalysisTheme.proTourSurface, in: Capsule())
            }
            .accessibilityLabel("播放速度，当前 \(speedLabel)")

            controlButton("backward.frame.fill", label: "后退一帧") {
                playbackManager.stepFrame(forward: false)
            }

            Button {
                if playbackManager.isPlaying {
                    playbackManager.pause()
                } else {
                    interactionMode = WorkspaceModeTransition.beginPlayback.mode
                    playbackManager.play()
                }
            } label: {
                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(width: 54, height: 54)
                    .foregroundStyle(.black)
                    .background(AnalysisTheme.proTourSignal, in: Circle())
            }
            .accessibilityLabel(playbackManager.isPlaying ? "暂停" : "播放")

            controlButton("forward.frame.fill", label: "前进一帧") {
                playbackManager.stepFrame(forward: true)
            }

            Button(action: onToggleDrawing) {
                Image(systemName: "pencil.tip")
                    .frame(width: 44, height: 44)
                    .background(
                        interactionMode == .drawing ? AnalysisTheme.proTourSignal : AnalysisTheme.proTourSurface,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                .foregroundStyle(interactionMode == .drawing ? AnalysisTheme.proTourBackground : AnalysisTheme.proTourPrimaryText)
            }
            .accessibilityLabel(interactionMode == .drawing ? "结束画线" : "画线")

            Button(action: hasResults ? onShowResults : onAnalyze) {
                VStack(spacing: 1) {
                    Image(systemName: hasResults ? "list.bullet.rectangle" : "sparkles")
                    Text(hasResults ? "结果" : "分析")
                        .font(.caption2.weight(.semibold))
                }
                .frame(width: 50, height: 44)
                .background(
                    hasResults ? AnalysisTheme.proTourSurface : AnalysisTheme.proTourSignal,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(hasResults ? AnalysisTheme.proTourPrimaryText : AnalysisTheme.proTourBackground)
            }
            .disabled(playbackManager.isScanning)
            .accessibilityLabel(hasResults ? "查看分析结果" : "开始 AI 分析")
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(AnalysisTheme.proTourBackground)
    }

    private var speedLabel: String {
        PlaybackRate.allCases.first(where: { abs($0.value - playbackManager.playbackSpeed) < 0.001 })?.label
            ?? String(format: "%.2g×", playbackManager.playbackSpeed)
    }

    private func controlButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .background(AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(label)
    }
}

struct DrawingToolRail: View {
    @Binding var activeTool: DrawingTool
    @Binding var selectedColor: Color
    @Binding var isKeyframeMode: Bool
    let onUndo: () -> Void
    let onClear: () -> Void
    let onDone: () -> Void

    @State private var confirmsClear = false
    @State private var showsColorPalette = false

    var body: some View {
        VStack(spacing: 5) {
            railButton(
                systemImage: "xmark",
                label: "关闭画线工具",
                isActive: false
            ) {
                showsColorPalette = false
                onDone()
            }

            ForEach(DrawingTool.allCases) { tool in
                toolButton(tool)
            }

            Button {
                showsColorPalette = false
                isKeyframeMode.toggle()
            } label: {
                Image(systemName: isKeyframeMode ? "pin.fill" : "rectangle.inset.filled")
                    .frame(width: 44, height: 44)
                    .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
            }
            .foregroundStyle(.white)
            .accessibilityLabel(isKeyframeMode ? "仅当前 P 点显示" : "全视频显示")
            .accessibilityHint(isKeyframeMode ? "切换为全视频显示" : "切换为仅当前 P 点显示")

            DrawingUndoControl(
                onUndo: onUndo,
                onRequestClear: { confirmsClear = true }
            )
        }
        .padding(6)
        .frame(maxWidth: WorkspaceAccessoryPolicy.drawingRailMaximumWidth)
        .fixedSize(horizontal: true, vertical: false)
        .background(AnalysisTheme.chrome.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .confirmationDialog("清除所有标注？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清除", role: .destructive, action: onClear)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除项目中的所有画线。")
        }
        .onAppear {
            showsColorPalette = activeTool.revealsColorPalette
        }
        .onChange(of: activeTool) { _, tool in
            showsColorPalette = tool.revealsColorPalette
        }
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        railButton(
            systemImage: tool.iconName,
            label: tool.rawValue,
            isActive: activeTool == tool,
            symbolColor: tool.revealsColorPalette ? selectedColor : nil
        ) {
            if activeTool == tool, tool.revealsColorPalette {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsColorPalette.toggle()
                }
            } else {
                activeTool = tool
                showsColorPalette = tool.revealsColorPalette
            }
        }
        .overlay(alignment: .trailing) {
            if activeTool == tool, tool.revealsColorPalette, showsColorPalette {
                DrawingColorPalette(selectedColor: $selectedColor) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsColorPalette = false
                    }
                }
                .fixedSize()
                .offset(x: -52)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .zIndex(activeTool == tool && showsColorPalette ? 2 : 0)
    }

    private func railButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        symbolColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .foregroundStyle(symbolColor ?? (isActive ? AnalysisTheme.current : .white))
                .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(isActive ? AnalysisTheme.current : .clear, lineWidth: 2)
                )
        }
        .accessibilityLabel(label)
    }
}

private struct DrawingColorPalette: View {
    @Binding var selectedColor: Color
    let onSelect: () -> Void

    private let colors: [(name: String, color: Color)] = [
        ("红色", .red),
        ("黄色", .yellow),
        ("绿色", .green),
        ("蓝色", .blue),
        ("白色", .white)
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, option in
                Button {
                    selectedColor = option.color
                    onSelect()
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(option.color)
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.65), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
            }
        }
        .padding(6)
        .background(AnalysisTheme.chrome.opacity(0.96), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
    }
}

private struct DrawingUndoControl: View {
    let onUndo: () -> Void
    let onRequestClear: () -> Void

    var body: some View {
        Image(systemName: "arrow.uturn.backward")
            .frame(width: 44, height: 44)
            .foregroundStyle(.white)
            .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.6)
                    .exclusively(before: TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first(true):
                            if DrawingRailPolicy.undoIntent(isLongPress: true) == .confirmClearAll {
                                onRequestClear()
                            }
                        case .second:
                            if DrawingRailPolicy.undoIntent(isLongPress: false) == .undoLast {
                                onUndo()
                            }
                        default:
                            break
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("撤销")
            .accessibilityHint("轻点撤销最后一笔，长按清除全部标注")
            .accessibilityAction(named: Text("撤销"), onUndo)
            .accessibilityAction(named: Text("清除全部标注"), onRequestClear)
    }
}

struct AnalysisProgressCard: View {
    let phase: AnalysisProgressPhase
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        let presentation = AnalysisProgressPresentation(phase: phase, progress: progress)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title).font(.subheadline.weight(.semibold))
                    Text(presentation.detail).font(.caption).foregroundStyle(AnalysisTheme.proTourSecondaryText)
                }
                Spacer()
                Text("\(presentation.percentage)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                Button("取消", action: onCancel)
                    .font(.caption.weight(.semibold))
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(AnalysisTheme.proTourSignal)
        }
        .foregroundStyle(AnalysisTheme.proTourPrimaryText)
        .padding(12)
        .background(AnalysisTheme.proTourSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AnalysisTheme.proTourRaisedSurface))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.title)，\(presentation.percentage)%")
    }
}

struct AnalysisFailureBanner: View {
    let failure: AnalysisFailure

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AnalysisTheme.proTourPaused)
            Text(AnalysisFailurePresentation(failure: failure).message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AnalysisTheme.proTourPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AnalysisTheme.proTourSurface)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(AnalysisTheme.proTourPaused)
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StageInspectorView: View {
    let presentation: AnalysisWorkspacePresentation
    let keyframes: [KeyframeMarker]
    let sourceFrameRate: Double
    let onSeek: (Double) -> Void
    let onAdjust: (SwingStage) -> Void

    var body: some View {
        let descriptors = SwingStage.allCases.map {
            StageDisplayDescriptor(
                stage: $0,
                keyframes: keyframes,
                presentation: presentation,
                currentTime: -1,
                frameDuration: 0
            )
        }
        let summary = StageResultSummary(statuses: descriptors.map(\.resultState))

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("阶段结果")
                    .font(.headline)
                Text("已确认 \(summary.confirmed) · 待核对 \(summary.review) · 未确定 \(summary.unresolved)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(descriptors, id: \.stage.id) { descriptor in
                        HStack(spacing: 10) {
                            Text(descriptor.stage.pNumber)
                                .font(.subheadline.weight(.bold))
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(descriptor.stage.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(descriptor.detailText(sourceFrameRate: sourceFrameRate))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let marker = descriptor.marker {
                                Button("查看") { onSeek(marker.time) }
                                    .font(.caption.weight(.semibold))
                            }
                            Button("调整") { onAdjust(descriptor.stage) }
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(descriptor.borderColor))
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

struct WorkspaceInspectorView: View {
    @ObservedObject var playbackManager: VideoPlaybackManager
    let presentation: AnalysisWorkspacePresentation
    let keyframes: [KeyframeMarker]
    @Binding var showPoseSkeleton: Bool
    @Binding var showHeadStability: Bool
    @Binding var showSpineAngle: Bool
    @Binding var showGrid: Bool
    let onCancelAnalysis: () -> Void
    let onSeek: (Double) -> Void
    let onAdjust: (SwingStage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if playbackManager.isScanning {
                AnalysisProgressCard(
                    phase: playbackManager.analysisProgressPhase,
                    progress: playbackManager.scanProgress,
                    onCancel: onCancelAnalysis
                )
            } else {
                StageInspectorView(
                    presentation: presentation,
                    keyframes: keyframes,
                    sourceFrameRate: playbackManager.sourceFrameRate,
                    onSeek: onSeek,
                    onAdjust: onAdjust
                )
            }

            if let failure = playbackManager.analysisFailure {
                AnalysisFailureBanner(failure: failure)
            }

            Divider().overlay(.white.opacity(0.14))

            VStack(alignment: .leading, spacing: 8) {
                Text("叠层")
                    .font(.headline)
                Toggle("骨架", isOn: $showPoseSkeleton)
                Toggle("头部轨迹", isOn: $showHeadStability)
                Toggle("身体倾斜", isOn: $showSpineAngle)
                Toggle("参考网格", isOn: $showGrid)
            }
            .disabled(!presentation.allowsPoseOverlays)

            if !presentation.allowsPoseOverlays {
                Text("分析完成后可开启人体叠层")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(AnalysisTheme.chrome)
    }
}

struct StageAdjustmentBar: View {
    let stage: SwingStage
    let detection: SwingStageDetection?
    @ObservedObject var playbackManager: VideoPlaybackManager
    let onCancel: () -> Void
    let onSetCurrentFrame: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(stage.shortName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(confidenceLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(confidenceColor)
                Spacer(minLength: 4)
                Text("\(formatTime(playbackManager.currentTime)) · #\(currentFrame)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .foregroundStyle(.white.opacity(0.78))
                .accessibilityLabel("取消调整")
            }

            HStack(spacing: 8) {
                frameButton(systemImage: "backward.frame.fill", label: "前一帧") {
                    playbackManager.stepFrame(forward: false)
                }

                Button(action: onSetCurrentFrame) {
                    Text("设为当前帧")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(AnalysisTheme.confirmed, in: RoundedRectangle(cornerRadius: 12))

                frameButton(systemImage: "forward.frame.fill", label: "后一帧") {
                    playbackManager.stepFrame(forward: true)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AnalysisTheme.chrome)
        .overlay(alignment: .top) { Divider().overlay(.white.opacity(0.10)) }
    }

    private var currentFrame: Int {
        Int((playbackManager.currentTime * max(playbackManager.sourceFrameRate, 1)).rounded())
    }

    private var confidenceLabel: String {
        switch detection?.status {
        case .confirmed: return "已确认"
        case .lowConfidence: return "待核对"
        case .unresolved, nil: return "未确定"
        }
    }

    private var confidenceColor: Color {
        switch detection?.status {
        case .confirmed: return AnalysisTheme.confirmed
        case .lowConfidence: return AnalysisTheme.current
        case .unresolved, nil: return .white.opacity(0.55)
        }
    }

    private func formatTime(_ value: Double) -> String {
        String(format: "%.3fs", max(value, 0))
    }

    private func frameButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 48, height: 44)
                .background(AnalysisTheme.raisedChrome, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

struct WorkspaceProjectSidebar: View {
    let projects: [LocalProjectSummary]
    let selectedProjectID: UUID
    let onSelect: (LocalProjectSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("项目")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(projects) { project in
                        Button { onSelect(project) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(project.modifiedAt, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                project.id == selectedProjectID ? AnalysisTheme.raisedChrome : .clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .background(AnalysisTheme.chrome)
    }
}

struct GridView: View {
    let rect: CGRect

    var body: some View {
        Canvas { context, _ in
            guard rect.width > 0, rect.height > 0 else { return }
            var path = Path()
            for index in 1..<3 {
                let x = rect.minX + rect.width * CGFloat(index) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * CGFloat(index) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}

struct SwingPhaseRailView: View {
    let keyframes: [KeyframeMarker]
    let presentation: AnalysisWorkspacePresentation
    let currentTime: Double
    let frameDuration: Double
    let duration: Double
    let onSelect: (Double) -> Void
    let onScrub: (Double) -> Void

    var body: some View {
        VStack(spacing: 5) {
            Slider(
                value: Binding(
                    get: { min(max(currentTime, 0), max(duration, 0.001)) },
                    set: onScrub
                ),
                in: 0...max(duration, 0.001)
            )
            .tint(AnalysisTheme.proTourSignal)
            .accessibilityLabel("挥杆进度")

            HStack(spacing: 0) {
                ForEach(visibleDescriptors, id: \.stage) { descriptor in
                    Button {
                        if let marker = descriptor.marker {
                            onSelect(marker.time)
                        }
                    } label: {
                        SwingPhaseSilhouette(
                            stage: descriptor.stage,
                            isCurrent: descriptor.isCurrent,
                            resultState: descriptor.resultState
                        )
                        .frame(maxWidth: .infinity, minHeight: FullscreenPlaybackPolicy.minimumTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(descriptor.accessibilityLabel)
                    .accessibilityHint("跳到该挥杆位置")
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var visibleDescriptors: [StageDisplayDescriptor] {
        SwingStage.allCases.compactMap { stage in
            let descriptor = StageDisplayDescriptor(
                stage: stage,
                keyframes: keyframes,
                presentation: presentation,
                currentTime: currentTime,
                frameDuration: frameDuration
            )
            guard descriptor.marker != nil,
                  SwingPhaseRailPolicy.appearance(
                    for: descriptor.resultState,
                    hasMarker: true
                  ) != .hidden
            else {
                return nil
            }
            return descriptor
        }
    }
}

private struct SwingPhaseSilhouette: View {
    let stage: SwingStage
    let isCurrent: Bool
    let resultState: StageResultState

    private var clubAngle: Angle {
        switch stage {
        case .address: .degrees(-20)
        case .takeaway: .degrees(-48)
        case .leadArmParallelBackswing: .degrees(-72)
        case .top: .degrees(-112)
        case .leadArmParallelDownswing: .degrees(38)
        case .shaftParallelDownswing: .degrees(0)
        case .impact: .degrees(18)
        case .followThrough: .degrees(0)
        case .finish: .degrees(105)
        }
    }

    private var accent: Color {
        if isCurrent { return .white }
        switch resultState {
        case .confirmed, .manual: return AnalysisTheme.proTourSignal
        case .review: return AnalysisTheme.current.opacity(0.45)
        case .unresolved: return .white.opacity(0.28)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(isCurrent ? .white : .clear, lineWidth: 1.5)
                .frame(width: 36, height: 36)

            Circle()
                .fill(accent)
                .frame(width: 5.5, height: 5.5)
                .offset(y: -11)

            Capsule()
                .fill(accent)
                .frame(width: 3.5, height: 15)
                .offset(y: -2)

            Capsule()
                .fill(accent)
                .frame(width: 2.5, height: 13)
                .rotationEffect(clubAngle)
                .offset(x: 6, y: -2)
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct StageDisplayDescriptor {
    let stage: SwingStage
    let marker: KeyframeMarker?
    let detection: SwingStageDetection?
    let isCurrent: Bool

    init(
        stage: SwingStage,
        keyframes: [KeyframeMarker],
        presentation: AnalysisWorkspacePresentation,
        currentTime: Double,
        frameDuration: Double
    ) {
        self.stage = stage
        marker = keyframes.first { $0.stage == stage.rawValue }
        detection = presentation.detection(for: stage)
        if let marker, currentTime >= 0 {
            isCurrent = abs(marker.time - currentTime) <= max(frameDuration * 1.5, 0.02)
        } else {
            isCurrent = false
        }
    }

    var resultState: StageResultState {
        if marker?.isLocked == true { return .manual }
        if detection?.status == .lowConfidence { return .review }
        if marker != nil { return .confirmed }
        return .unresolved
    }

    var stageStripColor: Color {
        switch resultState {
        case .confirmed, .manual: return AnalysisTheme.confirmed
        case .review: return AnalysisTheme.current
        case .unresolved: return .white.opacity(0.42)
        }
    }

    var symbol: String {
        if isCurrent { return "location.fill" }
        switch resultState {
        case .confirmed: return "checkmark"
        case .manual: return "lock.fill"
        case .review: return "exclamationmark"
        case .unresolved: return "minus"
        }
    }

    var shortStatus: String {
        if isCurrent { return "当前" }
        switch resultState {
        case .confirmed: return "已确认"
        case .manual: return "已锁定"
        case .review: return "待核对"
        case .unresolved: return "未确定"
        }
    }

    var foregroundColor: Color {
        isCurrent ? .black : .white
    }

    var backgroundColor: Color {
        if isCurrent { return AnalysisTheme.current }
        switch resultState {
        case .confirmed, .manual: return AnalysisTheme.confirmed.opacity(0.18)
        case .review: return AnalysisTheme.current.opacity(0.16)
        case .unresolved: return AnalysisTheme.raisedChrome
        }
    }

    var borderColor: Color {
        if isCurrent { return AnalysisTheme.current }
        switch resultState {
        case .confirmed, .manual: return AnalysisTheme.confirmed.opacity(0.72)
        case .review: return AnalysisTheme.current.opacity(0.78)
        case .unresolved: return .white.opacity(0.10)
        }
    }

    var accessibilityLabel: String {
        var parts = [stage.shortName, shortStatus]
        if let marker {
            parts.append(String(format: "%.3f 秒", marker.time))
        }
        return parts.joined(separator: "，")
    }

    func detailText(sourceFrameRate: Double) -> String {
        guard let marker else { return shortStatus }
        let frame = detection?.sourceFrameIndex
            ?? Int((marker.time * max(sourceFrameRate, 1)).rounded())
        var parts = [
            String(format: "%.3f 秒", marker.time),
            "第 \(frame) 帧",
            shortStatus
        ]
        if let detection {
            parts.append("置信度 \(Int((detection.confidence * 100).rounded()))%")
            if stage == .takeaway || stage == .impact {
                parts.append(detection.hasClubEvidence ? "有杆身" : "无杆身")
            }
            if stage == .impact {
                parts.append(detection.hasBallEvidence ? "有球位" : "无球位")
            }
        }
        return parts.joined(separator: " · ")
    }
}

private extension SwingStage {
    var pNumber: String {
        guard let index = SwingStage.allCases.firstIndex(of: self) else {
            return "收杆"
        }
        return "P\(index + 1)"
    }

    var displayName: String {
        switch self {
        case .address: return "准备"
        case .takeaway: return "起杆"
        case .leadArmParallelBackswing: return "上杆左臂平行"
        case .top: return "上杆顶点"
        case .leadArmParallelDownswing: return "下杆左臂平行"
        case .shaftParallelDownswing: return "下杆杆身平行"
        case .impact: return "击球"
        case .followThrough: return "送杆"
        case .finish: return "收杆"
        }
    }
}
