import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence scrubs verified account UID before immutable event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let export = String(try section(in: source, from: "func prepareExport()", to: "private func abandonPackageCorrelation()"))
        #expect(export.contains("No account UID"))
        #expect(receiver.contains("let verifiedAccountUID = membershipAccountUID?"))
        #expect(receiver.contains("scrubAccountUIDFromApplicationEvent"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("scrub is exact account-value bound and covers malformed UID-bearing keys without a blanket uid classifier")
    func valueBoundCustodyPreservesGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(in: source, from: "private func scrubAccountUIDFromApplicationEvent(", to: "private func startWatchdog"))
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(helper.contains("key.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("value.replacingOccurrences(of: verifiedAccountUID"))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    @Test("secret classifier keeps one session-key rule after custody convergence")
    func secretClassifierIsSimplified() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(driver.components(separatedBy: "\"sessionkey\",").count - 1 == 1)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
