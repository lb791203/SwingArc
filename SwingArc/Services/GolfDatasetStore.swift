import Foundation

public enum GolfDatasetStoreError: Error, Equatable, CustomStringConvertible {
    case predictionAlreadyExists(String)
    case revisionConflict(String)
    case pathTraversal

    public var description: String {
        switch self {
        case .predictionAlreadyExists(let id):
            return "Prediction run '\(id)' already exists and is immutable"
        case .revisionConflict(let id):
            return "Revision '\(id)' already exists with different content"
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

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
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
        guard !id.contains("/") && !id.contains("..") else {
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

    // MARK: - Atomic write

    private func atomicWrite<T: Encodable>(_ value: T, to destination: URL, allowOverwrite: Bool) throws {
        let dir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmpURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json")
        let data = try Self.encoder().encode(value)

        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: tmpURL)
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            guard allowOverwrite else {
                try? fileManager.removeItem(at: tmpURL)
                return
            }
            do {
                let existing = try Data(contentsOf: destination)
                if existing == data {
                    try? fileManager.removeItem(at: tmpURL)
                    return
                }
                _ = try fileManager.replaceItemAt(destination, withItemAt: tmpURL)
            } catch {
                try? fileManager.removeItem(at: tmpURL)
                throw error
            }
        } else {
            do {
                try fileManager.moveItem(at: tmpURL, to: destination)
            } catch {
                try? fileManager.removeItem(at: tmpURL)
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
            try? fileManager.removeItem(at: tmpURL)
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: tmpURL)
            throw NSError(domain: "GolfDatasetStore", code: 1, userInfo: nil)
        } else {
            do {
                try fileManager.moveItem(at: tmpURL, to: destination)
            } catch {
                try? fileManager.removeItem(at: tmpURL)
                throw error
            }
        }
    }

    // MARK: - Registry

    public func saveRegistry(_ registry: GolferRegistry) throws {
        try atomicWrite(registry, to: registryURL(), allowOverwrite: true)
    }

    public func loadRegistry() throws -> GolferRegistry {
        let data = try Data(contentsOf: registryURL())
        return try Self.decoder().decode(GolferRegistry.self, from: data)
    }

    // MARK: - Clip

    public func saveClip(_ clip: GolfClipIdentity) throws {
        try validateID(clip.clipID)
        try atomicWrite(clip, to: clipJSONURL(clipID: clip.clipID), allowOverwrite: true)
    }

    public func loadClip(clipID: String) throws -> GolfClipIdentity {
        try validateID(clipID)
        let data = try Data(contentsOf: clipJSONURL(clipID: clipID))
        return try Self.decoder().decode(GolfClipIdentity.self, from: data)
    }

    // MARK: - Prediction

    public func appendPrediction(_ prediction: GolfPredictionRun) throws {
        try validateID(prediction.predictionRunID)
        try validateID(prediction.clipID)
        let url = predictionJSONURL(clipID: prediction.clipID, predictionRunID: prediction.predictionRunID)

        if fileManager.fileExists(atPath: url.path) {
            throw GolfDatasetStoreError.predictionAlreadyExists(prediction.predictionRunID)
        }

        try atomicWriteImmutable(prediction, to: url)
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
        let url = revisionJSONURL(clipID: revision.clipID, revisionID: revision.revisionID)

        if fileManager.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            let newData = try Self.encoder().encode(revision)
            guard existing == newData else {
                throw GolfDatasetStoreError.revisionConflict(revision.revisionID)
            }
            return  // idempotent
        }

        try atomicWriteImmutable(revision, to: url)
    }

    public func loadRevision(clipID: String, revisionID: String) throws -> GolfAnnotationRevision {
        try validateID(clipID)
        try validateID(revisionID)
        let data = try Data(contentsOf: revisionJSONURL(clipID: clipID, revisionID: revisionID))
        return try Self.decoder().decode(GolfAnnotationRevision.self, from: data)
    }

    // MARK: - Snapshot

    public func loadSnapshot() throws -> GolfDatasetSnapshot {
        // Registry
        let registryURL = registryURL()
        let registry: GolferRegistry?
        if fileManager.fileExists(atPath: registryURL.path) {
            let data = try Data(contentsOf: registryURL)
            registry = try Self.decoder().decode(GolferRegistry.self, from: data)
        } else {
            registry = nil
        }

        // Clips
        let clipsDir = rootDirectory.appendingPathComponent("clips")
        let clipIDs: [String]
        if fileManager.fileExists(atPath: clipsDir.path) {
            clipIDs = (try? fileManager.contentsOfDirectory(
                at: clipsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).compactMap { $0.lastPathComponent }) ?? []
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

            // Predictions
            let predDir = clipsDir.appendingPathComponent(clipID).appendingPathComponent("predictions")
            if fileManager.fileExists(atPath: predDir.path) {
                let predFiles = (try? fileManager.contentsOfDirectory(
                    at: predDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                for predURL in predFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let data = try Data(contentsOf: predURL)
                    predictions.append(try Self.decoder().decode(GolfPredictionRun.self, from: data))
                }
            }

            // Revisions
            let revDir = clipsDir.appendingPathComponent(clipID).appendingPathComponent("annotations")
            if fileManager.fileExists(atPath: revDir.path) {
                let revFiles = (try? fileManager.contentsOfDirectory(
                    at: revDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
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
}
