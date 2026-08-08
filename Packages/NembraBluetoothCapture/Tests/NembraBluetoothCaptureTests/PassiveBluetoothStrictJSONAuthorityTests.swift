import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothStrictJSONAuthorityTests {
    @Test
    func topLevelDuplicateKeyIsDetectedBeforeFoundationPrecedence() {
        let data = Data(#"{"procedureVersion":"V14","procedureVersion":"V15"}"#.utf8)

        #expect(PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) == "procedureVersion")
        #expect(PassiveBluetoothStrictJSON.duplicateObjectKeyAtAnyDepth(in: data) == "procedureVersion")
    }

    @Test
    func nestedDuplicateKeyIsDetectedOnlyByRecursiveAuthorityScan() {
        let data = Data(#"{"build":{"buildIdentifier":"first","buildIdentifier":"second"}}"#.utf8)

        #expect(PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) == nil)
        #expect(PassiveBluetoothStrictJSON.duplicateObjectKeyAtAnyDepth(in: data) == "buildIdentifier")
    }

    @Test
    func sameKeyInDistinctSiblingObjectsIsNotAFalseDuplicate() {
        let data = Data(#"{"correlationWindows":[{"phase":0},{"phase":1}]}"#.utf8)

        #expect(PassiveBluetoothStrictJSON.duplicateObjectKeyAtAnyDepth(in: data) == nil)
    }

    @Test
    func escapedKeySpellingUsesDecodedSemanticIdentity() {
        let data = Data(#"{"procedureVersion":"V14","procedure\u0056ersion":"V15"}"#.utf8)

        #expect(PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) == "procedureVersion")
    }

    @Test
    func finalShareRejectsDuplicateTopLevelAuthorityBeforeDecode() {
        let data = Data(#"{"procedureVersion":"V14","procedureVersion":"V15"}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneFinalShareArtifactError
                .duplicateWireField("procedureVersion")
        ) {
            _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsDuplicateTopLevelAuthorityBeforeDecode() {
        let data = Data(#"{"experimentRecipeID":"ES80-FINGERPRINT-v1","experimentRecipeID":"forged"}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("experimentRecipeID")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsNestedBuildDuplicateBeforeFoundationCollapse() {
        let data = Data(#"{"build":{"buildIdentifier":"first","buildIdentifier":"second"}}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("buildIdentifier")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }

    @Test
    func softwareExportRejectsNestedCandidateDuplicateBeforeFoundationCollapse() {
        let data = Data(#"{"correlationWindows":[{"candidates":[{"peripheralIdentifier":"first","peripheralIdentifier":"second"}]}]}"#.utf8)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .duplicateWireField("peripheralIdentifier")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
        }
    }
}
