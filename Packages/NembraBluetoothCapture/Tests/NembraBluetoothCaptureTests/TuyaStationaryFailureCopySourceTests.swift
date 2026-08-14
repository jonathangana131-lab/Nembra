import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture stationary-only failure recovery copy")
struct TuyaStationaryFailureCopySourceTests {
    @Test("post-handoff failures require relaunch and a new stationary read-only attempt")
    func postHandoffFailureCopyStaysStationaryOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        ))

        #expect(!controller.contains("ride capture"))
        #expect(!controller.contains("outdoor ride"))

        let recovery = "Export diagnostics; relaunch Capture before any new stationary read-only attempt."
        #expect(controller.components(separatedBy: recovery).count - 1 == 2)
    }

    @Test("official Tuya handoff makes bare OFF1 restart copy invalid")
    func officialHandoffRecoveryRequiresRelaunch() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let postHandoff = String(try section(
            in: source,
            from: "private func beginOfficialConnection(candidate: Candidate)",
            to: "private protocol OfficialTuyaDriver"
        ))

        #expect(!postHandoff.lowercased().contains("restart from off1"))

        let required = [
            "Source authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only.",
            "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
            "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
            "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Relaunch Capture before a new stationary read-only attempt; do not rebuild accepted evidence from mutable post-seal state."
        ]
        for message in required {
            #expect(postHandoff.contains(message), "missing relaunch-required post-handoff recovery: \(message)")
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
