import Foundation
import AppKit

public struct ImageToBase64Converter: Converter {
    public let from: Format = .image
    public let to: Format = .base64DataURI

    public init() {}

    public static func mime(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        return "application/octet-stream"
    }

    /// Detects TIFF by its byte-order signature: `II*\0` (little-endian) or `MM\0*` (big-endian).
    public static func isTIFF(_ d: Data) -> Bool {
        d.starts(with: [0x49, 0x49, 0x2A, 0x00]) || d.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
    }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .bytes(data) = input else {
            throw ConversionError.wrongPayload(expected: "bytes")
        }
        // macOS clipboard images are often public.tiff with no public.png; mime(for:)
        // has no TIFF case, so without transcoding this would produce an unusable
        // application/octet-stream data-URI. Transcode to PNG via AppKit first.
        var out = data
        if Self.isTIFF(data) {
            out = try await MainActor.run { () throws -> Data in
                guard let rep = NSBitmapImageRep(data: data),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    throw ConversionError.engineFailed("tiff->png")
                }
                return png
            }
        }
        return .text("data:\(Self.mime(for: out));base64,\(out.base64EncodedString())")
    }
}
