import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence redacts the verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func applicationUpdateForEventCustody(",
            to: "private func receivedApplicationUpdate("
        ))
        let updateAdmission = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(prepareExport.contains("No account UID"))
        #expect(helper.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.contains("key.replacingOccurrences("))
        #expect(helper.contains("value.replacingOccurrences("))
        #expect(helper.contains("update.keys.sorted()"))
        #expect(helper.contains("while redacted[uniqueKey] != nil"))
        #expect(updateAdmission.contains("guard let custodySafeUpdate = applicationUpdateForEventCustody(update)"))
        #expect(updateAdmission.contains("sdk_account_uid_custody_unavailable"))
        #expect(updateAdmission.contains("log(\"tuya_application_update\", custodySafeUpdate.merging(["))
        #expect(!updateAdmission.contains("log(\"tuya_application_update\", update.merging(["))
        #expect(updateAdmission.contains("]) { _, trusted in trusted })"))
        #expect(!updateAdmission.contains("]) { current, _ in current })"))
    }

    @Test("account UID custody is value-bound rather than a blanket generic uid-key rule")
    func accountUIDCustodyDoesNotEraseGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let fragments = String(try section(
            in: driver,
            from: "private static let secretKeyFragments",
            to: "private static func redactApplicationSecrets"
        ))

        #expect(!fragments.contains("\"uid\","))
        #expect(!fragments.contains("\"uid\"\n"))
        #expect(fragments.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
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
