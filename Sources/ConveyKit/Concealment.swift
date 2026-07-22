import ConveyCore

public enum Concealment {
    static let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]

    public static func isConcealedOrTransient(_ snapshot: PasteboardSnapshot) -> Bool {
        let types = Set(snapshot.availableTypes)
        return markers.contains { types.contains($0) }
    }
}
