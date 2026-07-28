import Foundation

@main
struct PrecisionVideoInventorySmoke {
    static func main() {
        let metadata = InventoryVideoMetadata(
            fileName: "IMG_4694.MOV",
            sourceFrameRate: 30,
            duration: 45.5,
            width: 1080,
            height: 1920
        )
        let clip = PrecisionVideoInventory.makeDevelopmentClip(metadata: metadata)

        precondition(clip.clipID == "unassigned-img-4694")
        precondition(clip.golferID == nil)
        precondition(clip.view == nil)
        precondition(clip.handedness == nil)
        precondition(clip.split == .development)
        precondition(clip.annotationPasses == 0)
        precondition(clip.sourceFrameRate == 30)
        precondition(clip.duration == 45.5)
        precondition(clip.sourceWidth == 1080)
        precondition(clip.sourceHeight == 1920)
    }
}
