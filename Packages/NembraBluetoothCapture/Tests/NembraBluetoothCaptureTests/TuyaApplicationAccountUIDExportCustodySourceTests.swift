import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence scrubs the verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let admission = String(try section(
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
        #expect(admission.contains("let membershipAccountUID"))
        #expect(admission.contains("let exportSafeUpdate = Self.redactingVerifiedAccountUID"))
        #expect(admission.contains("<redacted-account-uid>"))
        #expect(!admission.contains("log(\"tuya_application_update\", update.merging(["))
        #expect(admission.contains("log(\"tuya_application_update\", exportSafeUpdate.merging(["))
    }

    @Test("scrubber removes the exact verified account UID from both application keys and values")
    func accountUIDBearingKeysAndValuesAreBothScrubbed() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let admission = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(admission.contains("private static func redactingVerifiedAccountUID"))
        #expect(admission.contains("safeKey = key.replacingOccurrences"))
        #expect(admission.contains("safeValue = value.replacingOccurrences"))
        #expect(admission.contains("with: \"<redacted-account-uid>\""))
        #expect(admission.contains("options: [.literal]"))
    }

    @Test("account identity custody does not become a blanket generic uid-key classifier")
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
