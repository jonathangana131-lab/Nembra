import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One duplicate top-level JSON key rejection")
struct PassiveBluetoothExperimentOneDuplicateTopLevelKeyTests {
    @Test("final Share rejects duplicate authority keys before Foundation decode")
    func finalShareRejectsDuplicateTopLevelKey() {
        let data = Data(#"{"schemaVersion":1,"schemaVersion":2}"#.utf8)

        #expect(throws: PassiveBluetoothExperimentOneFinalShareArtifactError.malformedWireData) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test("SoftwareExport rejects duplicate authority keys before Foundation decode")
    func softwareExportRejectsDuplicateTopLevelKey() {
        let data = Data(#"{"schemaVersion":1,"schemaVersion":2}"#.utf8)

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
