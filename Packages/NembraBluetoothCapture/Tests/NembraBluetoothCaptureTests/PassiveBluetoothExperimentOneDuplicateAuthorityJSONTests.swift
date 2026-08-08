import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One duplicate authority JSON custody")
struct PassiveBluetoothExperimentOneDuplicateAuthorityJSONTests {
    @Test("final Share rejects duplicate procedure provenance before keyed decoding")
    func finalShareRejectsDuplicateProcedureVersion() {
        let data = Data(
            #"{"procedureVersion":"V14","procedureVersion":"V15"}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("procedureVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test("final Share rejects duplicate digest authority before keyed decoding")
    func finalShareRejectsDuplicateSoftwareExportDigest() {
        let data = Data(
            #"{"softwareExportSHA256":"a","softwareExportSHA256":"b"}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("softwareExportSHA256")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test("SoftwareExport rejects duplicate recipe authority before keyed decoding")
    func softwareExportRejectsDuplicateRecipe() {
        let data = Data(
            #"{"experimentRecipeID":"ES80-FINGERPRINT-v1","experimentRecipeID":"forged"}"#.utf8
        )

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("experimentRecipeID")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }

    @Test("SoftwareExport rejects duplicate build authority before keyed decoding")
    func softwareExportRejectsDuplicateBuild() {
        let data = Data(#"{"build":{},"build":{}}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("build")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}