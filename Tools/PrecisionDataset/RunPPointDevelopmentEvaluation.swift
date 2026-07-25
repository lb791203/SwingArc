import Foundation

@main
struct RunPPointDevelopmentEvaluation {
    static func main() throws {
        let options = try Options(arguments: CommandLine.arguments)
        let truths = try loadTruths(directory: options.exportsDirectory)
        guard !truths.isEmpty else {
            throw PPointDevelopmentRunnerError.noGroundTruthPackages
        }
        try PPointDevelopmentCoveragePolicy.validate(truths)
        let candidates = try inventoryVideos(
            directory: options.videosDirectory,
            truths: truths
        )
        var pairs: [PPointDevelopmentEvaluationPair] = []
        for truth in truths {
            let candidate = try PPointDevelopmentVideoMatcher.match(
                truth: truth.media,
                candidates: candidates
            )
            let prediction = try analyze(
                videoURL: candidate.url,
                truth: truth
            )
            pairs.append(.init(truth: truth, prediction: prediction))
        }

        let report = try PPointDevelopmentEvaluationBuilder.makeReport(
            pairs: pairs
        )
        try FileManager.default.createDirectory(
            at: options.outputDirectory,
            withIntermediateDirectories: true
        )
        let jsonURL = options.outputDirectory.appendingPathComponent(
            "p-point-development-report.json"
        )
        let markdownURL = options.outputDirectory.appendingPathComponent(
            "p-point-development-report.md"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var json = try encoder.encode(report)
        json.append(0x0A)
        try json.write(to: jsonURL, options: .atomic)
        try Data(
            PPointDevelopmentEvaluationRenderer.markdown(report).utf8
        ).write(to: markdownURL, options: .atomic)
        print(markdownURL.path)
        print(jsonURL.path)
    }

    private static func loadTruths(
        directory: URL
    ) throws -> [PPointGroundTruthPackage] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.pathExtension.lowercased() == "json"
                && $0.lastPathComponent.hasPrefix("p-points-")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map {
            try PPointGroundTruthCoding.makeDecoder().decode(
                PPointGroundTruthPackage.self,
                from: Data(contentsOf: $0)
            )
        }
    }

    private static func inventoryVideos(
        directory: URL,
        truths: [PPointGroundTruthPackage]
    ) throws -> [PPointDevelopmentVideoCandidate] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let accepted = Set(["mov", "mp4", "m4v"])
        let timelineKeys = Set(truths.map {
            "\($0.media.timelineSHA256):\($0.media.frameCount)"
        })
        var candidates: [PPointDevelopmentVideoCandidate] = []
        for case let url as URL in enumerator
            where accepted.contains(url.pathExtension.lowercased()) {
            guard let provider = try? ExactVideoFrameProvider.load(url: url) else {
                continue
            }
            let key = "\(provider.timelineSHA256):\(provider.frameCount)"
            guard timelineKeys.contains(key),
                  let sha256 = try? AnnotationStore.mediaSHA256(url: url) else {
                continue
            }
            candidates.append(
                PPointDevelopmentVideoCandidate(
                    url: url,
                    sha256: sha256,
                    timelineSHA256: provider.timelineSHA256,
                    frameCount: provider.frameCount
                )
            )
        }
        return candidates
    }

    private static func analyze(
        videoURL: URL,
        truth: PPointGroundTruthPackage
    ) throws -> PPointAutomaticClipResult {
        let analysisView: PracticeCameraView = truth.view == .downTheLine
            ? .downTheLine
            : .faceOn
        let gate = AnalysisRunGate()
        let runID = gate.begin()
        let outcome = SwingVideoAnalysisEngine().analyze(
            url: videoURL,
            view: analysisView,
            runID: runID,
            gate: gate,
            progress: { _ in }
        )
        guard case let .completed(output) = outcome else {
            throw PPointDevelopmentRunnerError.analysisFailed(
                videoURL.lastPathComponent
            )
        }
        let stages = zip(PPointCode.allCases, SwingStage.pStages).map {
            code,
            stage -> PPointAutomaticStageResult in
            let detections = output.result.detections.filter {
                $0.stage == stage
            }
            guard detections.count == 1 else {
                return PPointAutomaticStageResult(
                    code: code,
                    sourceFrameIndex: nil,
                    status: .unresolved
                )
            }
            let detection = detections[0]
            let status: PPointAutomaticStageStatus
            switch detection.status {
            case .confirmed:
                status = .confirmed
            case .lowConfidence:
                status = .lowConfidence
            case .unresolved:
                status = .unresolved
            }
            return PPointAutomaticStageResult(
                code: code,
                sourceFrameIndex: detection.sourceFrameIndex,
                status: status
            )
        }
        return PPointAutomaticClipResult(
            mediaSHA256: truth.media.sha256,
            timelineSHA256: truth.media.timelineSHA256,
            view: output.view == .downTheLine ? .downTheLine : .faceOn,
            elapsedSeconds: output.elapsedSeconds,
            stages: stages
        )
    }
}

private struct Options {
    let exportsDirectory: URL
    let videosDirectory: URL
    let outputDirectory: URL

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 1
        while index + 1 < arguments.count {
            values[arguments[index]] = arguments[index + 1]
            index += 2
        }
        guard let exports = values["--exports"],
              let videos = values["--videos"],
              let output = values["--output"] else {
            throw OptionsError.usage
        }
        exportsDirectory = URL(
            fileURLWithPath: exports,
            isDirectory: true
        )
        videosDirectory = URL(
            fileURLWithPath: videos,
            isDirectory: true
        )
        outputDirectory = URL(
            fileURLWithPath: output,
            isDirectory: true
        )
    }
}

private enum OptionsError: Error, CustomStringConvertible {
    case usage

    var description: String {
        "usage: run-p-point-development-evaluation " +
            "--exports <directory> --videos <directory> --output <directory>"
    }
}
