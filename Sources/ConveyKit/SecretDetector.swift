import Foundation

/// Heuristic "this looks like a credential" check for clipboard text.
/// Hits are stored in history but masked until the user authenticates, and never persisted to disk.
public enum SecretDetector {
    // ponytail: prefix/shape regexes only; add entropy scoring if false negatives bite.
    static let patterns: [NSRegularExpression] = [
        #"\bsk-(proj-|ant-)?[A-Za-z0-9_-]{20,}"#,           // OpenAI / Anthropic
        #"\bgh[pousr]_[A-Za-z0-9]{30,}"#,                     // GitHub
        #"\bgithub_pat_[A-Za-z0-9_]{40,}"#,
        #"\bglpat-[A-Za-z0-9_-]{20,}"#,                       // GitLab
        #"\bAKIA[0-9A-Z]{16}\b"#,                             // AWS access key id
        #"\bxox[baprs]-[A-Za-z0-9-]{10,}"#,                   // Slack
        #"\bAIza[0-9A-Za-z_-]{35}"#,                          // Google API key
        #"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\."#, // JWT
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)\b(api[_-]?key|secret|token|passw(or)?d|bearer)\b\s*[:=]\s*['"]?[A-Za-z0-9/+_.-]{12,}"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func looksLikeSecret(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
