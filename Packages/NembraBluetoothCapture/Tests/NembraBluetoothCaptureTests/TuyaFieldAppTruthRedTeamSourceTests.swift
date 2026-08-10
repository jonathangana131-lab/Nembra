import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-app truth red team")
struct TuyaFieldAppTruthRedTeamSourceTests {
    @Test("target authorization cannot be minted by display score, name, RSSI, or power-cycle hints")
    func targetAuthorizationUsesOnlyDeterministicEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let candidateStart = source.range(of: "struct Candidate:"),
              let phaseStart = source.range(of: "enum Phase:", range: candidateStart.upperBound..<source.endIndex) else {
            Issue.record("Expected Candidate and Phase declarations in the field entrypoint.")
            return
        }

        let candidate = String(source[candidateStart.lowerBound..<phaseStart.lowerBound])
        #expect(
            candidate.contains("knownID || (fd50 && tuyaCompany)"),
            "Only the exact previously observed CoreBluetooth UUID or corroborating FD50 + Tuya-company evidence may authorize the physical target."
        )
        #expect(
            !candidate.contains("score >="),
            "The score includes name/RSSI/power-cycle presentation hints and therefore cannot mint physical target authority."
        )
    }

    @Test("canonical preflight verdict is the sole acceptance authority")
    func noParallelPassBoolean() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for:"))
        #expect(
            !source.contains("var passed: Bool"),
            "Do not duplicate the canonical physical acceptance authority with an app-local pass boolean, even if the local boolean currently delegates to the verdict."
        )
    }

    @Test("SDK callback projection stays explicitly distinct from raw FD50 bytes")
    func sdkApplicationEvidenceIsNotRawTransport() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("rawFD50BytesCaptured: false"))
        #expect(source.contains("not raw FD50"))
    }

    @Test("post-discovery BLE ownership remains exclusively with Tuya SDK")
    func oneBLEOwnerAfterDiscovery() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(!source.contains("central.connect("))
        #expect(!source.contains("writeValue("))
        #expect(source.contains("ThingSmartBLEManager.sharedInstance().connectBLE"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
