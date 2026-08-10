import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event custody closure")
struct TuyaApplicationEventCustodyClosureSourceTests {
    @Test("Nembra generation provenance wins every SDK payload collision")
    func trustedGenerationWinsReservedCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = try applicationReceiver(in: source)

        #expect(receiver.contains("log(\"tuya_application_update\""))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("leased account UID is scrubbed from application keys and values before custody")
    func accountUIDCannotEnterAcceptedEventContent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = try applicationReceiver(in: source)

        #expect(receiver.contains("leasedAccountUID"))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("redactedKey"))
        #expect(receiver.contains("redactedValue"))
        #expect(receiver.contains("custodySafeUpdate"))
        #expect(receiver.components(separatedBy: "replacingOccurrences(").count - 1 >= 2)
        #expect(receiver.range(of: "custodySafeUpdate")!.lowerBound < receiver.range(of: "sessionLedger.recordApplicationUpdate")!.lowerBound)
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("UID custody is value-bound, preserves generic uid fields, and keeps classifier deduplicated")
    func accountUIDCustodyDoesNotBecomeBlanketUIDClassifier() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
        #expect(driver.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
    }

    @Test("post-redaction key collisions retain each opaque application entry")
    func keyRedactionCollisionCannotSilentlyDropEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = try applicationReceiver(in: source)

        #expect(receiver.contains("collisionOrdinal"))
        #expect(receiver.contains("while custodySafeUpdate[custodyKey] != nil"))
        #expect(receiver.contains("custodySafeUpdate[custodyKey] = redactedValue"))
    }

    private func applicationReceiver(in source: String) throws -> String {
        String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
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
