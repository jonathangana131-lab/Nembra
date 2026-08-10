import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya accepted application-event provenance")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("trusted Nembra generation is stamped after untrusted event redaction")
    func trustedGenerationWinsReservedCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let redaction = try #require(receiver.range(of: "var eventDetails = redactedApplicationEventDetails(update)"))
        let generation = try #require(receiver.range(of: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventDetails)"))
        #expect(redaction.lowerBound < generation.lowerBound)
        #expect(generation.lowerBound < log.lowerBound)
        #expect(!receiver.contains("update.merging(["))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
