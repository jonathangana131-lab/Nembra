import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence scrubs exact verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try repositorySource()
        let admission = String(try section(source, "private func receivedApplicationUpdate(", "private func startWatchdog"))
        let export = String(try section(source, "func prepareExport()", "private func abandonPackageCorrelation()"))
        #expect(export.contains("No account UID"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(admission.contains("verifiedAccountUID"))
        #expect(admission.contains("scrubAccountUIDFromApplicationEvent"))
        #expect(!admission.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("UID scrub is exact-value-bound rather than a generic uid-key rule")
    func valueBoundScrub() throws {
        let source = try repositorySource()
        let helper = String(try section(source, "private func scrubAccountUIDFromApplicationEvent(", "private func startWatchdog"))
        let driver = String(try section(source, "@MainActor\nprivate final class SmartLifeDriver", "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(helper.contains("key.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("value.replacingOccurrences(of: verifiedAccountUID"))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    private func section(_ text: String, _ start: String, _ end: String) throws -> Substring {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { throw SourceError.missing }
        return text[a.lowerBound..<b.lowerBound]
    }

    private func repositorySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
