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

        #expect(receiver.contains("log(\"tuya_application_update\""))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))

        // `update` is SDK-owned application evidence. Nembra-owned provenance must win
        // any collision before the event becomes accepted/exportable evidence.
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
    }

    @Test("reserved-key precedence changes no protocol or physical authority")
    func metadataRepairStaysEvidenceOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        for forbidden in ["publishDps", "queryDps", "writeValue", "disconnectBLE"] {
            #expect(!receiver.contains(forbidden), "Event metadata precedence must not add command authority: \(forbidden)")
        }
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
