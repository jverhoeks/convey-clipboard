import Foundation

public struct MermaidToSVGConverter: Converter {
    public let from: Format = .mermaid
    public let to: Format = .svg
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(src) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return await window.mermaidToSvg(src);", arguments: ["src": src])
        guard let svg = result as? String else {
            throw ConversionError.engineFailed("mermaid svg")
        }
        return .text(svg)
    }
}

public struct MermaidToPNGConverter: Converter {
    public let from: Format = .mermaid
    public let to: Format = .png
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(src) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return await window.mermaidToPngDataUrl(src, 2);", arguments: ["src": src])
        guard let dataURL = result as? String,
              let comma = dataURL.range(of: ","),
              let data = Data(base64Encoded: String(dataURL[comma.upperBound...])) else {
            throw ConversionError.engineFailed("mermaid png")
        }
        return .bytes(data)
    }
}
