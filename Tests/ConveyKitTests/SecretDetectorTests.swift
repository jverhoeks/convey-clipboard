import XCTest
@testable import ConveyKit

final class SecretDetectorTests: XCTestCase {
    func testDetectsCommonTokens() {
        for s in ["sk-abcdefghijklmnopqrstuvwxyz0123", "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef1234",
                  "AKIAIOSFODNN7EXAMPLE", "-----BEGIN RSA PRIVATE KEY-----\nMIIE",
                  "export API_KEY=abcd1234efgh5678", "xoxb-1234567890-abcdefghij"] {
            XCTAssertTrue(SecretDetector.looksLikeSecret(s), s)
        }
    }
    func testIgnoresOrdinaryText() {
        for s in ["hello world", "sk-short", "the token was revoked", "password: hunter2", "https://example.com/a/b"] {
            XCTAssertFalse(SecretDetector.looksLikeSecret(s), s)
        }
    }
}
