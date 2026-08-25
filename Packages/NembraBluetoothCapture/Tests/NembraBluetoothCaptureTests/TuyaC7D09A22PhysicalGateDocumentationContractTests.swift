import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("C7D09A22 physical gate documentation contract")
struct TuyaC7D09A22PhysicalGateDocumentationContractTests {
    @Test("physical runbook cannot weaken the canonical authenticated preflight")
    func physicalRunbookMatchesCanonicalAuthenticatedPreflight() throws {
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds == 30_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds == 45_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds == 60_000_000_000)

        var repositoryRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            repositoryRoot.deleteLastPathComponent()
        }

        let runbookURL = repositoryRoot.appendingPathComponent("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        let runbook = try String(contentsOf: runbookURL, encoding: .utf8)

        #expect(runbook.contains("at least two real, non-empty application notification payloads"))
        #expect(runbook.contains("latest accepted application notification payload arrives at least `30.0 s` after authentication"))
        #expect(runbook.contains("authenticated continuity reaches at least `45.0 s` from authentication"))
        #expect(runbook.contains("package-owned `60.0 s` incomplete-observation horizon"))

        #expect(!runbook.contains("at least one real, non-empty application notification payload"))
        #expect(!runbook.contains("acceptance boundary is strictly `>30.0 s` plus real notify payload evidence"))
    }
}
