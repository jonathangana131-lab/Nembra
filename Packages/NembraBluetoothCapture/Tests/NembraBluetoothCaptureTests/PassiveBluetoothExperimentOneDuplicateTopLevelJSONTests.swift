import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneDuplicateTopLevelJSONTests {
    @Test
    func finalShareRejectsDuplicateTopLevelKeyBeforeFoundationDecode() {
        let data = Data(#"{"schemaVersion":1,"schemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsDuplicateTopLevelKeyBeforeFoundationDecode() {
        let data = Data(#"{"experimentRecipeID":"ES80-FINGERPRINT-v1","experimentRecipeID":"ES80-FINGERPRINT-v1"}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("experimentRecipeID")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
