import Foundation

@main
struct MediaExportFormatSmoke {
    static func main() {
        precondition(MediaExportKind.frame.fileExtension == "jpg")
        precondition(MediaExportKind.annotatedVideo.fileExtension == "mov")
    }
}
