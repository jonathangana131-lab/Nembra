import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One duplicate top-level JSON custody")
struct PassiveBluetoothDuplicateTopLevelJSONTests {
    @Test("final Share rejects duplicate digest authority before Foundation parser precedence")
    func finalShareRejectsDuplicateDigestMember() {
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

    @Test("nested SoftwareExport rejects duplicate recipe authority before Foundation parser precedence")
    func softwareExportRejectsDuplicateRecipeMember() {
        let data = Data(
            #"{"experimentRecipeID":"ES80-FINGERPRINT-v1","experimentRecipeID":"FORGED"}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("experimentRecipeID")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }

    @Test("semantic duplicate keys encoded with JSON escapes are still rejected")
    func escapedDuplicateKeyFailsClosed() {
        let data = Data(
            #"{"captureJSONBase64":"AA==","\u0063aptureJSONBase64":"AQ=="}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("captureJSONBase64")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
