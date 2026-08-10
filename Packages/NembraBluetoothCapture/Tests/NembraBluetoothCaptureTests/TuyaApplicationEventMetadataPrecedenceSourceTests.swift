import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya accepted application-event provenance")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("trusted generation is package-owned without discarding colliding SDK evidence")
    func trustedGenerationWinsReservedCollisionLosslessly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))

        let custody = try #require(receiver.range(of: "TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        let generation = try #require(receiver.range(of: "trustedGeneration: String(token.diagnosticGeneration)", range: custody.upperBound..<receiver.endIndex))
        let ledger = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate", range: generation.upperBound..<receiver.endIndex))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", custodySafeEventDetails)", range: ledger.upperBound..<receiver.endIndex))
        #expect(custody.lowerBound < generation.lowerBound)
        #expect(generation.lowerBound < ledger.lowerBound)
        #expect(ledger.lowerBound < log.lowerBound)
        #expect(!receiver.contains("eventDetails[\"generation\"] ="))
        #expect(!receiver.contains("update.merging(["))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw Error.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    private enum Error: Swift.Error { case sectionMissing }
}
