import CryptoKit
import Foundation

enum AnnotationExportError: Error, Equatable {
    case validationFailed([AnnotationValidationError])
    case writeFailed
}

struct AnnotationExportReceipt: Equatable {
    let url: URL
    let sha256: String
    let includesRawVideo: Bool
}

enum AnnotationExportService {
    static func freezeAndExport(
        package: inout AnnotationPackage,
        destinationDirectory: URL,
        now: Date
    ) throws -> AnnotationExportReceipt {
        var candidate = package
        candidate.frozenAt = now
        let errors = AnnotationPackageValidator.validate(candidate)
        guard errors.isEmpty else {
            throw AnnotationExportError.validationFailed(errors)
        }

        guard let data = try? AnnotationCoding.makeEncoder().encode(
            candidate
        ) else {
            throw AnnotationExportError.writeFailed
        }
        do {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            let url = destinationDirectory.appendingPathComponent(
                "\(candidate.metadata.clipID)-annotation-v" +
                    "\(candidate.schemaVersion).json"
            )
            try data.write(to: url, options: .atomic)
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            package = candidate
            return .init(
                url: url,
                sha256: digest,
                includesRawVideo: false
            )
        } catch {
            throw AnnotationExportError.writeFailed
        }
    }
}
