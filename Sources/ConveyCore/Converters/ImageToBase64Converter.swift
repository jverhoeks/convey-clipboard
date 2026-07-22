import Foundation

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

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .bytes(data) = input else {
            throw ConversionError.wrongPayload(expected: "bytes")
        }
        return .text("data:\(Self.mime(for: data));base64,\(data.base64EncodedString())")
    }
}
