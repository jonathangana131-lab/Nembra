import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated physical acceptance contract")
struct TuyaAuthenticatedAcceptanceContractSourceTests {
    @Test("mechanical preflight pins the 2 payload / 30 second late payload / 45 second continuity floor")
    func mechanicalGateMatchesCanonicalAcceptanceFloor() throws {
        let preflight = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift"
        )

        #expect(preflight.contains("minimumAuthenticatedApplicationPayloadCount = 2"))
        #expect(preflight.contains("minimumPostAuthenticationPayloadSurvivalNanoseconds: UInt64 = 30_000_000_000"))
        #expect(preflight.contains("minimumAuthenticatedConnectionNanoseconds: UInt64 = 45_000_000_000"))
        #expect(preflight.contains("latestPayload - authenticatedAt >= minimumPostAuthenticationPayloadSurvivalNanoseconds"))
        #expect(preflight.contains("latest - authenticatedAt >= minimumAuthenticatedConnectionNanoseconds"))
    }

    @Test("field app consumes the canonical preflight verdict at acceptance")
    func fieldAppConsumesCanonicalVerdict() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("TuyaAuthenticatedReadOnlyPreflight.verdict"))
        #expect(app.contains("case .readyForStationaryMapping:"))
    }

    @Test("physical truth ledger remains no weaker than the mechanical gate")
    func physicalTruthLedgerMatchesCanonicalFloor() throws {
        let physicalTruth = try readRepositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")

        #expect(physicalTruth.contains("at least **2** genuine, non-empty application updates"))
        #expect(physicalTruth.contains("**latest** accepted application update arrives at least **30.0 seconds after authentication**"))
        #expect(physicalTruth.contains("authenticated continuity reaches at least **45.0 seconds after authentication**"))
        #expect(physicalTruth.contains("no weaker than shipping `TuyaAuthenticatedReadOnlyPreflight`"))
        #expect(!physicalTruth.contains("acceptance boundary is strictly `>30.0 s` plus real notify payload evidence"))
    }

    @Test("stationary runbook uses the same canonical PASS floor and removes stale donor archaeology")
    func stationaryRunbookMatchesCanonicalFloor() throws {
        let runbook = try readRepositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(runbook.contains("At least **2** genuine, non-empty authenticated application updates"))
        #expect(runbook.contains("**latest** accepted application update arrived at least **30 seconds after authentication**"))
        #expect(runbook.contains("at least **45 seconds after authentication**"))
        #expect(runbook.contains("A single bootstrap callback is insufficient."))
        #expect(runbook.contains("Live GitHub wins over stale snapshots."))
        #expect(!runbook.contains("at least **one genuine non-empty application notification payload**"))
        #expect(!runbook.contains("with a target of at least **45 seconds**"))
        #expect(!runbook.contains("obsolete app-authority parent"))
    }

    @Test("canonical documentation explicitly rejects weaker historical prose")
    func canonicalDocumentationPinsPrecedence() throws {
        let contract = try readRepositoryFile("docs/ES80_AUTHENTICATED_ACCEPTANCE_CONTRACT_V14.md")

        #expect(contract.contains("minimumAuthenticatedApplicationPayloadCount = 2"))
        #expect(contract.contains("minimumPostAuthenticationPayloadSurvivalNanoseconds = 30_000_000_000"))
        #expect(contract.contains("minimumAuthenticatedConnectionNanoseconds = 45_000_000_000"))
        #expect(contract.contains("A single bootstrap callback is insufficient."))
        #expect(contract.contains("Any older sentence in that file that describes one payload or treats 45 seconds as guidance-only is superseded"))
        #expect(contract.contains("does not itself flip the experiment to GO"))
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
}
