import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated physical gate contract consistency")
struct TuyaAuthenticatedPhysicalGateContractConsistencyTests {
    private var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            root.deleteLastPathComponent()
        }
        return root
    }

    private func repositoryFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("physical handoffs cannot weaken the canonical authenticated application gate")
    func physicalHandoffsMatchCanonicalPreflight() throws {
        let physicalTruth = try repositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        let stationaryGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                == 30_000_000_000
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
                == 45_000_000_000
        )

        for document in [physicalTruth, stationaryGate] {
            #expect(document.contains("at least **2**"))
            #expect(document.contains("at least 30.0 seconds after authentication"))
            #expect(document.contains("at least **45.0 seconds**"))
        }

        #expect(physicalTruth.contains("A single bootstrap/state-replay payload is not enough."))
        #expect(stationaryGate.contains("one bootstrap/state-replay callback cannot close the gate"))
    }
}
