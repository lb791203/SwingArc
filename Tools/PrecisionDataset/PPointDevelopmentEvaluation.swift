import Foundation

enum PPointAutomaticStageStatus: String, Codable, Equatable {
    case confirmed
    case lowConfidence = "low-confidence"
    case unresolved
}

struct PPointAutomaticStageResult: Codable, Equatable {
    let code: PPointCode
    let sourceFrameIndex: Int?
    let status: PPointAutomaticStageStatus
}

struct PPointAutomaticClipResult: Codable, Equatable {
    let mediaSHA256: String
    let timelineSHA256: String
    let view: PPointGroundTruthView
    let elapsedSeconds: Double
    let stages: [PPointAutomaticStageResult]
}

struct PPointDevelopmentEvaluationPair: Equatable {
    let truth: PPointGroundTruthPackage
    let prediction: PPointAutomaticClipResult
}

enum PPointDevelopmentDecision: String, Codable, Equatable {
    case developmentOnly = "development-only"
}

struct PPointStageDevelopmentSummary: Codable, Equatable {
    let code: PPointCode
    let referenceCount: Int
    let hitCount: Int
    let unresolvedCount: Int
    let outOfToleranceCount: Int
    let hitRate: Double
    let unresolvedRate: Double
    let outOfToleranceRate: Double
    let medianAbsoluteFrameError: Double?
}

struct PPointViewDevelopmentSummary: Codable, Equatable {
    let view: PPointGroundTruthView
    let clipCount: Int
    let stages: [PPointStageDevelopmentSummary]
}

struct PPointStageDevelopmentResult: Codable, Equatable {
    let code: PPointCode
    let referenceFrame: Int
    let predictedFrame: Int?
    let status: PPointAutomaticStageStatus
    let signedFrameDelta: Int?
    let absoluteFrameError: Int?
    let withinTolerance: Bool
}

struct PPointClipDevelopmentResult: Codable, Equatable {
    let mediaSHA256: String
    let fileName: String
    let view: PPointGroundTruthView
    let elapsedSeconds: Double
    let stages: [PPointStageDevelopmentResult]
}

struct PPointDevelopmentEvaluationReport: Codable, Equatable {
    let schemaVersion: Int
    let decision: PPointDevelopmentDecision
    let maximumAcceptedFrameError: Int
    let clipCount: Int
    let totalElapsedSeconds: Double
    let views: [PPointViewDevelopmentSummary]
    let clips: [PPointClipDevelopmentResult]
}

enum PPointDevelopmentEvaluationError: Error, Equatable {
    case mediaIdentityMismatch(String)
    case missingViewCoverage(Set<PPointGroundTruthView>)
}

enum PPointDevelopmentCoveragePolicy {
    private static let requiredViews: Set<PPointGroundTruthView> = [
        .downTheLine,
        .faceOn
    ]

    static func missingViews(
        in truths: [PPointGroundTruthPackage]
    ) -> Set<PPointGroundTruthView> {
        requiredViews.subtracting(truths.map(\.view))
    }

    static func validate(
        _ truths: [PPointGroundTruthPackage]
    ) throws {
        let missing = missingViews(in: truths)
        guard missing.isEmpty else {
            throw PPointDevelopmentEvaluationError.missingViewCoverage(
                missing
            )
        }
    }
}

enum PPointDevelopmentEvaluationBuilder {
    static let maximumAcceptedFrameError = 2
    private static let orderedViews: [PPointGroundTruthView] = [
        .downTheLine,
        .faceOn
    ]

    static func makeReport(
        pairs: [PPointDevelopmentEvaluationPair]
    ) throws -> PPointDevelopmentEvaluationReport {
        for pair in pairs {
            guard pair.truth.media.sha256
                    == pair.prediction.mediaSHA256,
                  pair.truth.media.timelineSHA256
                    == pair.prediction.timelineSHA256,
                  pair.truth.view == pair.prediction.view else {
                throw PPointDevelopmentEvaluationError.mediaIdentityMismatch(
                    pair.truth.media.sha256
                )
            }
        }
        try PPointDevelopmentCoveragePolicy.validate(
            pairs.map(\.truth)
        )

        return PPointDevelopmentEvaluationReport(
            schemaVersion: 1,
            decision: .developmentOnly,
            maximumAcceptedFrameError: maximumAcceptedFrameError,
            clipCount: pairs.count,
            totalElapsedSeconds: pairs.reduce(0) {
                $0 + max(0, $1.prediction.elapsedSeconds)
            },
            views: orderedViews.map { view in
                let viewPairs = pairs.filter { $0.truth.view == view }
                return PPointViewDevelopmentSummary(
                    view: view,
                    clipCount: viewPairs.count,
                    stages: PPointCode.allCases.map { code in
                        summarize(code: code, pairs: viewPairs)
                    }
                )
            },
            clips: pairs.map(makeClipResult)
        )
    }

    private static func makeClipResult(
        _ pair: PPointDevelopmentEvaluationPair
    ) -> PPointClipDevelopmentResult {
        PPointClipDevelopmentResult(
            mediaSHA256: pair.truth.media.sha256,
            fileName: pair.truth.media.fileName,
            view: pair.truth.view,
            elapsedSeconds: pair.prediction.elapsedSeconds,
            stages: PPointCode.allCases.compactMap { code in
                guard let truth = pair.truth.stages.first(where: {
                    $0.code == code
                }) else {
                    return nil
                }
                let predictions = pair.prediction.stages.filter {
                    $0.code == code
                }
                let prediction = predictions.count == 1
                    ? predictions[0]
                    : PPointAutomaticStageResult(
                        code: code,
                        sourceFrameIndex: nil,
                        status: .unresolved
                    )
                let predictedFrame = prediction.status == .unresolved
                    ? nil
                    : prediction.sourceFrameIndex
                let delta = predictedFrame.map {
                    $0 - truth.sourceFrameIndex
                }
                let error = delta.map(abs)
                return PPointStageDevelopmentResult(
                    code: code,
                    referenceFrame: truth.sourceFrameIndex,
                    predictedFrame: predictedFrame,
                    status: prediction.status,
                    signedFrameDelta: delta,
                    absoluteFrameError: error,
                    withinTolerance: error.map {
                        $0 <= maximumAcceptedFrameError
                    } ?? false
                )
            }
        )
    }

    private static func summarize(
        code: PPointCode,
        pairs: [PPointDevelopmentEvaluationPair]
    ) -> PPointStageDevelopmentSummary {
        let records = pairs.compactMap { pair -> (Int, PPointAutomaticStageResult?)? in
            guard let truth = pair.truth.stages.first(where: {
                $0.code == code
            }) else {
                return nil
            }
            let predictions = pair.prediction.stages.filter {
                $0.code == code
            }
            return (
                truth.sourceFrameIndex,
                predictions.count == 1 ? predictions[0] : nil
            )
        }
        let errors = records.compactMap { reference, prediction -> Int? in
            guard let prediction,
                  prediction.status != .unresolved,
                  let frame = prediction.sourceFrameIndex else {
                return nil
            }
            return abs(frame - reference)
        }
        let hitCount = errors.filter {
            $0 <= maximumAcceptedFrameError
        }.count
        let unresolvedCount = records.count - errors.count
        let outOfToleranceCount = errors.filter {
            $0 > maximumAcceptedFrameError
        }.count
        return PPointStageDevelopmentSummary(
            code: code,
            referenceCount: records.count,
            hitCount: hitCount,
            unresolvedCount: unresolvedCount,
            outOfToleranceCount: outOfToleranceCount,
            hitRate: rate(hitCount, records.count),
            unresolvedRate: rate(unresolvedCount, records.count),
            outOfToleranceRate: rate(
                outOfToleranceCount,
                records.count
            ),
            medianAbsoluteFrameError: median(errors)
        )
    }

    private static func rate(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let ordered = values.sorted()
        let middle = ordered.count / 2
        if ordered.count.isMultiple(of: 2) {
            return Double(ordered[middle - 1] + ordered[middle]) / 2
        }
        return Double(ordered[middle])
    }
}

enum PPointDevelopmentEvaluationRenderer {
    static func markdown(
        _ report: PPointDevelopmentEvaluationReport
    ) -> String {
        var lines = [
            "# SwingArc P1–P8 开发精度报告",
            "",
            "> 此报告仅用于开发评估，不代表发布精度或训练完成。",
            "",
            "- 视频数：\(report.clipCount)",
            "- 合计分析耗时：\(String(format: "%.2f", report.totalElapsedSeconds)) 秒",
            "- 命中标准：人工帧 ±\(report.maximumAcceptedFrameError) 帧"
        ]
        for view in report.views {
            lines += [
                "",
                view.view == .downTheLine ? "## DTL" : "## Face-on",
                "",
                "- 视频数：\(view.clipCount)",
                "",
                "| P点 | 样本 | 命中率 | 未识别率 | 超差率 | 中位帧误差 |",
                "| --- | ---: | ---: | ---: | ---: | ---: |"
            ]
            lines += view.stages.map {
                "| \($0.code.rawValue) | \($0.referenceCount) | " +
                    "\(percent($0.hitRate)) | \(percent($0.unresolvedRate)) | " +
                    "\(percent($0.outOfToleranceRate)) | " +
                    "\(number($0.medianAbsoluteFrameError)) |"
            }
        }
        lines += [
            "",
            "## 每段视频明细",
            "",
            "| 视频 | 视角 | P点 | 人工帧 | 自动帧 | 偏移 | 状态 |",
            "| --- | --- | --- | ---: | ---: | ---: | --- |"
        ]
        for clip in report.clips {
            lines += clip.stages.map {
                "| \(clip.fileName) | \(viewName(clip.view)) | " +
                    "\($0.code.rawValue) | \($0.referenceFrame) | " +
                    "\(integer($0.predictedFrame)) | " +
                    "\(signedInteger($0.signedFrameDelta)) | " +
                    "\($0.status.rawValue) |"
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "—"
    }

    private static func integer(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    private static func signedInteger(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value > 0 ? "+\(value)" : String(value)
    }

    private static func viewName(_ view: PPointGroundTruthView) -> String {
        view == .downTheLine ? "DTL" : "Face-on"
    }
}
