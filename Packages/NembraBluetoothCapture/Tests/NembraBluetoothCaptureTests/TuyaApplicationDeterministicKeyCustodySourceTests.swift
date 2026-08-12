import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya deterministic application-key custody")
struct TuyaApplicationDeterministicKeyCustodySourceTests {
    @Test("top-level and nested dictionaries canonicalize original keys before redaction collisions")
    func originalKeyOrderingPrecedesCollisionSuffixing() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let callback = String(try section(
            in: driver,
            from: "func device(_ device: ThingSmartDevice?, dpsUpdate",
            to: "private static func sortedApplicationEntries("
        ))
        let sanitizerStart = try #require(driver.range(of: "private static func redactApplicationSecrets("))
        let sanitizer = String(driver[sanitizerStart.lowerBound...])

        #expect(callback.contains("for (key, value) in Self.sortedApplicationEntries(dps)"))
        #expect(!callback.contains("for (key, value) in dps {"))
        #expect(sanitizer.contains("for (key, value) in sortedApplicationEntries(dictionary)"))
        #expect(!sanitizer.contains("for (key, value) in dictionary {"))

        let sort = try #require(callback.range(of: "Self.sortedApplicationEntries(dps)"))
        let redact = try #require(callback.range(of: "Self.redactKnownSecretValues(in: keyString)"))
        let collision = try #require(callback.range(of: "while sanitized[custodyKey] != nil"))
        #expect(sort.lowerBound < redact.lowerBound)
        #expect(redact.lowerBound < collision.lowerBound)
    }

    @Test("canonical ordering uses original spelling, scalar type and scalar reflection")
    func canonicalOrderingDoesNotDependOnRedactedCustodyKey() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private static func sortedApplicationEntries(",
            to: "private static let secretKeyFragments"
        ))

        #expect(helper.contains("String(describing: left.key)"))
        #expect(helper.contains("String(describing: right.key)"))
        #expect(helper.contains("String(reflecting: type(of: left.key.base))"))
        #expect(helper.contains("String(reflecting: type(of: right.key.base))"))
        #expect(helper.contains("String(reflecting: left.key.base)"))
        #expect(helper.contains("String(reflecting: right.key.base)"))
        #expect(!helper.contains("redactKnownSecretValues"))
    }

    @Test("private secret ordering and lossless collision fences stay composed")
    func currentSecretCustodyRemainsIntact() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.contains("Set([NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret])"))
        #expect(driver.contains("left.count > right.count"))
        #expect(driver.contains("while sanitized[custodyKey] != nil"))
        #expect(driver.contains("redactedApplicationDescription(value)"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}