import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application overlapping-secret custody")
struct TuyaApplicationSecretOverlapCustodySourceTests {
    @Test("exact private secrets are de-duplicated and redacted longest-first")
    func exactSecretsCannotPartiallyExposeAnOverlappingLongerCredential() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let order = String(try section(
            in: driver,
            from: "private static var exactSecretValues",
            to: "private static func redactKnownSecretValues"
        ))
        let redactor = String(try section(
            in: driver,
            from: "private static func redactKnownSecretValues",
            to: "private static func redactedApplicationDescription"
        ))

        #expect(order.contains("Set(["))
        #expect(order.contains(".sorted"))
        #expect(order.contains("left.count > right.count"))
        #expect(order.contains("left < right"))
        #expect(redactor.contains("for secret in exactSecretValues"))
        #expect(redactor.contains("replacingOccurrences(of: secret, with: \"<redacted>\")"))
    }

    @Test("longest-first ordering removes a longer overlapping secret as one credential")
    func overlapModel() {
        let values = Set(["foo", "foobar"])
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                return left < right
            }
        var text = "opaque=foobar"
        for secret in values {
            text = text.replacingOccurrences(of: secret, with: "<redacted>")
        }
        #expect(text == "opaque=<redacted>")
        #expect(!text.contains("bar"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
