import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 authenticated stationary gate authority")
struct TuyaPhysicalGateDocumentationSourceTests {
    @Test("field authority matches executable sustained application acceptance")
    func fieldAuthorityMatchesExecutableGate() throws {
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds == 30_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds == 45_000_000_000)

        let physicalTruth = try readRepositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        #expect(physicalTruth.contains("at least **two** genuine, non-empty application notification payloads"))
        #expect(physicalTruth.contains("at least **30 seconds after authentication**"))
        #expect(physicalTruth.contains("at least **45 seconds after authentication**"))
        #expect(!physicalTruth.contains("strictly `>30.0 s` plus real notify payload evidence"))

        let stationaryGate = try readRepositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")
        #expect(stationaryGate.contains("at least **two genuine non-empty application notification payloads**"))
        #expect(stationaryGate.contains("**latest accepted application payload is at least 30 seconds after authentication**"))
        #expect(stationaryGate.contains("at least **45 seconds of accepted authenticated continuity after authentication**"))
        #expect(!stationaryGate.contains("at least **one genuine non-empty application notification payload**"))
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
