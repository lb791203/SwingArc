import Foundation

struct PrecisionEvaluationInput: Codable {
    let datasetHash: String
    let artifactVersion: String
    let modelVersion: String
    let clips: [PrecisionClipEvaluation]
    let inputRejections: [PrecisionInputRejectionResult]
    let device: PrecisionDeviceMeasurement
}

struct PrecisionClipEvaluation: Codable {
    let clipID: String
    let golferID: String?
    let split: DatasetSplit
    let view: DatasetView?
    let stages: [PrecisionStageEvaluation]
    let bodyLandmarks: [PrecisionBodyLandmarkEvaluation]
    let clubheadFrames: [PrecisionClubheadFrameEvaluation]
    let metrics: [SwingMetricValue]
}

struct PrecisionStageEvaluation: Codable {
    let stage: String
    let referenceFrame: Int?
    let predictedFrame: Int?
    let status: String
}

struct PrecisionBodyLandmarkEvaluation: Codable {
    let landmark: String
    let normalizedError: Double?
}

struct PrecisionClubheadFrameEvaluation: Codable {
    let sourceFrameIndex: Int
    let visibleInReference: Bool
    let normalizedError: Double?
}

struct PrecisionInputRejectionResult: Codable {
    let caseID: String
    let expectedRejected: Bool
    let actualRejected: Bool
    let reason: String

    var passed: Bool {
        expectedRejected == actualRejected
    }
}

struct PrecisionInputRejectionReport: Codable {
    let caseID: String
    let expectedRejected: Bool
    let actualRejected: Bool
    let reason: String
    let passed: Bool
}

struct PrecisionDeviceMeasurement: Codable {
    let device: String
    let operatingSystem: String
    let elapsedSeconds: Double
    let peakMemoryMB: Double
}

struct PrecisionEvaluationReport: Codable {
    let datasetHash: String
    let artifactVersion: String
    let modelVersion: String
    let golferCounts: [PrecisionGolferCount]
    let heldOutGolferCount: Int
    let views: [PrecisionViewCoverage]
    let stageRates: [PrecisionStageRate]
    let bodyLandmarks: [PrecisionBodyLandmarkSummary]
    let bodyLandmarkMedianError: Double?
    let clubhead: PrecisionClubheadSummary
    let clubheadByView: [PrecisionClubheadViewSummary]
    let inputRejections: [PrecisionInputRejectionReport]
    let unsupportedMetricsHaveNoMeasuredValues: Bool
    let device: PrecisionDeviceMeasurement
    let releasePassed: Bool
    let failedThresholds: [String]
}

struct PrecisionGolferCount: Codable {
    let split: DatasetSplit
    let view: DatasetView
    let golferCount: Int
}

struct PrecisionViewCoverage: Codable {
    let view: DatasetView
    let heldOutGolferCount: Int
    let hasHeldOutCoverage: Bool
}

struct PrecisionStageRate: Codable {
    let view: DatasetView
    let stage: String
    let referenceCount: Int
    let hitCount: Int
    let unresolvedCount: Int
    let falseConfirmationCount: Int
    let hitRate: Double
    let unresolvedRate: Double
    let falseConfirmationRate: Double
}

struct PrecisionBodyLandmarkSummary: Codable {
    let view: DatasetView
    let landmark: String
    let sampleCount: Int
    let measuredCount: Int
    let medianError: Double?
    let p90Error: Double?
    let missRate: Double
}

struct PrecisionClubheadSummary: Codable {
    let visibleFrameCount: Int
    let hitCount: Int
    let visibleFrameHitRate: Double
    let medianError: Double?
    let p90Error: Double?
    let maximumAcceptedError: Double
    let gapCount: Int
    let missingVisibleFrameCount: Int
}

struct PrecisionClubheadViewSummary: Codable {
    let view: DatasetView
    let summary: PrecisionClubheadSummary
}

extension PrecisionEvaluationReport {
    private enum CodingKeys: String, CodingKey {
        case datasetHash
        case artifactVersion
        case modelVersion
        case golferCounts
        case heldOutGolferCount
        case views
        case stageRates
        case bodyLandmarks
        case bodyLandmarkMedianError
        case clubhead
        case clubheadByView
        case inputRejections
        case unsupportedMetricsHaveNoMeasuredValues
        case device
        case releasePassed
        case failedThresholds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(datasetHash, forKey: .datasetHash)
        try container.encode(artifactVersion, forKey: .artifactVersion)
        try container.encode(modelVersion, forKey: .modelVersion)
        try container.encode(golferCounts, forKey: .golferCounts)
        try container.encode(heldOutGolferCount, forKey: .heldOutGolferCount)
        try container.encode(views, forKey: .views)
        try container.encode(stageRates, forKey: .stageRates)
        try container.encode(bodyLandmarks, forKey: .bodyLandmarks)
        try container.encodeExplicitNil(
            bodyLandmarkMedianError,
            forKey: .bodyLandmarkMedianError
        )
        try container.encode(clubhead, forKey: .clubhead)
        try container.encode(clubheadByView, forKey: .clubheadByView)
        try container.encode(inputRejections, forKey: .inputRejections)
        try container.encode(
            unsupportedMetricsHaveNoMeasuredValues,
            forKey: .unsupportedMetricsHaveNoMeasuredValues
        )
        try container.encode(device, forKey: .device)
        try container.encode(releasePassed, forKey: .releasePassed)
        try container.encode(failedThresholds, forKey: .failedThresholds)
    }
}

extension PrecisionBodyLandmarkSummary {
    private enum CodingKeys: String, CodingKey {
        case view
        case landmark
        case sampleCount
        case measuredCount
        case medianError
        case p90Error
        case missRate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(view, forKey: .view)
        try container.encode(landmark, forKey: .landmark)
        try container.encode(sampleCount, forKey: .sampleCount)
        try container.encode(measuredCount, forKey: .measuredCount)
        try container.encodeExplicitNil(medianError, forKey: .medianError)
        try container.encodeExplicitNil(p90Error, forKey: .p90Error)
        try container.encode(missRate, forKey: .missRate)
    }
}

extension PrecisionClubheadSummary {
    private enum CodingKeys: String, CodingKey {
        case visibleFrameCount
        case hitCount
        case visibleFrameHitRate
        case medianError
        case p90Error
        case maximumAcceptedError
        case gapCount
        case missingVisibleFrameCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleFrameCount, forKey: .visibleFrameCount)
        try container.encode(hitCount, forKey: .hitCount)
        try container.encode(visibleFrameHitRate, forKey: .visibleFrameHitRate)
        try container.encodeExplicitNil(medianError, forKey: .medianError)
        try container.encodeExplicitNil(p90Error, forKey: .p90Error)
        try container.encode(
            maximumAcceptedError,
            forKey: .maximumAcceptedError
        )
        try container.encode(gapCount, forKey: .gapCount)
        try container.encode(
            missingVisibleFrameCount,
            forKey: .missingVisibleFrameCount
        )
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeExplicitNil<T: Encodable>(
        _ value: T?,
        forKey key: Key
    ) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

enum PrecisionEvaluationReportBuilder {
    static let requiredStages = (1...8).map { "P\($0)" }
    static let maximumAcceptedStageFrameError = 2
    static let minimumHeldOutGolferCount = 10
    static let minimumStageHitRate = 0.90
    static let maximumBodyLandmarkMedianError = 0.03
    static let minimumClubheadVisibleFrameHitRate = 0.90
    static let clubheadMaximumAcceptedError = 0.02

    private static let orderedSplits: [DatasetSplit] = [
        .development,
        .training,
        .validation,
        .heldOut
    ]
    private static let orderedViews: [DatasetView] = [
        .downTheLine,
        .faceOn
    ]

    static func makeReport(from input: PrecisionEvaluationInput) -> PrecisionEvaluationReport {
        let heldOutClips = input.clips.filter { $0.split == .heldOut }
        let heldOutGolferCount = uniqueGolfers(in: heldOutClips).count
        let golferCounts = orderedSplits.flatMap { split in
            orderedViews.map { view in
                PrecisionGolferCount(
                    split: split,
                    view: view,
                    golferCount: uniqueGolfers(
                        in: input.clips.filter {
                            $0.split == split && $0.view == view
                        }
                    ).count
                )
            }
        }
        let views = orderedViews.map { view in
            let count = uniqueGolfers(
                in: heldOutClips.filter { $0.view == view }
            ).count
            return PrecisionViewCoverage(
                view: view,
                heldOutGolferCount: count,
                hasHeldOutCoverage: count > 0
            )
        }
        let stageRates = orderedViews.flatMap { view in
            requiredStages.map { stage in
                summarizeStage(
                    heldOutClips: heldOutClips,
                    view: view,
                    stage: stage
                )
            }
        }
        let bodyLandmarks = summarizeBodyLandmarks(heldOutClips: heldOutClips)
        let allBodyErrors = heldOutClips.flatMap(\.bodyLandmarks)
            .compactMap { finiteValue($0.normalizedError) }
        let bodyLandmarkMedianError = percentile(allBodyErrors, percentile: 0.50)
        let clubhead = summarizeClubhead(clips: heldOutClips)
        let clubheadByView = orderedViews.map { view in
            PrecisionClubheadViewSummary(
                view: view,
                summary: summarizeClubhead(
                    clips: heldOutClips.filter { $0.view == view }
                )
            )
        }
        let unsupportedMetricsHaveNoMeasuredValues = heldOutClips
            .flatMap(\.metrics)
            .filter { !$0.id.isSupportedBySingleCamera }
            .allSatisfy { metric in
                guard metric.value == nil else { return false }
                if case .measured = metric.availability {
                    return false
                }
                return true
            }

        let releasePassed = heldOutGolferCount >= minimumHeldOutGolferCount
            && views.allSatisfy(\.hasHeldOutCoverage)
            && stageRates.allSatisfy { $0.hitRate >= minimumStageHitRate }
            && (bodyLandmarkMedianError.map {
                $0 <= maximumBodyLandmarkMedianError
            } ?? false)
            && clubhead.visibleFrameHitRate >= minimumClubheadVisibleFrameHitRate
            && clubhead.maximumAcceptedError == clubheadMaximumAcceptedError
            && unsupportedMetricsHaveNoMeasuredValues

        let failedThresholds = failures(
            heldOutGolferCount: heldOutGolferCount,
            views: views,
            stageRates: stageRates,
            bodyLandmarkMedianError: bodyLandmarkMedianError,
            clubhead: clubhead,
            unsupportedMetricsHaveNoMeasuredValues: unsupportedMetricsHaveNoMeasuredValues
        )

        return PrecisionEvaluationReport(
            datasetHash: input.datasetHash,
            artifactVersion: input.artifactVersion,
            modelVersion: input.modelVersion,
            golferCounts: golferCounts,
            heldOutGolferCount: heldOutGolferCount,
            views: views,
            stageRates: stageRates,
            bodyLandmarks: bodyLandmarks,
            bodyLandmarkMedianError: bodyLandmarkMedianError,
            clubhead: clubhead,
            clubheadByView: clubheadByView,
            inputRejections: input.inputRejections.map {
                PrecisionInputRejectionReport(
                    caseID: $0.caseID,
                    expectedRejected: $0.expectedRejected,
                    actualRejected: $0.actualRejected,
                    reason: $0.reason,
                    passed: $0.passed
                )
            },
            unsupportedMetricsHaveNoMeasuredValues: unsupportedMetricsHaveNoMeasuredValues,
            device: input.device,
            releasePassed: releasePassed,
            failedThresholds: failedThresholds
        )
    }

    private static func uniqueGolfers(
        in clips: [PrecisionClipEvaluation]
    ) -> Set<String> {
        Set(clips.compactMap(\.golferID).filter { !$0.isEmpty })
    }

    private static func summarizeStage(
        heldOutClips: [PrecisionClipEvaluation],
        view: DatasetView,
        stage: String
    ) -> PrecisionStageRate {
        let records = heldOutClips
            .filter { $0.view == view }
            .flatMap(\.stages)
            .filter { $0.stage == stage }
        let references = records.filter { $0.referenceFrame != nil }
        let hits = references.filter(isStageHit)
        let unresolved = references.filter { record in
            record.predictedFrame == nil || normalizedStatus(record.status) == "unresolved"
        }
        let falseConfirmations = records.filter(isFalseConfirmation)
        let falseConfirmationDenominator = max(
            references.count + records.filter { $0.referenceFrame == nil }.count,
            1
        )
        return PrecisionStageRate(
            view: view,
            stage: stage,
            referenceCount: references.count,
            hitCount: hits.count,
            unresolvedCount: unresolved.count,
            falseConfirmationCount: falseConfirmations.count,
            hitRate: rate(numerator: hits.count, denominator: references.count),
            unresolvedRate: rate(
                numerator: unresolved.count,
                denominator: references.count
            ),
            falseConfirmationRate: Double(falseConfirmations.count)
                / Double(falseConfirmationDenominator)
        )
    }

    private static func isStageHit(_ record: PrecisionStageEvaluation) -> Bool {
        guard normalizedStatus(record.status) != "unresolved",
              let reference = record.referenceFrame,
              let predicted = record.predictedFrame else {
            return false
        }
        return abs(predicted - reference) <= maximumAcceptedStageFrameError
    }

    private static func isFalseConfirmation(
        _ record: PrecisionStageEvaluation
    ) -> Bool {
        guard normalizedStatus(record.status) == "confirmed",
              let predicted = record.predictedFrame else {
            return false
        }
        guard let reference = record.referenceFrame else {
            return true
        }
        return abs(predicted - reference) > maximumAcceptedStageFrameError
    }

    private static func normalizedStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func summarizeBodyLandmarks(
        heldOutClips: [PrecisionClipEvaluation]
    ) -> [PrecisionBodyLandmarkSummary] {
        let landmarks = Set(
            heldOutClips.flatMap(\.bodyLandmarks).map(\.landmark)
        ).sorted()
        return orderedViews.flatMap { view in
            landmarks.compactMap { landmark in
                let samples = heldOutClips
                    .filter { $0.view == view }
                    .flatMap(\.bodyLandmarks)
                    .filter { $0.landmark == landmark }
                guard !samples.isEmpty else { return nil }
                let errors = samples.compactMap {
                    finiteValue($0.normalizedError)
                }
                return PrecisionBodyLandmarkSummary(
                    view: view,
                    landmark: landmark,
                    sampleCount: samples.count,
                    measuredCount: errors.count,
                    medianError: percentile(errors, percentile: 0.50),
                    p90Error: percentile(errors, percentile: 0.90),
                    missRate: rate(
                        numerator: samples.count - errors.count,
                        denominator: samples.count
                    )
                )
            }
        }
    }

    private static func summarizeClubhead(
        clips: [PrecisionClipEvaluation]
    ) -> PrecisionClubheadSummary {
        let visibleFrames = clips.flatMap(\.clubheadFrames)
            .filter(\.visibleInReference)
        let errors = visibleFrames.compactMap {
            finiteValue($0.normalizedError)
        }
        let hitCount = errors.filter {
            $0 <= clubheadMaximumAcceptedError
        }.count
        var gapCount = 0
        var missingVisibleFrameCount = 0
        for clip in clips {
            var isInsideGap = false
            for frame in clip.clubheadFrames
                .sorted(by: { $0.sourceFrameIndex < $1.sourceFrameIndex })
                where frame.visibleInReference {
                if finiteValue(frame.normalizedError) == nil {
                    missingVisibleFrameCount += 1
                    if !isInsideGap {
                        gapCount += 1
                        isInsideGap = true
                    }
                } else {
                    isInsideGap = false
                }
            }
        }
        return PrecisionClubheadSummary(
            visibleFrameCount: visibleFrames.count,
            hitCount: hitCount,
            visibleFrameHitRate: rate(
                numerator: hitCount,
                denominator: visibleFrames.count
            ),
            medianError: percentile(errors, percentile: 0.50),
            p90Error: percentile(errors, percentile: 0.90),
            maximumAcceptedError: clubheadMaximumAcceptedError,
            gapCount: gapCount,
            missingVisibleFrameCount: missingVisibleFrameCount
        )
    }

    private static func failures(
        heldOutGolferCount: Int,
        views: [PrecisionViewCoverage],
        stageRates: [PrecisionStageRate],
        bodyLandmarkMedianError: Double?,
        clubhead: PrecisionClubheadSummary,
        unsupportedMetricsHaveNoMeasuredValues: Bool
    ) -> [String] {
        var failures: [String] = []
        if heldOutGolferCount < minimumHeldOutGolferCount {
            failures.append("heldOutGolferCount >= 10")
        }
        if !views.allSatisfy(\.hasHeldOutCoverage) {
            failures.append("held-out coverage for dtl and face-on")
        }
        for stage in stageRates where stage.hitRate < minimumStageHitRate {
            failures.append(
                "\(stage.view.rawValue)/\(stage.stage) hitRate >= 0.90"
            )
        }
        if !(bodyLandmarkMedianError.map {
            $0 <= maximumBodyLandmarkMedianError
        } ?? false) {
            failures.append("body landmark median error <= 0.03")
        }
        if clubhead.visibleFrameHitRate < minimumClubheadVisibleFrameHitRate {
            failures.append("clubhead visible-frame hit rate >= 0.90")
        }
        if clubhead.maximumAcceptedError != clubheadMaximumAcceptedError {
            failures.append("clubhead maximum accepted error == 0.02")
        }
        if !unsupportedMetricsHaveNoMeasuredValues {
            failures.append("unsupported metrics have no measured values")
        }
        return failures
    }

    private static func rate(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private static func finiteValue(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func percentile(
        _ values: [Double],
        percentile: Double
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if percentile == 0.50, sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            return (sorted[upper - 1] + sorted[upper]) / 2
        }
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[min(rank - 1, sorted.count - 1)]
    }
}

enum PrecisionEvaluationCLIError: Error, CustomStringConvertible {
    case missingArgument(String)
    case unsupportedArgument(String)
    case unsupportedFormat(String)

    var description: String {
        switch self {
        case let .missingArgument(argument):
            return "missing required argument \(argument)"
        case let .unsupportedArgument(argument):
            return "unsupported argument \(argument)"
        case let .unsupportedFormat(format):
            return "unsupported output format \(format)"
        }
    }
}

enum PrecisionEvaluationOutputFormat: String {
    case json
    case markdown
}

enum PrecisionEvaluationCLI {
    static func render(
        arguments: [String],
        readFile: (String) throws -> Data
    ) throws -> Data {
        var inputPath: String?
        var outputFormat: PrecisionEvaluationOutputFormat?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            guard index + 1 < arguments.count else {
                throw PrecisionEvaluationCLIError.missingArgument(argument)
            }
            let value = arguments[index + 1]
            switch argument {
            case "--input":
                inputPath = value
            case "--format":
                guard let format = PrecisionEvaluationOutputFormat(rawValue: value) else {
                    throw PrecisionEvaluationCLIError.unsupportedFormat(value)
                }
                outputFormat = format
            default:
                throw PrecisionEvaluationCLIError.unsupportedArgument(argument)
            }
            index += 2
        }
        guard let inputPath else {
            throw PrecisionEvaluationCLIError.missingArgument("--input")
        }
        guard let outputFormat else {
            throw PrecisionEvaluationCLIError.missingArgument("--format")
        }
        return try render(
            inputData: readFile(inputPath),
            format: outputFormat
        )
    }

    static func render(
        inputData: Data,
        format: PrecisionEvaluationOutputFormat
    ) throws -> Data {
        let input = try JSONDecoder().decode(
            PrecisionEvaluationInput.self,
            from: inputData
        )
        let report = PrecisionEvaluationReportBuilder.makeReport(from: input)
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes
            ]
            var data = try encoder.encode(report)
            data.append(0x0A)
            return data
        case .markdown:
            return Data(markdown(for: report).utf8)
        }
    }

    static func markdown(for report: PrecisionEvaluationReport) -> String {
        var lines = [
            "# Precision Swing Evaluation",
            "",
            "- Dataset hash: `\(report.datasetHash)`",
            "- Artifact version: `\(report.artifactVersion)`",
            "- Model version: `\(report.modelVersion)`",
            "- Held-out golfers: \(report.heldOutGolferCount)",
            "",
            "## Golfer counts by split and view",
            "",
            "| Split | View | Golfers |",
            "| --- | --- | ---: |"
        ]
        lines += report.golferCounts.map {
            "| \($0.split.rawValue) | \($0.view.rawValue) | \($0.golferCount) |"
        }
        lines += [
            "",
            "## Held-out view coverage",
            "",
            "| View | Golfers | Covered |",
            "| --- | ---: | --- |"
        ]
        lines += report.views.map {
            "| \($0.view.rawValue) | \($0.heldOutGolferCount) | \($0.hasHeldOutCoverage) |"
        }
        lines += [
            "",
            "## P1–P8 held-out rates",
            "",
            "| View | Stage | References | Hits | Hit rate | Unresolved rate | False-confirmation rate |",
            "| --- | --- | ---: | ---: | ---: | ---: | ---: |"
        ]
        lines += report.stageRates.map {
            "| \($0.view.rawValue) | \($0.stage) | \($0.referenceCount) | \($0.hitCount) | \(format($0.hitRate)) | \(format($0.unresolvedRate)) | \(format($0.falseConfirmationRate)) |"
        }
        lines += [
            "",
            "## Body landmarks",
            "",
            "| View | Landmark | Samples | Measured | Median error | P90 error | Miss rate |",
            "| --- | --- | ---: | ---: | ---: | ---: | ---: |"
        ]
        lines += report.bodyLandmarks.map {
            "| \($0.view.rawValue) | \($0.landmark) | \($0.sampleCount) | \($0.measuredCount) | \(format($0.medianError)) | \(format($0.p90Error)) | \(format($0.missRate)) |"
        }
        lines += [
            "",
            "Overall body-landmark median error: \(format(report.bodyLandmarkMedianError))",
            "",
            "## Clubhead",
            "",
            "| Scope | Visible frames | Hits | Hit rate | Median error | P90 error | Max accepted error | Gaps | Missing visible frames |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
            clubheadRow(scope: "all", summary: report.clubhead)
        ]
        lines += report.clubheadByView.map {
            clubheadRow(scope: $0.view.rawValue, summary: $0.summary)
        }
        lines += [
            "",
            "## Input rejection",
            "",
            "| Case | Expected rejected | Actual rejected | Passed | Reason |",
            "| --- | --- | --- | --- | --- |"
        ]
        lines += report.inputRejections.map {
            "| \($0.caseID) | \($0.expectedRejected) | \($0.actualRejected) | \($0.passed) | \($0.reason) |"
        }
        lines += [
            "",
            "## Runtime",
            "",
            "- Device: \(report.device.device)",
            "- OS: \(report.device.operatingSystem)",
            "- Elapsed seconds: \(format(report.device.elapsedSeconds))",
            "- Peak memory MB: \(format(report.device.peakMemoryMB))",
            "- Unsupported metrics have no measured values: \(report.unsupportedMetricsHaveNoMeasuredValues)",
            "",
            "Release passed: **\(report.releasePassed)**",
            "",
            "## Failed thresholds",
            ""
        ]
        if report.failedThresholds.isEmpty {
            lines.append("- None")
        } else {
            lines += report.failedThresholds.map { "- \($0)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func clubheadRow(
        scope: String,
        summary: PrecisionClubheadSummary
    ) -> String {
        "| \(scope) | \(summary.visibleFrameCount) | \(summary.hitCount) | \(format(summary.visibleFrameHitRate)) | \(format(summary.medianError)) | \(format(summary.p90Error)) | \(format(summary.maximumAcceptedError)) | \(summary.gapCount) | \(summary.missingVisibleFrameCount) |"
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(
            format: "%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

#if PRECISION_EVALUATION_CLI
@main
struct RunPrecisionEvaluationCommand {
    static func main() throws {
        let output = try PrecisionEvaluationCLI.render(
            arguments: CommandLine.arguments,
            readFile: { path in
                if path == "-" {
                    return FileHandle.standardInput.readDataToEndOfFile()
                }
                return try Data(contentsOf: URL(fileURLWithPath: path))
            }
        )
        FileHandle.standardOutput.write(output)
    }
}
#endif
