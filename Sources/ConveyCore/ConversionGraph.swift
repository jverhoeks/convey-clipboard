/// A directed graph of `Converter` edges, used to discover and run conversion paths.
///
/// `@unchecked Sendable` contract: the graph is built once — via `register(_:)` calls
/// made from `Convey.init` on the main actor — and is treated as read-only afterward.
/// `register(_:)` must not be called concurrently with `path`, `validTargets`, or
/// `convert`; there is no internal synchronization protecting `edges` against
/// concurrent mutation and reads.
public final class ConversionGraph: @unchecked Sendable {
    private var edges: [Format: [Converter]] = [:]

    public init(_ converters: [Converter] = []) {
        converters.forEach(register)
    }

    public func register(_ converter: Converter) {
        edges[converter.from, default: []].append(converter)
    }

    public func validTargets(from sources: [Format]) -> [Format] {
        var visited = Set(sources)
        var queue = sources
        var result: [Format] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            for edge in edges[node] ?? [] where !visited.contains(edge.to) {
                visited.insert(edge.to)
                result.append(edge.to)
                queue.append(edge.to)
            }
        }
        return result
    }

    public func path(from: Format, to: Format) -> [Converter]? {
        if from == to { return [] }
        var visited: Set<Format> = [from]
        var queue: [(Format, [Converter])] = [(from, [])]
        while !queue.isEmpty {
            let (node, acc) = queue.removeFirst()
            for edge in edges[node] ?? [] where !visited.contains(edge.to) {
                let next = acc + [edge]
                if edge.to == to { return next }
                visited.insert(edge.to)
                queue.append((edge.to, next))
            }
        }
        return nil
    }

    public func convert(_ payload: Payload, from: Format, to: Format) async throws -> Payload {
        guard let path = path(from: from, to: to) else {
            throw ConversionError.noPath(from: from, to: to)
        }
        var current = payload
        for converter in path {
            current = try await converter.convert(current)
        }
        return current
    }
}
