import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya metadata account UID custody")
struct TuyaMetadataAccountUIDCustodySourceTests {
    @Test("approved metadata session requires a concrete account UID")
    func approvedSessionCannotLoseAccountIdentity() throws {
        let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let polling = String(try section(
            in: source,
            from: "private func pollApprovalOnce(",
            to: "private func scheduleDeviceLoad"
        ))

        #expect(polling.contains("let uid = result[\"uid\"] as? String ?? \"\""))
        #expect(polling.contains("!uid.isEmpty"))
        #expect(polling.contains("uid: uid"))
    }

    @Test("opaque metadata is scrubbed against the exact owning account UID before UI custody")
    func selectedMetadataCannotRetainOwningAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let load = String(try section(
            in: source,
            from: "private func loadSelectedDeviceDetails(",
            to: "private func signedGET("
        ))

        #expect(load.contains("let accountUID = session.uid.trimmingCharacters"))
        #expect(load.contains("selectedDeviceMetadata = Self.redactAccountUID("))
        #expect(load.contains("selectedDeviceSpecifications = Self.redactAccountUID("))
        #expect(load.contains("selectedDeviceStatus = Self.redactAccountUID("))
        #expect(load.contains("Self.redactSecrets(rawDetail)"))
        #expect(load.contains("Self.redactSecrets(specs[\"result\"]"))
        #expect(load.contains("Self.redactSecrets(statusMap)"))
        #expect(load.components(separatedBy: "accountUID: accountUID").count - 1 == 3)
    }

    @Test("final export scrubs the exact account UID across the complete envelope")
    func finalExportCannotReintroduceAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let export = String(try section(
            in: source,
            from: "func prepareRedactedExport()",
            to: "func resetLink()"
        ))

        let snapshot = try #require(export.range(of: "let accountUID = session.uid.trimmingCharacters"))
        let envelope = try #require(export.range(of: "var envelope: [String: Any]"))
        let custody = try #require(export.range(of: "let custodySafeEnvelope = Self.redactAccountUID(envelope, accountUID: accountUID)"))
        let encode = try #require(export.range(of: "JSONSerialization.data(withJSONObject: custodySafeEnvelope"))
        #expect(snapshot.lowerBound < envelope.lowerBound)
        #expect(envelope.lowerBound < custody.lowerBound)
        #expect(custody.lowerBound < encode.lowerBound)
    }

    @Test("account UID redaction is value-bound, recursive, and collision preserving")
    func accountUIDRedactorPreservesGenericUIDEvidence() throws {
        let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let redactor = String(try section(
            in: source,
            from: "private static func redactAccountUID(",
            to: "private static func remoteMessage"
        ))

        #expect(redactor.contains("accountUID: String"))
        #expect(redactor.contains("<redacted-account-uid>"))
        #expect(redactor.contains("options: [.caseInsensitive, .literal]"))
        #expect(redactor.contains("dictionary.sorted"))
        #expect(redactor.contains("collisionOrdinal"))
        #expect(redactor.contains("while output[custodyKey] != nil"))
        #expect(redactor.contains("redactAccountUID(value, accountUID: accountUID)"))
        #expect(redactor.contains("array.map { redactAccountUID($0, accountUID: accountUID) }"))
        #expect(!redactor.contains("normalized.contains(\"uid\")"))
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