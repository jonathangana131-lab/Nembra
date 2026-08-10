import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence redacts verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let helper = String(try section(in: source, from: "private func redactVerifiedAccountUIDFromApplicationEvent(", to: "private func receivedApplicationUpdate("))
        let export = String(try section(in: source, from: "func prepareExport()", to: "private func abandonPackageCorrelation()"))

        #expect(export.contains("No account UID"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(receiver.contains("let verifiedAccountUID = membershipAccountUID"))
        #expect(receiver.contains("let redactedUpdate = redactVerifiedAccountUIDFromApplicationEvent("))
        #expect(receiver.contains("log(\"tuya_application_update\", redactedUpdate.merging(["))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
        #expect(helper.contains("replacingOccurrences"))
        #expect(helper.contains("options: [.caseInsensitive, .literal]"))
        #expect(helper.contains("redacted[redact(key)] = redact(value)"))
    }

    @Test("account UID custody is value-bound rather than blanket generic uid-key classification")
    func accountUIDCustodyDoesNotEraseGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
