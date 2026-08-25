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

    @Test("physical truth ledger no longer advertises the weaker one payload plus greater than 30 second gate")
    func physicalTruthLedgerMatchesCanonicalFloor() throws {
        let physicalTruth = try readRepositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")

        #expect(physicalTruth.contains("at least **two** genuine, non-empty application notification payloads"))
        #expect(physicalTruth.contains("latest accepted application payload arrives at least **30 seconds after authentication**"))
        #expect(physicalTruth.contains("continuously accepted for at least **45 seconds after authentication**"))
        #expect(!physicalTruth.contains("acceptance boundary is strictly `>30.0 s` plus real notify payload evidence"))
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
