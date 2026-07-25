import Foundation

enum PPointGroundTruthView: String, Codable, Equatable {
    case downTheLine = "dtl"
    case faceOn = "face-on"
}

enum PPointGroundTruthReviewLevel: String, Codable, Equatable {
    case singlePassDevelopment = "single-pass-development"
}

struct PPointGroundTruthMedia: Codable, Equatable {
    let fileName: String
    let sha256: String
    let timelineSHA256: String
    let frameCount: Int
    let width: Int
    let height: Int
}

struct PPointGroundTruthStage: Codable, Equatable {
    let code: PPointCode
    let sourceFrameIndex: Int
    let time: Double
}

struct PPointGroundTruthPackage: Codable, Equatable {
    let schemaVersion: Int
    let stageSystem: String
    let reviewLevel: PPointGroundTruthReviewLevel
    let media: PPointGroundTruthMedia
    let view: PPointGroundTruthView
    let createdAt: Date
    let stages: [PPointGroundTruthStage]
}

enum PPointGroundTruthExportError: Error, Equatable {
    case missingManualStages([PPointCode])
    case missingExactSourceFrames([PPointCode])
    case frameOutOfRange([PPointCode])
    case nonIncreasingFrames
    case unreadableVideo
    case writeFailed
}

enum PPointGroundTruthPackageBuilder {
    static func make(
        media: PPointGroundTruthMedia,
        view: PPointGroundTruthView,
        markers: [KeyframeMarker],
        createdAt: Date
    ) throws -> PPointGroundTruthPackage {
        let manualByStage = Dictionary(
            markers
                .filter { $0.source == .manual }
                .map { ($0.stage, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let missingManual = zip(PPointCode.allCases, SwingStage.pStages)
            .compactMap { code, stage in
                manualByStage[stage.rawValue] == nil ? code : nil
            }
        guard missingManual.isEmpty else {
            throw PPointGroundTruthExportError.missingManualStages(
                missingManual
            )
        }

        let missingExactFrames = zip(
            PPointCode.allCases,
            SwingStage.pStages
        ).compactMap { code, stage in
            manualByStage[stage.rawValue]?.sourceFrameIndex == nil
                ? code
                : nil
        }
        guard missingExactFrames.isEmpty else {
            throw PPointGroundTruthExportError.missingExactSourceFrames(
                missingExactFrames
            )
        }

        let stages = zip(PPointCode.allCases, SwingStage.pStages).map {
            code,
            stage -> PPointGroundTruthStage in
            let marker = manualByStage[stage.rawValue]!
            return PPointGroundTruthStage(
                code: code,
                sourceFrameIndex: marker.sourceFrameIndex!,
                time: marker.time
            )
        }
        let outOfRange = stages.compactMap {
            (0..<media.frameCount).contains($0.sourceFrameIndex)
                ? nil
                : $0.code
        }
        guard outOfRange.isEmpty else {
            throw PPointGroundTruthExportError.frameOutOfRange(outOfRange)
        }
        let frames = stages.map(\.sourceFrameIndex)
        guard zip(frames, frames.dropFirst()).allSatisfy(<) else {
            throw PPointGroundTruthExportError.nonIncreasingFrames
        }

        return PPointGroundTruthPackage(
            schemaVersion: 1,
            stageSystem: "p-system-v1",
            reviewLevel: .singlePassDevelopment,
            media: media,
            view: view,
            createdAt: createdAt,
            stages: stages
        )
    }
}

enum PPointGroundTruthCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
