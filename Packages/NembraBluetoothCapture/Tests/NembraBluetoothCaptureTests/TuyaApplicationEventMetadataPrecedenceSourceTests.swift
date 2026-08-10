import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWinsReservedKeyCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let custody = String(try section(
            in: source,
            from: "private func makeApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("log(\"tuya_application_update\", eventDetails)"))
        #expect(!receiver.contains("update.merging(["))
        #expect(custody.contains("eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        #expect(custody.contains("var eventDetails: [String: String] = [:]"))
        #expect(custody.contains("eventDetails[redactedKey] = redactedValue"))
        #expect(custody.range(of: "eventDetails[redactedKey] = redactedValue")!.lowerBound < custody.range(of: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)")!.lowerBound)
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
