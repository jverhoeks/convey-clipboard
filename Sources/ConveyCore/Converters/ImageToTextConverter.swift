import Foundation
import Vision

/// On-demand, on-device OCR for clipboard images.
public struct ImageToTextConverter: Converter {
    public let from: Format = .image
    public let to: Format = .plainText

    public init() {}

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .bytes(data) = input else {
            throw ConversionError.wrongPayload(expected: "bytes")
        }
        try Task.checkCancellation()
        // Vision's synchronous work must not block the menu-bar UI.
        let text: String = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.automaticallyDetectsLanguage = true
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(data: data, options: [:]).perform([request])
                    let text = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw ImageTextError.noText }
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try Task.checkCancellation()
        return .text(text)
    }
}

public enum ImageTextError: LocalizedError {
    case noText

    public var errorDescription: String? {
        "No text was found in this image. Try a clearer or larger capture."
    }
}
