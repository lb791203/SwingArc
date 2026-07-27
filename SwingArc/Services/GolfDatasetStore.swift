import Foundation

public enum GolfDatasetStoreError: Error, Equatable, CustomStringConvertible {
    case predictionAlreadyExists(String)
    case revisionConflict(String)
    case anchorAlreadyExists(String)
    case anchorNotFound(String)
    case anchorClipMismatch(expected: String, got: String)
    case invalidID(String)
    case pathTraversal

    public var description: String {
        switch self {
        case .predictionAlreadyExists(let id):
            return "Prediction run '\(id)' already exists and is immutable"
        case .revisionConflict(let id):
            return "Revision '\(id)' already exists with different content"
        case .anchorAlreadyExists(let id):
            return "Subject anchor '\(id)' already exists and is immutable"
        case .anchorNotFound(let id):
            return "Subject anchor '\(id)' not found"
        case .anchorClipMismatch(let expected, let got):
            return "Subject anchor clipID '\(got)' does not match directory clipID '\(expected)'"
        case .invalidID(let msg):
            return "Invalid ID or payload: \(msg)"
        case .pathTraversal:
            return "ID contains path traversal characters"
        }
    }
}

public struct GolfDatasetSnapshot: Equatable, Sendable {
    public let registry: GolferRegistry?
    public let clips: [GolfClipIdentity]
    public let predictions: [GolfPredictionRun]
    public let revisions: [GolfAnnotationRevision]

    public init(
        registry: GolferRegistry?,
        clips: [GolfClipIdentity],
        predictions: [GolfPredictionRun],
        revisions: [GolfAnnotationRevision]
    ) {
        self.registry = registry
        self.clips = clips
        self.predictions = predictions
        self.revisions = revisions
    }
}

public final class GolfDatasetStore: @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    // MARK: - Locking

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Encoder / Decoder

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Path helpers

    private func validateID(_ id: String) throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == id,
              !id.contains("/"), !id.contains("..") else {
            throw GolfDatasetStoreError.pathTraversal
        }
    }

    private func registryURL() -> URL {
        rootDirectory.appendingPathComponent("golfer-registry.json")
    }

    private func clipDirectory(clipID: String) -> URL {
        rootDirectory.appendingPathComponent("clips").appendingPathComponent(clipID)
    }

    private func clipJSONURL(clipID: String) -> URL {
        clipDirectory(clipID: clipID).appendingPathComponent("clip.json")
    }

    private func predictionJSONURL(clipID: String, predictionRunID: String) -> URL {
        clipDirectory(clipID: clipID)
            .appendingPathComponent("predictions")
            .appendingPathComponent("\(predictionRunID).json")
    }

    private func revisionJSONURL(clipID: String, revisionID: String) -> URL {
        clipDirectory(clipID: clipID)
            .appendingPathComponent("annotations")
            .appendingPathComponent("\(revisionID).json")
    }

    private func anchorJSONURL(clipID: String, anchorID: String) -> URL {
        clipDirectory(clipID: clipID)
            .appendingPathComponent("anchors")
            .appendingPathComponent("\(anchorID).json")
    }

    // MARK: - Atomic write

    private func cleanupTmp(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    private func atomicWrite<T: Encodable>(_ value: T, to destination: URL, allowOverwrite: Bool) throws {
        let dir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmpURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json")
        let data = try Self.encoder().encode(value)

        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            cleanupTmp(tmpURL)
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            guard allowOverwrite else {
                cleanupTmp(tmpURL)
                return
            }
            do {
                let existing = try Data(contentsOf: destination)
                if existing == data {
                    cleanupTmp(tmpURL)
                    return
                }
                _ = try fileManager.replaceItemAt(destination, withItemAt: tmpURL)
            } catch {
                cleanupTmp(tmpURL)
                throw error
            }
        } else {
            do {
                try fileManager.moveItem(at: tmpURL, to: destination)
            } catch {
                cleanupTmp(tmpURL)
                throw error
            }
        }
    }

    private func atomicWriteImmutable<T: Encodable>(_ value: T, to destination: URL) throws {
        let dir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmpURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json")
        let data = try Self.encoder().encode(value)

        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            cleanupTmp(tmpURL)
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            cleanupTmp(tmpURL)
            throw GolfDatasetStoreError.predictionAlreadyExists(
                destination.deletingPathExtension().lastPathComponent
            )
        } else {
            do {
                try fileManager.moveItem(at: tmpURL, to: destination)
            } catch {
                cleanupTmp(tmpURL)
                throw error
            }
        }
    }

    // MARK: - Registry

    public func saveRegistry(_ registry: GolferRegistry) throws {
        try withLock {
            try atomicWrite(registry, to: registryURL(), allowOverwrite: true)
        }
    }

    public func loadRegistry() throws -> GolferRegistry {
        let data = try Data(contentsOf: registryURL())
        return try Self.decoder().decode(GolferRegistry.self, from: data)
    }

    // MARK: - Clip

    public func saveClip(_ clip: GolfClipIdentity) throws {
        try validateID(clip.clipID)
        try withLock {
            try atomicWrite(clip, to: clipJSONURL(clipID: clip.clipID), allowOverwrite: true)
        }
    }

    public func loadClip(clipID: String) throws -> GolfClipIdentity {
        try validateID(clipID)
        let data = try Data(contentsOf: clipJSONURL(clipID: clipID))
        return try Self.decoder().decode(GolfClipIdentity.self, from: data)
    }

    /// Narrow read APIs deliberately avoid decoding immutable prediction payloads.
    /// Annotation clients use these paths for blind held-out review.
    public func loadClips() throws -> [GolfClipIdentity] {
        let clipsDir = rootDirectory.appendingPathComponent("clips")
        guard fileManager.fileExists(atPath: clipsDir.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .compactMap { url in
                try validateID(url.lastPathComponent)
                let clipJSON = url.appendingPathComponent("clip.json")
                guard fileManager.fileExists(atPath: clipJSON.path) else { return nil }
                return try Self.decoder().decode(GolfClipIdentity.self, from: Data(contentsOf: clipJSON))
            }
            .sorted { $0.clipID < $1.clipID }
    }

    public func loadRevisions(clipID: String) throws -> [GolfAnnotationRevision] {
        try validateID(clipID)
        let directory = clipDirectory(clipID: clipID).appendingPathComponent("annotations")
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }
            .map { try Self.decoder().decode(GolfAnnotationRevision.self, from: Data(contentsOf: $0)) }
    }

    /// Lists only run identifiers. It never decodes a prediction JSON document.
    public func listPredictionRunIDs(clipID: String) throws -> [String] {
        try validateID(clipID)
        let directory = clipDirectory(clipID: clipID).appendingPathComponent("predictions")
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    // MARK: - Prediction

    public func appendPrediction(_ prediction: GolfPredictionRun) throws {
        try validateID(prediction.predictionRunID)
        try validateID(prediction.clipID)
        try withLock {
            let url = predictionJSONURL(clipID: prediction.clipID, predictionRunID: prediction.predictionRunID)
            if fileManager.fileExists(atPath: url.path) {
                throw GolfDatasetStoreError.predictionAlreadyExists(prediction.predictionRunID)
            }
            try atomicWriteImmutable(prediction, to: url)
        }
    }

    public func loadPrediction(clipID: String, predictionRunID: String) throws -> GolfPredictionRun {
        try validateID(clipID)
        try validateID(predictionRunID)
        let data = try Data(contentsOf: predictionJSONURL(clipID: clipID, predictionRunID: predictionRunID))
        return try Self.decoder().decode(GolfPredictionRun.self, from: data)
    }

    // MARK: - Revision

    public func saveRevision(_ revision: GolfAnnotationRevision) throws {
        try validateID(revision.revisionID)
        try validateID(revision.clipID)
        try withLock {
            let url = revisionJSONURL(clipID: revision.clipID, revisionID: revision.revisionID)

            if fileManager.fileExists(atPath: url.path) {
                let existing = try Data(contentsOf: url)
                let newData = try Self.encoder().encode(revision)
                guard existing == newData else {
                    throw GolfDatasetStoreError.revisionConflict(revision.revisionID)
                }
                return
            }
            try atomicWriteImmutable(revision, to: url)
        }
    }

    public func loadRevision(clipID: String, revisionID: String) throws -> GolfAnnotationRevision {
        try validateID(clipID)
        try validateID(revisionID)
        let data = try Data(contentsOf: revisionJSONURL(clipID: clipID, revisionID: revisionID))
        return try Self.decoder().decode(GolfAnnotationRevision.self, from: data)
    }

    // MARK: - Snapshot

    public func loadSnapshot() throws -> GolfDatasetSnapshot {
        let registryURL = registryURL()
        let registry: GolferRegistry?
        if fileManager.fileExists(atPath: registryURL.path) {
            let data = try Data(contentsOf: registryURL)
            registry = try Self.decoder().decode(GolferRegistry.self, from: data)
        } else {
            registry = nil
        }

        let clipsDir = rootDirectory.appendingPathComponent("clips")
        let clipIDs: [String]
        if fileManager.fileExists(atPath: clipsDir.path) {
            clipIDs = (try fileManager.contentsOfDirectory(
                at: clipsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).compactMap { $0.lastPathComponent })
        } else {
            clipIDs = []
        }

        var clips: [GolfClipIdentity] = []
        var predictions: [GolfPredictionRun] = []
        var revisions: [GolfAnnotationRevision] = []

        for clipID in clipIDs.sorted() {
            let clipJSON = clipsDir.appendingPathComponent(clipID).appendingPathComponent("clip.json")
            if fileManager.fileExists(atPath: clipJSON.path) {
                let data = try Data(contentsOf: clipJSON)
                clips.append(try Self.decoder().decode(GolfClipIdentity.self, from: data))
            }

            let predDir = clipsDir.appendingPathComponent(clipID).appendingPathComponent("predictions")
            if fileManager.fileExists(atPath: predDir.path) {
                let predFiles = (try fileManager.contentsOfDirectory(
                    at: predDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ))
                for predURL in predFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let data = try Data(contentsOf: predURL)
                    predictions.append(try Self.decoder().decode(GolfPredictionRun.self, from: data))
                }
            }

            let revDir = clipsDir.appendingPathComponent(clipID).appendingPathComponent("annotations")
            if fileManager.fileExists(atPath: revDir.path) {
                let revFiles = (try fileManager.contentsOfDirectory(
                    at: revDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ))
                for revURL in revFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let data = try Data(contentsOf: revURL)
                    revisions.append(try Self.decoder().decode(GolfAnnotationRevision.self, from: data))
                }
            }
        }

        return GolfDatasetSnapshot(
            registry: registry,
            clips: clips.sorted { $0.clipID < $1.clipID },
            predictions: predictions.sorted { $0.predictionRunID < $1.predictionRunID },
            revisions: revisions.sorted { $0.revisionID < $1.revisionID }
        )
    }

    // MARK: - Subject Anchors

    public func appendSubjectAnchor(_ anchor: GolfSubjectAnchorDecision, clipID: String) throws {
        try withLock {
            try validateID(clipID)
            try validateID(anchor.anchorID)
            guard anchor.clipID == clipID else {
                throw GolfDatasetStoreError.anchorClipMismatch(expected: clipID, got: anchor.clipID)
            }
            guard anchor.schemaVersion == GolfSubjectAnchorDecision.currentSchemaVersion else {
                throw GolfDatasetStoreError.invalidID("schemaVersion mismatch: \(anchor.schemaVersion)")
            }
            let clip = try loadClip(clipID: clipID)
            guard anchor.mediaSHA256 == clip.media.sha256 &&
                    anchor.timelineSHA256 == clip.media.timelineSHA256 else {
                throw GolfDatasetStoreError.invalidID(
                    "anchor media/timeline SHA mismatch with clip"
                )
            }
            let destination = anchorJSONURL(clipID: clipID, anchorID: anchor.anchorID)
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw GolfDatasetStoreError.anchorAlreadyExists(anchor.anchorID)
            }
            try atomicWrite(anchor, to: destination, allowOverwrite: false)
        }
    }

    public func loadSubjectAnchors(clipID: String) throws -> [GolfSubjectAnchorDecision] {
        try withLock {
            try validateID(clipID)
            let dir = clipDirectory(clipID: clipID).appendingPathComponent("anchors")
            guard fileManager.fileExists(atPath: dir.path) else { return [] }
            let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "json" }
            var result: [GolfSubjectAnchorDecision] = []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let data = try Data(contentsOf: file)
                result.append(try Self.decoder().decode(GolfSubjectAnchorDecision.self, from: data))
            }
            return result.sorted {
                if $0.sourceFrameIndex != $1.sourceFrameIndex {
                    return $0.sourceFrameIndex < $1.sourceFrameIndex
                }
                return $0.anchorID < $1.anchorID
            }
        }
    }

    public func loadSubjectAnchor(clipID: String, anchorID: String) throws -> GolfSubjectAnchorDecision {
        try withLock {
            try validateID(clipID)
            try validateID(anchorID)
            let destination = anchorJSONURL(clipID: clipID, anchorID: anchorID)
            guard fileManager.fileExists(atPath: destination.path) else {
                throw GolfDatasetStoreError.anchorNotFound(anchorID)
            }
            let data = try Data(contentsOf: destination)
            return try Self.decoder().decode(GolfSubjectAnchorDecision.self, from: data)
        }
    }
}
