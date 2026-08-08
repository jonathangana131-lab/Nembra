import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothFinalShareJSONDuplicateAuthorityTests {
    @Test
    func finalShareRejectsDuplicateTopLevelAuthorityBeforeFoundationDecoding() {
        let data = Data(#"{"schemaVersion":1,"schemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsDuplicateTopLevelAuthorityBeforeFoundationDecoding() {
        let data = Data(#"{"schemaVersion":1,"schemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }

    @Test
    func finalShareRejectsEscapedEquivalentDuplicateAuthorityKey() {
        let data = Data(#"{"schemaVersion":1,"\u0073chemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsEscapedEquivalentDuplicateAuthorityKey() {
        let data = Data(#"{"schemaVersion":1,"\u0073chemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
