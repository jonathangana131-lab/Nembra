import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One duplicate top-level JSON custody")
struct PassiveBluetoothExperimentOneDuplicateTopLevelJSONTests {
    @Test("final Share rejects duplicate procedure authority before unknown-field parsing")
    func finalShareDuplicateProcedureVersionFailsClosedFirst() {
        let data = Data(
            #"{"procedureVersion":"V14","procedureVersion":"FORGED","unexpected":true}"#.utf8
        )

        #expect(throws: PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData) {
            try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test("SoftwareExport rejects duplicate recipe authority before unknown-field parsing")
    func softwareExportDuplicateRecipeFailsClosedFirst() {
        let data = Data(
            #"{"experimentRecipeID":"ES80-FINGERPRINT-v1","experimentRecipeID":"FORGED","unexpected":true}"#.utf8
        )

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData) {
            try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
