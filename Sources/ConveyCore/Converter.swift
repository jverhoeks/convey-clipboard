public protocol Converter: Sendable {
    var from: Format { get }
    var to: Format { get }
    func convert(_ input: Payload) async throws -> Payload
}

public enum ConversionError: Error, Equatable {
    case wrongPayload(expected: String)
    case noPath(from: Format, to: Format)
    case engineFailed(String)
}
