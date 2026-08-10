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
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(prepareExport.contains("No account UID"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(updateAdmission.contains("redactedApplicationUpdateForEventCustody"))
        #expect(!updateAdmission.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("UID scrubber is bound to the exact pre-await membership lease")
    func accountUIDLeaseIsCapturedBeforeAsyncAdmission() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationUpdateForEventCustody"
        ))
        let scrubber = String(try section(
            in: source,
            from: "private func redactedApplicationUpdateForEventCustody",
            to: "private func startWatchdog"
        ))

        let capturedLease = try requiredOffset(
            containing: "let verifiedAccountUID = membershipAccountUID",
            in: receiver
        )
        let firstAwait = try requiredOffset(
            containing: "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let scrubCall = try requiredOffset(
            containing: "verifiedAccountUID: verifiedAccountUID",
            in: receiver
        )

        #expect(capturedLease < firstAwait)
        #expect(firstAwait < scrubCall)
        #expect(receiver.contains("!verifiedAccountUID.isEmpty"))
        #expect(scrubber.contains("verifiedAccountUID: String"))
        #expect(!scrubber.contains("membershipAccountUID"))
    }

    @Test("account UID custody scrubs both application keys and values without blanket uid-key erasure")
    func accountUIDCustodyIsValueBound() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(controller.contains("key.replacingOccurrences("))
        #expect(controller.contains("value.replacingOccurrences("))
        #expect(controller.contains("with: \"<redacted-account-uid>\""))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    @Test("application secret classifier carries one session-key rule")
    func duplicateSessionKeyClassifierIsRemoved() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.components(separatedBy: "\"sessionkey\",").count - 1 == 1)
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
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
