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
        // Match the top-left UIKit/SwiftUI drawing coordinate system when
        // Core Animation renders this detached layer tree offscreen.
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let drawingLayer = CALayer()
        drawingLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(drawingLayer)

        let duration = max(asset.duration.seconds, 0.01)
        drawings.forEach { drawing in
            let layer = annotationLayer(for: drawing, canvasSize: renderSize)
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
                draw(drawing, canvasSize: size)
            }
        }.cgImage!
    }

    private static func draw(_ drawing: DrawingElement, canvasSize: CGSize) {
        let scale = max(1, canvasSize.width / 390)
        let linePath = path(for: drawing, canvasSize: canvasSize)
        UIColor(drawing.color).setStroke()
        linePath.lineWidth = drawing.lineWidth * scale
        linePath.lineCapStyle = .round
        linePath.lineJoinStyle = .round
        linePath.stroke()

        guard let layout = angleLayout(for: drawing, canvasSize: canvasSize) else {
            return
        }
        let arcPath = path(forArcPoints: layout.arcPoints)
        UIColor(drawing.color).withAlphaComponent(0.5).setStroke()
        arcPath.lineWidth = 2 * scale
        arcPath.lineCapStyle = .round
        arcPath.stroke()

        let label = angleLabel(for: layout, drawing: drawing, scale: scale)
        let labelSize = label.size()
        label.draw(at: CGPoint(
            x: layout.labelCenter.x - labelSize.width / 2,
            y: layout.labelCenter.y - labelSize.height / 2
        ))
    }

    private static func annotationLayer(for drawing: DrawingElement, canvasSize: CGSize) -> CALayer {
        let scale = max(1, canvasSize.width / 390)
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: canvasSize)

        let lineLayer = CAShapeLayer()
        lineLayer.frame = container.bounds
        lineLayer.path = path(for: drawing, canvasSize: canvasSize).cgPath
        lineLayer.strokeColor = UIColor(drawing.color).cgColor
        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.lineWidth = drawing.lineWidth * scale
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        container.addSublayer(lineLayer)

        guard let layout = angleLayout(for: drawing, canvasSize: canvasSize) else {
            return container
        }

        let arcLayer = CAShapeLayer()
        arcLayer.frame = container.bounds
        arcLayer.path = path(forArcPoints: layout.arcPoints).cgPath
        arcLayer.strokeColor = UIColor(drawing.color).withAlphaComponent(0.5).cgColor
        arcLayer.fillColor = UIColor.clear.cgColor
        arcLayer.lineWidth = 2 * scale
        arcLayer.lineCap = .round
        container.addSublayer(arcLayer)

        let label = angleLabel(for: layout, drawing: drawing, scale: scale)
        let labelSize = label.size()
        let labelLayer = CATextLayer()
        labelLayer.contentsScale = max(2, UIScreen.main.scale)
        labelLayer.string = label
        labelLayer.alignmentMode = .center
        labelLayer.frame = CGRect(
            x: layout.labelCenter.x - labelSize.width / 2,
            y: layout.labelCenter.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        container.addSublayer(labelLayer)
        return container
    }

    private static func path(for drawing: DrawingElement, canvasSize: CGSize) -> UIBezierPath {
        let points = canvasPoints(for: drawing, canvasSize: canvasSize)
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

    private static func canvasPoints(
        for drawing: DrawingElement,
        canvasSize: CGSize
    ) -> [CGPoint] {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        return drawing.points.map {
            DrawingCanvasGeometry.denormalizedPoint($0, in: canvasRect)
        }
    }

    private static func angleLayout(
        for drawing: DrawingElement,
        canvasSize: CGSize
    ) -> DrawingAngleLayout? {
        guard drawing.tool == .angle else { return nil }
        let scale = max(1, canvasSize.width / 390)
        return DrawingAngleGeometry.layout(
            points: canvasPoints(for: drawing, canvasSize: canvasSize),
            preferredArcRadius: 25 * scale,
            labelOffset: 15 * scale,
            arcSegmentCount: max(24, Int(ceil(24 * scale)))
        )
    }

    private static func path(forArcPoints points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private static func angleLabel(
        for layout: DrawingAngleLayout,
        drawing: DrawingElement,
        scale: CGFloat
    ) -> NSAttributedString {
        NSAttributedString(
            string: String(format: "%.1f°", layout.degrees),
            attributes: [
                .font: UIFont.systemFont(ofSize: 11 * scale, weight: .bold),
                .foregroundColor: UIColor(drawing.color)
            ]
        )
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
