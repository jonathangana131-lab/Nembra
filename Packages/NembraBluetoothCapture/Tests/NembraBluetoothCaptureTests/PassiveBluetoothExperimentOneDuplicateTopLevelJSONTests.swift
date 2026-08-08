import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneDuplicateTopLevelJSONTests {
    @Test
    func finalShareRejectsDuplicateDigestAuthorityBeforeFoundationDecode() {
        let data = Data(
            #"{"softwareExportSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","softwareExportSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("softwareExportSHA256")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsDuplicateCaptureProvenanceBeforeFoundationDecode() {
        let data = Data(#"{"captureJSONBase64":"e30=","captureJSONBase64":"W10="}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("captureJSONBase64")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
