import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya reserved application metadata custody")
struct TuyaApplicationReservedMetadataLosslessSourceTests {
    @Test("opaque SDK generation survives before trusted generation is stamped")
    func generationCollisionIsLosslessAndAuthoritySeparated() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("redactedKey == \"generation\""))
        #expect(helper.contains("? \"application.generation\""))
        #expect(helper.contains("var custodyKey = reservedCustodyKey"))
        #expect(helper.contains("\\(reservedCustodyKey)#\\(collisionOrdinal)"))
        #expect(helper.contains("update.sorted(by: { $0.key < $1.key })"))
        #expect(!helper.contains("diagnosticGeneration"))
        #expect(!helper.contains("currentConnectionToken"))
        #expect(receiver.contains("var eventDetails = custodySafeUpdate"))
        #expect(receiver.contains("eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
    }

    @Test("reserved namespace retains deterministic collision custody")
    func reservedNamespaceCollisionIsDeterministic() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))
        let sort = try #require(helper.range(of: "update.sorted(by: { $0.key < $1.key })"))
        let reserve = try #require(helper.range(of: "let reservedCustodyKey = redactedKey == \"generation\""))
        let collision = try #require(helper.range(of: "while redacted[custodyKey] != nil"))
        #expect(sort.lowerBound < reserve.lowerBound)
        #expect(reserve.lowerBound < collision.lowerBound)
        #expect(helper.contains("redacted[custodyKey] = redactedValue"))
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
