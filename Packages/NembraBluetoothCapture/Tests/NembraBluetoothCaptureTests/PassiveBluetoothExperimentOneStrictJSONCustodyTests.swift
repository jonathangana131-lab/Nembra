import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneStrictJSONCustodyTests {
    @Test
    func finalShareRejectsDuplicateTopLevelSemanticKeyBeforeFoundationDecoding() {
        let data = Data(#"{"schemaVersion":1,"schemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsDuplicateTopLevelSemanticKeyBeforeFoundationDecoding() {
        let data = Data(#"{"schemaVersion":1,"schemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
