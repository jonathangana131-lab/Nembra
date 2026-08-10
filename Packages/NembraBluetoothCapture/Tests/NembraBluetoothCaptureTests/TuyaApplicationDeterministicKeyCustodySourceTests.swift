import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya deterministic application-key custody")
struct TuyaApplicationDeterministicKeyCustodySourceTests {
    @Test("top-level and nested maps sort original SDK keys before collision custody")
    func originalOrderingPrecedesRedactionCollisions() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        let callback = String(try section(in: driver, from: "func device(_ device: ThingSmartDevice?, dpsUpdate", to: "private static func sortedApplicationEntries("))
        let sanitizer = String(try section(in: driver, from: "private static func redactApplicationSecrets(", to: "}\n#endif"))

        #expect(callback.contains("for (key, value) in Self.sortedApplicationEntries(dps)"))
        #expect(!callback.contains("for (key, value) in dps {"))
        #expect(sanitizer.contains("for (key, value) in sortedApplicationEntries(dictionary)"))
        #expect(!sanitizer.contains("for (key, value) in dictionary {"))
        #expect(callback.contains("Self.redactKnownSecretValues(in: keyString)"))
        #expect(callback.contains("while sanitized[custodyKey] != nil"))
    }

    @Test("ordering is based on original scalar identity, never the redacted custody key")
    func helperDoesNotConsumeRedactionAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(in: source, from: "private static func sortedApplicationEntries(", to: "private static let secretKeyFragments"))
        #expect(helper.contains("String(describing: left.key)"))
        #expect(helper.contains("String(describing: right.key)"))
        #expect(helper.contains("type(of: left.key.base)"))
        #expect(helper.contains("type(of: right.key.base)"))
        #expect(helper.contains("String(reflecting: left.key.base)"))
        #expect(helper.contains("String(reflecting: right.key.base)"))
        #expect(!helper.contains("redactKnownSecretValues"))
    }

    @Test("merged longest-first secret and collision fences survive")
    func secretCustodyRemainsIntact() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(driver.contains("Set([NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret])"))
        #expect(driver.contains("if left.count != right.count { return left.count > right.count }"))
        #expect(driver.contains("redactedApplicationDescription(value)"))
        #expect(driver.contains("while sanitized[custodyKey] != nil"))
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
