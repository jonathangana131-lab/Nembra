import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 authenticated stationary gate authority")
struct TuyaPhysicalGateDocumentationSourceTests {
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

    @Test("field procedure cannot weaken executable sustained application acceptance")
    func fieldProcedureMatchesExecutableGate() throws {
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                == 30_000_000_000
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
                == 45_000_000_000
        )

        let physicalTruth = try repositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        #expect(physicalTruth.contains("at least **2** genuine, non-empty application updates"))
        #expect(physicalTruth.contains("at least **30.0 seconds after authentication**"))
        #expect(physicalTruth.contains("at least **45.0 seconds after authentication**"))
        #expect(!physicalTruth.contains("strictly `>30.0 s` plus real notify payload evidence"))

        let stationaryGate = try repositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")
        #expect(stationaryGate.contains("at least **two genuine non-empty application notification payloads**"))
        #expect(stationaryGate.contains("**latest accepted application payload is at least 30 seconds after authentication**"))
        #expect(stationaryGate.contains("at least **45 seconds of accepted authenticated continuity after authentication**"))
        #expect(!stationaryGate.contains("at least **one genuine non-empty application notification payload**"))

        let secureLink = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        #expect(secureLink.contains("at least two genuine non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate` callbacks"))
        #expect(secureLink.contains("latest application evidence occurs at least 30 seconds after SDK authentication"))
        #expect(secureLink.contains("at least 45 seconds of canonical authenticated observation"))
    }
}
