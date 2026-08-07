import Foundation

enum MediaExportKind: CaseIterable {
    case frame
    case annotatedVideo

    var fileExtension: String {
        switch self {
        case .frame: return "jpg"
        case .annotatedVideo: return "mov"
        }
    }
}

#if canImport(UIKit)
import AVFoundation
import Photos
import SwiftUI
import UIKit

enum MediaExportError: LocalizedError {
    case missingVideoTrack
    case cannotCreateFrame
    case cannotCreateExportSession
    case exportFailed
    case photoPermissionDenied
    case cannotReadImage

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack: return "视频中没有可导出的画面轨道。"
        case .cannotCreateFrame: return "无法生成当前视频帧。"
        case .cannotCreateExportSession: return "无法创建视频导出任务。"
        case .exportFailed: return "视频导出失败。"
        case .photoPermissionDenied: return "请允许 SwingArc 添加照片与视频到相册。"
        case .cannotReadImage: return "无法读取待保存的图片。"
        }
    }
}

enum MediaExportService {
    static func export(
        kind: MediaExportKind,
        asset: AVAsset,
        time: Double,
        drawings: [DrawingElement]
    ) async throws -> URL {
        switch kind {
        case .frame:
            return try await exportFrame(asset: asset, time: time, drawings: drawings)
        case .annotatedVideo:
            return try await exportAnnotatedVideo(asset: asset, drawings: drawings)
        }
    }

    static func saveToPhotoLibrary(_ url: URL, kind: MediaExportKind) async throws {
        let authorization = await requestAddOnlyAuthorization()
        guard authorization == .authorized || authorization == .limited else {
            throw MediaExportError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                switch kind {
                case .frame:
                    guard let image = UIImage(contentsOfFile: url.path) else { return }
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                case .annotatedVideo:
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? MediaExportError.exportFailed)
                }
            }
        }
    }

    private static func exportFrame(
        asset: AVAsset,
        time: Double,
        drawings: [DrawingElement]
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero

                do {
                    let image = try generator.copyCGImage(
                        at: CMTime(seconds: max(0, time), preferredTimescale: 600),
                        actualTime: nil
                    )
                    let rendered = render(drawings: drawings, over: image)
                    guard let jpeg = UIImage(cgImage: rendered).jpegData(compressionQuality: 0.95) else {
                        throw MediaExportError.cannotCreateFrame
                    }
                    let destination = temporaryURL(for: .frame)
                    try jpeg.write(to: destination, options: .atomic)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func exportAnnotatedVideo(asset: AVAsset, drawings: [DrawingElement]) async throws -> URL {
        guard asset.tracks(withMediaType: .video).first != nil else {
            throw MediaExportError.missingVideoTrack
        }

        let composition = AVMutableVideoComposition(propertiesOf: asset)
        let renderSize = composition.renderSize
        guard renderSize.width > 0, renderSize.height > 0 else {
            throw MediaExportError.missingVideoTrack
        }

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let drawingLayer = CALayer()
        drawingLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(drawingLayer)

        let duration = max(asset.duration.seconds, 0.01)
        drawings.forEach { drawing in
            let layer = shapeLayer(for: drawing, canvasSize: renderSize)
            if drawing.isKeyframeSpecific {
                layer.opacity = 0
                let threshold = 0.15
                let start = max(0, drawing.videoTime - threshold) / duration
                let end = min(duration, drawing.videoTime + threshold) / duration
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [0, 1, 1, 0]
                animation.keyTimes = [0, NSNumber(value: start), NSNumber(value: end), 1]
                animation.duration = duration
                animation.beginTime = AVCoreAnimationBeginTimeAtZero
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: "visibility")
            }
            drawingLayer.addSublayer(layer)
        }

        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaExportError.cannotCreateExportSession
        }
        let destination = temporaryURL(for: .annotatedVideo)
        exportSession.outputURL = destination
        exportSession.outputFileType = .mov
        exportSession.videoComposition = composition

        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                if exportSession.status == .completed {
                    continuation.resume(returning: destination)
                } else {
                    continuation.resume(throwing: exportSession.error ?? MediaExportError.exportFailed)
                }
            }
        }
    }

    private static func render(drawings: [DrawingElement], over image: CGImage) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            drawings.forEach { drawing in
                let path = path(for: drawing, canvasSize: size)
                UIColor(drawing.color).setStroke()
                path.lineWidth = drawing.lineWidth * max(1, size.width / 390)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }.cgImage!
    }

    private static func shapeLayer(for drawing: DrawingElement, canvasSize: CGSize) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path(for: drawing, canvasSize: canvasSize).cgPath
        layer.strokeColor = UIColor(drawing.color).cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = drawing.lineWidth * max(1, canvasSize.width / 390)
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private static func path(for drawing: DrawingElement, canvasSize: CGSize) -> UIBezierPath {
        let points = drawing.points.map {
            CGPoint(x: $0.x * canvasSize.width, y: (1 - $0.y) * canvasSize.height)
        }
        let path = UIBezierPath()
        guard let first = points.first else { return path }

        switch drawing.tool {
        case .circle:
            let second = points.dropFirst().first ?? first
            path.append(UIBezierPath(ovalIn: DrawingCircleGeometry.bounds(center: first, edge: second)))
        case .angle:
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        case .arrow:
            let end = points.dropFirst().first ?? first
            path.move(to: first)
            path.addLine(to: end)
            if let head = ArrowGeometry.headPoints(
                start: first,
                end: end,
                length: 14 * max(1, canvasSize.width / 390)
            ) {
                path.move(to: head.left)
                path.addLine(to: end)
                path.addLine(to: head.right)
            }
        case .select, .line, .freehand:
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        return path
    }

    private static func temporaryURL(for kind: MediaExportKind) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SwingArc-\(UUID().uuidString)")
            .appendingPathExtension(kind.fileExtension)
    }

    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
#endif
