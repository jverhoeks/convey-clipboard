import Foundation

/// Converts a BSD `script -r` recording into an asciicast v2 file (asciinema's format).
///
/// `script -r` records a stream of 24-byte little-endian headers — length u64, seconds u64,
/// microseconds u32, direction u32 ('s' start, 'o' output, 'i' input, 'e' end) — each
/// followed by `length` bytes. Only output is kept; typed input is already echoed in it.
public enum Asciicast {
    public static func fromScriptRecording(_ data: Data, width: Int, height: Int,
                                           env: [String: String] = [:]) throws -> String {
        let bytes = [UInt8](data)
        func u64(_ at: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(bytes[at + $1]) << (8 * $1) } }
        func u32(_ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(bytes[at + $1]) << (8 * $1) } }

        var start: Double?
        var lines: [String] = []
        var pending: [UInt8] = []  // incomplete UTF-8 sequence split across two chunks
        var i = 0
        while i + 24 <= bytes.count {
            let len = Int(u64(i)), time = Double(u64(i + 8)) + Double(u32(i + 16)) / 1_000_000
            let direction = u32(i + 20)
            let body = i + 24
            guard len >= 0, body + len <= bytes.count else { throw AsciicastError.truncated }
            i = body + len
            if start == nil { start = time }
            guard direction == UInt32(UInt8(ascii: "o")), len > 0 else { continue }
            pending += bytes[body..<body + len]
            let text = decodePrefix(&pending)
            guard !text.isEmpty else { continue }
            let t = String(format: "%.6f", time - (start ?? time))  // JSONSerialization prints 17 digits
            lines.append("[\(t),\"o\",\(try json(text))]")
        }
        var header: [String: Any] = ["version": 2, "width": width, "height": height]
        if let start { header["timestamp"] = Int(start) }
        if !env.isEmpty { header["env"] = env }
        return ([try json(header)] + lines).joined(separator: "\n") + "\n"
    }

    /// Decodes and removes the longest valid UTF-8 prefix, keeping up to 3 trailing bytes
    /// of a split character for the next chunk. Garbage that can never be valid is decoded lossily.
    static func decodePrefix(_ buffer: inout [UInt8]) -> String {
        for keep in 0...min(3, buffer.count) {
            if let s = String(bytes: buffer.dropLast(keep), encoding: .utf8) {
                buffer = Array(buffer.suffix(keep))
                return s
            }
        }
        defer { buffer = [] }
        return String(decoding: buffer, as: UTF8.self)
    }

    private static func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]),
               as: UTF8.self)
    }
}

public enum AsciicastError: Error, CustomStringConvertible {
    case truncated
    public var description: String { "recording is truncated or not a `script -r` file" }
}
