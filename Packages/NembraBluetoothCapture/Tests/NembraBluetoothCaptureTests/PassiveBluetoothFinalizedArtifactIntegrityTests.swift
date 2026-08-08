import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Finalized Capture artifact integrity")
struct PassiveBluetoothFinalizedArtifactIntegrityTests {
    @Test
    func sha256IsDeterministicOverExactBytes() {
        let data = Data("abc".utf8)

        #expect(
            PassiveBluetoothFinalizedArtifactIntegrity.sha256Hex(of: data)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test
    func malformedBytesDoNotEarnAnalysisReadyReport() {
        let malformed = Data("{not-valid-capture-json".utf8)

        #expect(throws: (any Error).self) {
            _ = try PassiveBluetoothFinalizedArtifactIntegrity.inspect(malformed)
        }
    }
}
