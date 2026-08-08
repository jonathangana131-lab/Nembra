import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneDuplicateTopLevelJSONAuthorityTests {
    @Test
    func finalShareRejectsDuplicateTopLevelKeyBeforeSchemaValidation() {
        let data = Data(#"{"schemaVersion":999,"schemaVersion":999,"artifactKind":"unused","experimentID":"unused","experimentRecipeID":"unused","procedureVersion":"unused","buildInstanceID":"unused","softwareExportSHA256":"unused","softwareExportJSONBase64":"unused"}"#.utf8)

        let observed: PassiveBluetoothExperimentOneFinalShareArtifactError? = {
            do {
                _ = try PassiveBluetoothExperimentOneFinalShareArtifactCodec.decodeAndVerify(data)
                return nil
            } catch let error as PassiveBluetoothExperimentOneFinalShareArtifactError {
                return error
            } catch {
                return nil
            }
        }()

        #expect(observed == .malformedWireData)
    }

    @Test
    func softwareExportRejectsDuplicateTopLevelKeyBeforeSchemaValidation() {
        let data = Data(#"{"schemaVersion":999,"schemaVersion":999,"experimentRecipeID":"unused","captureJSONBase64":"","stationaryManifestJSONBase64":"","correlationWindows":[],"build":{"buildIdentifier":"unused","buildInstanceID":"unused","sourceCommitSHA":"unused","executableSHA256":"unused"}}"#.utf8)

        let observed: PassiveBluetoothExperimentOneSoftwareExportError? = {
            do {
                _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(data)
                return nil
            } catch let error as PassiveBluetoothExperimentOneSoftwareExportError {
                return error
            } catch {
                return nil
            }
        }()

        #expect(observed == .malformedWireData)
    }
}
