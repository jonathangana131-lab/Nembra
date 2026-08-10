import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer authority")
struct TuyaFieldInstallerIntendedDeviceAuthoritySourceTests {
    @Test("installer binds the build to one exact software-accepted source")
    func acceptedSourceCannotBeReplacedByBranchNamesOrAmbientCheckout() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("EXPECTED_SOURCE_SHA"))
        #expect(installer.contains("NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA"))
        #expect(installer.contains("Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA"))
        #expect(installer.contains("NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA"))
        #expect(installer.contains("git status --porcelain=v1 --untracked-files=all"))
        #expect(!installer.contains("capture/one-time-ble-dump-gpt56"))
    }

    @Test("installer admits only the privately named intended iPhone")
    func arbitraryConnectedIPhoneCannotBecomeTheFieldDevice() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"))
        #expect(installer.contains("es80_signed_field_artifact_private_runner.py"))
        #expect(installer.contains("--validate-intended-device-udid-file"))
        #expect(installer.contains("--repository-root \"$ROOT\""))
        #expect(installer.contains("if [[ \"$ROW_UDID\" == \"$DEVICE_UDID\" ]]"))
        #expect(installer.contains("$MATCH_COUNT\" == \"1"))
        #expect(installer.contains("No arbitrary-device fallback is permitted"))
        #expect(installer.contains("devicectl device install app --device \"$DEVICE_UDID\""))
        #expect(installer.contains("devicectl device process launch"))
        #expect(!installer.contains("Choose iPhone number"))
        #expect(!installer.contains("DEVICE_COUNT"))
    }

    @Test("installer builds only the private standalone Capture workspace and keeps secrets off launch argv")
    func fieldProductAndSecretBoundaryStayExplicit() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("Scripts/bootstrap_capture_tuya_sdk.sh"))
        #expect(installer.contains("NembraCapture.xcworkspace"))
        #expect(installer.contains("-scheme \"Nembra Capture\""))
        #expect(installer.contains("com.jonathangana131.nembra.capturelearn"))
        #expect(installer.contains("unset NEMBRA_TUYA_APP_KEY NEMBRA_TUYA_APP_SECRET"))
        #expect(installer.contains("Private workspace bootstrap changed tracked/unignored accepted-source inputs"))
        #expect(installer.contains("Accepted-source inputs changed while the field build was compiling"))
        #expect(!installer.contains("--environment-variables"))
        #expect(!installer.contains("NEMBRA_TUYA_APP_KEY=$"))
        #expect(!installer.contains("NEMBRA_TUYA_APP_SECRET=$"))
    }

    @Test("operator instructions match the accepted four-window confirmation procedure")
    func launchInstructionsCannotRegressToTwoWindowHintAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(installer.contains("Fresh manager scan = Live"))
        #expect(installer.contains("exactly one repeatable full CoreBluetooth target"))
        #expect(installer.contains("Historical UUID, FD50, Tuya/name/RSSI hints cannot override that result"))
        #expect(installer.contains("Confirm correlated Bluetooth target"))
        #expect(installer.contains("genuine same-generation non-empty dpsUpdate"))
        #expect(installer.contains("canonical continuity of at least 45 seconds"))
        #expect(installer.contains("immutable accepted seal/export"))
        #expect(installer.contains("No outdoor ride is authorized by this installer"))

        #expect(!installer.contains("run the scooter-OFF baseline, power it ON"))
        #expect(!installer.contains("select the authoritative target"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
