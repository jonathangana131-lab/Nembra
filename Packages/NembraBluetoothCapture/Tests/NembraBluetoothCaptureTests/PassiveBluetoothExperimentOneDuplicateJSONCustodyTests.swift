import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One final-share duplicate JSON custody")
struct PassiveBluetoothExperimentOneDuplicateJSONCustodyTests {
    @Test("outer final Share rejects duplicate top-level semantic fields before Foundation decoding")
    func finalShareRejectsDuplicateTopLevelField() throws {
        let duplicate = Data(#"{"schemaVersion":1,"schemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(duplicate)
        }
    }

    @Test("nested SoftwareExport rejects duplicate top-level semantic fields before Foundation decoding")
    func softwareExportRejectsDuplicateTopLevelField() throws {
        let duplicate = Data(#"{"schemaVersion":1,"schemaVersion":1}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(duplicate)
        }
    }
}
