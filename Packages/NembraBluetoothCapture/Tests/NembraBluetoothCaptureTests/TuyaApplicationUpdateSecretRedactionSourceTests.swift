import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application update secret redaction source contract")
struct TuyaApplicationUpdateSecretRedactionSourceTests {
    @Test("authenticated application update details are recursively redacted before controller custody")
    func applicationUpdateCannotRetainCredentialShapedValues() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.contains("private static func redactApplicationSecrets(_ object: Any) -> Any"))
        #expect(driver.contains("secretKeyFragments"))
        #expect(driver.contains("localkey"))
        #expect(driver.contains("accesstoken"))
        #expect(driver.contains("refreshtoken"))
        #expect(driver.contains("sessionkey"))
        #expect(driver.contains("authkey"))
        #expect(driver.contains("seckey"))
        #expect(driver.contains("keyString.lowercased().filter"))
        #expect(driver.contains("$0.isLetter || $0.isNumber"))
        #expect(driver.contains("array.map(redactApplicationSecrets)"))
        #expect(driver.contains("Self.redactedApplicationDescription(value)"))
        #expect(driver.contains("private static func redactKnownSecretValues(in text: String) -> String"))
        #expect(driver.contains("sanitized[custodyKey] = \"<redacted>\""))
        #expect(driver.contains("onApplicationUpdate?(sanitized)"))
        #expect(!driver.contains("sanitized[String(describing: key)] = String(describing: value)"))
    }

    @Test("export redaction claim remains coupled to the application-event path")
    func exportRedactionClaimIncludesApplicationEvents() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))
        let updates = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(export.contains("secretsRedacted: true"))
        #expect(updates.contains("let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)"))
        #expect(updates.contains("var eventDetails = custodySafeUpdate"))
        #expect(updates.contains("eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        #expect(updates.contains("log(\"tuya_application_update\", eventDetails)"))
        #expect(!updates.contains("update.merging(["))
        #expect(source.contains("No account UID, AppKey/AppSecret, password, account token, local_key, session key"))
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