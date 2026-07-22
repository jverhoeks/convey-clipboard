@MainActor
public final class Convey {
    public let graph: ConversionGraph
    private let runtime: WebRuntime

    public init() {
        let runtime = WebRuntime()
        self.runtime = runtime
        graph = ConversionGraph([
            ImageToBase64Converter(),
            RTFToHTMLConverter(),
            HTMLToMarkdownConverter(runtime: runtime),
            HTMLToPlainTextConverter(runtime: runtime),
            MarkdownToHTMLConverter(runtime: runtime),
            MermaidToSVGConverter(runtime: runtime),
            MermaidToPNGConverter(runtime: runtime),
        ])
    }

    public func convert(_ payload: Payload, from: Format, to: Format) async throws -> Payload {
        try await graph.convert(payload, from: from, to: to)
    }
}
