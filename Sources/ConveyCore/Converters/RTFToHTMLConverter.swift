import Foundation
import AppKit

public struct RTFToHTMLConverter: Converter {
    public let from: Format = .rtf
    public let to: Format = .html

    public init() {}

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .bytes(data) = input else {
            throw ConversionError.wrongPayload(expected: "bytes")
        }
        return try await MainActor.run {
            guard let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) else {
                throw ConversionError.engineFailed("rtf parse")
            }
            let htmlData = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            )
            guard let html = String(data: htmlData, encoding: .utf8) else {
                throw ConversionError.engineFailed("html encode")
            }
            return Payload.text(html)
        }
    }
}
