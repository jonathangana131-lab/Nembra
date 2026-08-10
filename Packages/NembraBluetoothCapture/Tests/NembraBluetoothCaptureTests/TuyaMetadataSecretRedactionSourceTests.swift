import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya metadata secret redaction source contract")
struct TuyaMetadataSecretRedactionSourceTests {
    @Test("recursive redaction normalizes credential key spelling before classification")
    func tokenKeySpellingsCannotBypassRedaction() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let redaction = try section(
            in: bridge,
            from: "private static func redactSecrets(_ object: Any) -> Any",
            to: "private static func remoteMessage"
        )
        let body = String(redaction).lowercased()

        #expect(body.contains("secretkeyfragments"))
        #expect(body.contains("localkey"))
        #expect(body.contains("accesstoken"))
        #expect(body.contains("refreshtoken"))
        #expect(body.contains("authkey"))
        #expect(body.contains("seckey"))
        #expect(body.contains("key.lowercased().filter"))
        #expect(body.contains("$0.isletter || $0.isnumber"))
        #expect(body.contains("redactsecrets(value)"))
        #expect(body.contains("array.map(redactsecrets)"))

        // The old punctuation-sensitive checks allowed camelCase token keys through.
        #expect(!body.contains("normalized.contains(\"access_token\")"))
        #expect(!body.contains("normalized.contains(\"refresh_token\")"))
    }

    @Test("linked device UI state does not retain raw device dictionaries or local key")
    func linkedDeviceStateRemainsSecretFree() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let linkedDevice = try section(
            in: bridge,
            from: "struct LinkedDevice: Identifiable, Equatable",
            to: "enum Phase"
        )
        let body = String(linkedDevice)

        #expect(!body.contains("localKey"))
        #expect(!body.contains("local_key"))
        #expect(!body.contains("raw: [String: AnyHashable]"))
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
