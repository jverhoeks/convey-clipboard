public struct HTMLToMarkdownConverter: Converter {
    public let from: Format = .html
    public let to: Format = .markdown
    private let runtime: WebRuntime

    public init(runtime: WebRuntime) { self.runtime = runtime }

    public func convert(_ input: Payload) async throws -> Payload {
        guard case let .text(html) = input else {
            throw ConversionError.wrongPayload(expected: "text")
        }
        let result = try await runtime.call("return window.htmlToMarkdown(html);", arguments: ["html": html])
        guard let markdown = result as? String else {
            throw ConversionError.engineFailed("turndown")
        }
        return .text(markdown)
    }
}
