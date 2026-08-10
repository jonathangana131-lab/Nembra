import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence redacts the verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let updateAdmission = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let uidRedaction = String(try section(
            in: source,
            from: "private func redactAccountUIDFromApplicationDetails(",
            to: "private func startWatchdog"
        ))
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(prepareExport.contains("No account UID"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(!updateAdmission.contains("log(\"tuya_application_update\", update.merging(["))

        // Custody binds to the exact membership UID admitted with the same account lease.
        // The snapshot survives the actor hop so a re-entrant account change cannot make the
        // redactor fall back to raw application evidence before event custody.
        #expect(updateAdmission.contains("let admittedAccountUID = membershipAccountUID?.trimmingCharacters"))
        #expect(updateAdmission.contains("membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == admittedAccountUID"))
        #expect(updateAdmission.contains("accountUID: admittedAccountUID"))

        // Scrub the exact UID from both malformed keys and values. If redaction makes two keys
        // collide, preserve both sanitized values instead of silently dropping one.
        #expect(uidRedaction.contains("of: exactAccountUID"))
        #expect(uidRedaction.contains("with: \"<redacted-account-uid>\""))
        #expect(uidRedaction.contains("let baseKey = redacted(key)"))
        #expect(uidRedaction.contains("while sanitized[admittedKey] != nil"))
        #expect(uidRedaction.contains("sanitized[admittedKey] = redacted(value)"))
    }

    @Test("account UID custody is value-bound rather than a blanket generic uid-key rule")
    func accountUIDCustodyDoesNotEraseGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
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
