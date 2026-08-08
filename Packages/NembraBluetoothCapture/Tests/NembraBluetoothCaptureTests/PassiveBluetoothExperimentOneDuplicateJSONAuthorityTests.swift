import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneDuplicateJSONAuthorityTests {
    @Test
    func finalShareRejectsDuplicateTopLevelAuthorityKeyBeforeFoundationDecoding() {
        let ambiguous = Data(
            #"{"schemaVersion":1,"schemaVersion":1}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(ambiguous)
        }
    }

    @Test
    func softwareExportRejectsDuplicateTopLevelAuthorityKeyBeforeFoundationDecoding() {
        let ambiguous = Data(
            #"{"schemaVersion":1,"schemaVersion":1}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(ambiguous)
        }
    }

    @Test
    func finalShareReportsEscapedDuplicateKeyBySemanticName() {
        let ambiguous = Data(
            #"{"schemaVersion":1,"schema\u0056ersion":1}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(ambiguous)
        }
    }

    @Test
    func softwareExportReportsEscapedDuplicateKeyBySemanticName() {
        let ambiguous = Data(
            #"{"schemaVersion":1,"schema\u0056ersion":1}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(ambiguous)
        }
    }
}
