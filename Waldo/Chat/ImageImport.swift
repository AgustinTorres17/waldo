import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Images added to a chat from a file or the clipboard. Reduced to `maxSide`,
/// because the model doesn't need more and a photo would use a lot of memory.
@MainActor
enum ImageImport {
    private static let maxSide = 2_048

    static func image(fromFile url: URL) -> ChatImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(image(from:))
    }

    /// The image on the clipboard: a copied file, or the picture itself.
    /// Nil when it holds text, even with a picture of it (a table from a
    /// spreadsheet, say), so that it's pasted as text.
    static func imageOnClipboard(_ pasteboard: NSPasteboard = .general) -> ChatImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], let url = urls.first {
            return image(fromFile: url)
        }
        guard pasteboard.string(forType: .string)?.isEmpty ?? true else { return nil }
        for type in pasteboard.types ?? [] where UTType(type.rawValue)?.conforms(to: .image) == true {
            if let data = pasteboard.data(forType: type),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = image(from: source) {
                return image
            }
        }
        return nil
    }

    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to ask about"
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func image(from source: CGImageSource) -> ChatImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // photos taken sideways
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).flatMap { ChatImage($0) }
    }
}
