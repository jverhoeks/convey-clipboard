public struct MarkdownToHTMLConverter: Converter {
    public let from: Format = .markdown
    public let to: Format = .html
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(markdown) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return window.markdownToHtml(md);", arguments: ["md": markdown])
        guard let html = result as? String else {
            throw ConversionError.engineFailed("marked")
        }
        return .text(html)
    }
}
