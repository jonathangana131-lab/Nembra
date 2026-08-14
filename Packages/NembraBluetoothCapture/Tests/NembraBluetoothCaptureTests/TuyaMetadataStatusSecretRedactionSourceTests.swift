import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya metadata status secret redaction source contract")
struct TuyaMetadataStatusSecretRedactionSourceTests {
    @Test("raw status entries are redacted before retained UI state")
    func statusAdmissionCannotBypassRecursiveSecretRedaction() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let load = try section(
            in: bridge,
            from: "private func loadSelectedDeviceDetails",
            to: "private func signedGET"
        )
        let body = String(load)

        #expect(body.contains("selectedDeviceStatus = Self.redactAccountUID("))
        #expect(body.contains("Self.redactSecrets(statusMap),"))
        #expect(body.contains("accountUID: accountUID"))
        #expect(!body.contains("selectedDeviceStatus = statusMap"))
    }

    @Test("export re-applies redaction to retained status as defense in depth")
    func exportCannotTrustRetainedStatusMapWithoutRedaction() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let export = try section(
            in: bridge,
            from: "func prepareRedactedExport()",
            to: "func resetLink()"
        )
        let body = String(export)

        #expect(body.contains("\"status\": Self.redactSecrets(selectedDeviceStatus ?? [:])"))
        #expect(body.contains("Self.redactAccountUID(envelope, accountUID: accountUID)"))
        #expect(!body.contains("\"status\": selectedDeviceStatus ?? [:]"))
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