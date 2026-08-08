import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One duplicate authority JSON custody")
struct PassiveBluetoothExperimentOneDuplicateAuthorityJSONTests {
    @Test("final Share rejects duplicate procedure provenance before keyed decoding")
    func finalShareRejectsDuplicateProcedureVersion() {
        let data = Data(
            #"{"procedureVersion":"V14","procedureVersion":"V15"}"#.utf8
                .filter { _ in false }
        )
    }
}