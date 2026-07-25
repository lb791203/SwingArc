import Foundation

@main
struct PPointGroundTruthExportSmoke {
    static func main() throws {
        let markers = zip(PPointCode.allCases, SwingStage.pStages)
            .enumerated()
            .map { offset, item in
                KeyframeMarker(
                    time: Double(offset + 1) / 30,
                    stage: item.1,
                    source: .manual,
                    sourceFrameIndex: (offset + 1) * 10
                )
            }
            .reversed()

        let package = try PPointGroundTruthPackageBuilder.make(
            media: PPointGroundTruthMedia(
                fileName: "IMG_5001.MOV",
                sha256: "media-sha",
                timelineSHA256: "timeline-sha",
                frameCount: 240,
                width: 1920,
                height: 1080
            ),
            view: .downTheLine,
            markers: Array(markers),
            createdAt: Date(timeIntervalSince1970: 100)
        )

        precondition(package.schemaVersion == 1)
        precondition(package.stageSystem == "p-system-v1")
        precondition(package.reviewLevel == .singlePassDevelopment)
        precondition(package.view == .downTheLine)
        precondition(package.stages.map(\.code) == PPointCode.allCases)
        precondition(
            package.stages.map(\.sourceFrameIndex)
                == [10, 20, 30, 40, 50, 60, 70, 80]
        )

        let encoded = try PPointGroundTruthCoding.makeEncoder().encode(package)
        let restored = try PPointGroundTruthCoding.makeDecoder().decode(
            PPointGroundTruthPackage.self,
            from: encoded
        )
        precondition(restored == package)
        let json = String(decoding: encoded, as: UTF8.self)
        precondition(json.contains("\"view\" : \"dtl\""))
        precondition(!json.contains("automatic"))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let receipt = try PPointGroundTruthExportService.write(
            package: package,
            destinationDirectory: directory
        )
        precondition(receipt.url.pathExtension == "json")
        precondition(receipt.url.lastPathComponent.contains("dtl"))
        precondition(receipt.url.lastPathComponent.contains("media-sha"))
        precondition(!receipt.includesRawVideo)
        let exported = try PPointGroundTruthCoding.makeDecoder().decode(
            PPointGroundTruthPackage.self,
            from: Data(contentsOf: receipt.url)
        )
        precondition(exported == package)

        expectFailure(.missingManualStages([.p4])) {
            var incomplete = Array(markers)
            incomplete.removeAll { $0.stage == SwingStage.top.rawValue }
            _ = try PPointGroundTruthPackageBuilder.make(
                media: package.media,
                view: .faceOn,
                markers: incomplete,
                createdAt: package.createdAt
            )
        }

        expectFailure(.missingExactSourceFrames([.p4])) {
            var inexact = Array(markers)
            inexact.removeAll { $0.stage == SwingStage.top.rawValue }
            inexact.append(
                KeyframeMarker(
                    time: 1.2,
                    stage: .top,
                    source: .manual,
                    sourceFrameIndex: nil
                )
            )
            _ = try PPointGroundTruthPackageBuilder.make(
                media: package.media,
                view: .downTheLine,
                markers: inexact,
                createdAt: package.createdAt
            )
        }

        expectFailure(.nonIncreasingFrames) {
            var unordered = Array(markers)
            unordered.removeAll {
                $0.stage == SwingStage.leadArmParallelDownswing.rawValue
            }
            unordered.append(
                KeyframeMarker(
                    time: 0.5,
                    stage: .leadArmParallelDownswing,
                    source: .manual,
                    sourceFrameIndex: 35
                )
            )
            _ = try PPointGroundTruthPackageBuilder.make(
                media: package.media,
                view: .downTheLine,
                markers: unordered,
                createdAt: package.createdAt
            )
        }

        expectFailure(.missingManualStages([.p2])) {
            var automatic = Array(markers)
            automatic.removeAll { $0.stage == SwingStage.takeaway.rawValue }
            automatic.append(
                KeyframeMarker(
                    time: 0.2,
                    stage: .takeaway,
                    source: .automatic,
                    sourceFrameIndex: 20
                )
            )
            _ = try PPointGroundTruthPackageBuilder.make(
                media: package.media,
                view: .downTheLine,
                markers: automatic,
                createdAt: package.createdAt
            )
        }
    }

    private static func expectFailure(
        _ expected: PPointGroundTruthExportError,
        _ operation: () throws -> Void
    ) {
        do {
            try operation()
            preconditionFailure("Expected \(expected)")
        } catch let error as PPointGroundTruthExportError {
            precondition(error == expected)
        } catch {
            preconditionFailure("Unexpected error \(error)")
        }
    }
}
