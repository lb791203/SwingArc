import CryptoKit
import Foundation

enum AnnotationStoreError: Error, Equatable {
    case unreadableMedia
    case mediaIdentityMismatch
    case invalidPackage
    case writeFailed
}

struct AnnotationStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent(
                "SwingArcAnnotations",
                isDirectory: true
            )
    }

    static func mediaSHA256(url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw AnnotationStoreError.unreadableMedia
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw AnnotationStoreError.unreadableMedia
            }
            if count == 0 { break }
            hasher.update(data: Data(buffer[0..<count]))
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func packageURL(mediaSHA256: String) -> URL {
        rootDirectory.appendingPathComponent(
            "\(mediaSHA256).annotation.json"
        )
    }

    func load(mediaSHA256: String) throws -> AnnotationPackage? {
        let url = packageURL(mediaSHA256: mediaSHA256)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let package: AnnotationPackage
        do {
            package = try AnnotationCoding.makeDecoder().decode(
                AnnotationPackage.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw AnnotationStoreError.invalidPackage
        }
        guard package.media.sha256 == mediaSHA256 else {
            throw AnnotationStoreError.mediaIdentityMismatch
        }
        return package
    }

    func save(
        _ package: AnnotationPackage,
        expectedMediaSHA256: String? = nil
    ) throws {
        if let expectedMediaSHA256,
           expectedMediaSHA256 != package.media.sha256 {
            throw AnnotationStoreError.mediaIdentityMismatch
        }
        do {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true
            )
            let data = try AnnotationCoding.makeEncoder().encode(package)
            try data.write(
                to: packageURL(mediaSHA256: package.media.sha256),
                options: .atomic
            )
        } catch {
            throw AnnotationStoreError.writeFailed
        }
    }
}
