import Foundation
import AppKit

/// Transcodes raster image bytes (e.g. TIFF from the pasteboard) to PNG.
public enum ImageTranscoder {
    /// Returns PNG-encoded bytes for the given image data, or `nil` if the
    /// data is not a decodable image.
    public static func pngData(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
