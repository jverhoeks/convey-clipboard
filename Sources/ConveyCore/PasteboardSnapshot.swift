import Foundation
import AppKit

public protocol PasteboardSnapshot {
    var availableTypes: [String] { get }
    func data(forType type: String) -> Data?
    func string(forType type: String) -> String?
}

public struct SystemPasteboard: PasteboardSnapshot {
    private let pasteboard: NSPasteboard

    public init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var availableTypes: [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    public func data(forType type: String) -> Data? {
        pasteboard.data(forType: NSPasteboard.PasteboardType(type))
    }

    public func string(forType type: String) -> String? {
        pasteboard.string(forType: NSPasteboard.PasteboardType(type))
    }
}
