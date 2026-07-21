import Foundation

public enum Payload: Equatable, Sendable {
    case text(String)
    case bytes(Data)

    public var text: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    public var bytes: Data? {
        if case let .bytes(value) = self { return value }
        return nil
    }
}
