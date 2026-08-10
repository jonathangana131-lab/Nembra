import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event custody convergence")
struct TuyaApplicationEventCustodyConvergenceSourceTests {
    @Test("accepted application evidence scrubs exact verified account UID before immutable event custody")
    func accountUIDCannotEnterAcceptedApplicationEvent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let receiver = String(try section(
            in: controller,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(source.contains("<redacted-account-uid>"))
        #expect(receiver.contains("verifiedAccountUID"))
        #expect(receiver.contains("redactVerifiedAccountUID"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))

        let helper = String(try section(
            in: controller,
            from: "private func redactVerifiedAccountUID(",
            to: "private func startWatchdog"
        ))
        #expect(helper.contains("key.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("value.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("<redacted-account-uid>"))
    }

    @Test("Nembra generation provenance wins SDK key collision")
    func trustedGenerationWinsCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("secret classifier is simplified without blanket generic uid erasure")
    func secretClassifierRemainsValueAwareForAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        #expect(driver.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
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
