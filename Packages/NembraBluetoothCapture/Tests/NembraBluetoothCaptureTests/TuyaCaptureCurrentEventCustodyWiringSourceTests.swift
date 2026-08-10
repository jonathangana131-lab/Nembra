import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current event-custody wiring")
struct TuyaCaptureCurrentEventCustodyWiringSourceTests {
    @Test("accepted application events enter package custody before event logging")
    func applicationEventsCannotForgeProvenanceOrExportAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        #expect(receiver.contains("applicationUpdate: update"))
        #expect(receiver.contains("trustedGeneration: String(token.diagnosticGeneration)"))
        #expect(receiver.contains("accountUID: membershipAccountUID"))
        #expect(receiver.contains("log(\"tuya_application_update\", eventDetails)"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    @Test("driver secret classifier stays narrow while package custody owns exact UID redaction")
    func driverClassifierDoesNotBlanketEraseGenericUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "private final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let classifier = String(try section(
            in: driver,
            from: "private static let secretKeyFragments = [",
            to: "]\n\n    private static func redactApplicationSecrets"
        ))

        #expect(!classifier.contains("\"uid\""))
        #expect(classifier.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
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

    private enum SourceContractError: Error { case sectionMissing }
}
