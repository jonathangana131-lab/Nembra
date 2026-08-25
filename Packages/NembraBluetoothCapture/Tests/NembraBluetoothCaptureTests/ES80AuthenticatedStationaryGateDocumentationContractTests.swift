import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 authenticated stationary gate documentation contract")
struct ES80AuthenticatedStationaryGateDocumentationContractTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture package root
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository root
    }

    private static func document(_ name: String) throws -> String {
        let url = repositoryRoot()
            .appendingPathComponent("docs")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("stationary gate prose cannot weaken the compiled authenticated preflight")
    func stationaryGateMatchesCompiledMinimums() throws {
        let gate = try Self.document("ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds == 30_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds == 45_000_000_000)

        #expect(gate.contains("`minimumAuthenticatedApplicationPayloadCount = 2`"))
        #expect(gate.contains("`minimumPostAuthenticationPayloadSurvivalNanoseconds = 30_000_000_000`"))
        #expect(gate.contains("`minimumAuthenticatedConnectionNanoseconds = 45_000_000_000`"))
        #expect(gate.contains("at least **two genuine non-empty application payloads**"))
        #expect(gate.contains("at least **30.0 seconds after authentication**"))
        #expect(gate.contains("at least **45.0 seconds after authentication**"))
    }

    @Test("physical predecessor points forward to the same strict gate")
    func physicalTruthDoesNotReintroduceObsoleteOnePayloadGate() throws {
        let physicalTruth = try Self.document("ES80_PHYSICAL_TRUTH_C7D09A22.md")

        #expect(physicalTruth.contains("at least **two** genuine, non-empty application payloads"))
        #expect(physicalTruth.contains("at least **30.0 seconds after authentication**"))
        #expect(physicalTruth.contains("at least **45.0 seconds after authentication**"))
        #expect(!physicalTruth.contains("acceptance boundary is strictly `>30.0 s` plus real notify payload evidence"))
    }
}
