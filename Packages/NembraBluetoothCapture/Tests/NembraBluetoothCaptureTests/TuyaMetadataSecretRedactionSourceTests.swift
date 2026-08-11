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
        for fragment in [
            "localkey",
            "sessionkey",
            "appkey",
            "appsecret",
            "password",
            "accounttoken",
            "accesstoken",
            "refreshtoken",
            "authkey",
            "seckey",
        ] {
            #expect(body.contains("\"\(fragment)\""), "Metadata sanitizer must redact every export-promised credential key: \(fragment)")
        }
        #expect(body.contains("key.lowercased().filter"))
        #expect(body.contains("$0.isletter || $0.isnumber"))
        #expect(body.contains("redactsecrets(value)"))
        #expect(body.contains("array.map(redactsecrets)"))
        #expect(!body.contains("normalized.contains(\"access_token\")"))
        #expect(!body.contains("normalized.contains(\"refresh_token\")"))
        #expect(!body.contains("normalized.contains(\"session_key\")"))
    }

    @Test("final metadata export re-sanitizes every current opaque payload at custody")
    func finalExportReSanitizesOpaquePayloads() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let export = try section(
            in: bridge,
            from: "func prepareRedactedExport()",
            to: "func resetLink()"
        )
        let body = String(export)

        #expect(body.contains("\"status\": Self.redactSecrets(selectedDeviceStatus ?? [:])"))
        #expect(body.contains("\"specifications\": Self.redactSecrets(selectedDeviceSpecifications ?? [:])"))
        #expect(body.contains("envelope[\"deviceDetailRedacted\"] = Self.redactSecrets(selectedDeviceMetadata)"))
        #expect(!body.contains("\"status\": selectedDeviceStatus ?? [:]"))
        #expect(!body.contains("\"specifications\": selectedDeviceSpecifications ?? [:]"))
        #expect(!body.contains("envelope[\"deviceDetailRedacted\"] = selectedDeviceMetadata"))
        #expect(!body.contains("selectedDeviceLocalStrategy"))
        #expect(!body.contains("\"localStrategy\""))
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