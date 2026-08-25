import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya physical-truth gate documentation")
struct TuyaPhysicalTruthGateDocumentationTests {
    @Test("C7D09A22 handoff cannot weaken the shipping authenticated preflight")
    func c7d09a22HandoffMatchesShippingPreflightThresholds() throws {
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds == 30_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds == 45_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds == 60_000_000_000)

        let physicalTruth = try readRepositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")

        #expect(physicalTruth.contains("official SmartLife App SDK for the current BLE generation"))
        #expect(physicalTruth.contains("at least **2** genuine, non-empty application updates"))
        #expect(physicalTruth.contains("at least **30.0 seconds after authentication**"))
        #expect(physicalTruth.contains("at least **45.0 seconds after authentication**"))
        #expect(physicalTruth.contains("package-owned 60-second observation horizon"))
        #expect(physicalTruth.contains("one bootstrap replay cannot mint readiness"))
        #expect(physicalTruth.contains("documentation must not authorize stationary mapping before the runtime itself can return `readyForStationaryMapping`"))

        #expect(!physicalTruth.contains("strictly `>30.0 s` plus real notify payload evidence"))
        #expect(!physicalTruth.contains("at least one real, non-empty application notification payload is received from the selected scooter"))
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
