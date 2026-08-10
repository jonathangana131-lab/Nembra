import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer intended-device authority")
struct TuyaFieldInstallerIntendedDeviceAuthoritySourceTests {
    @Test("installer reads one private intended-device identity through the hardened reader")
    func intendedDeviceIdentityCannotComeFromAmbientSelection() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"))
        #expect(installer.contains("unset NEMBRA_INTENDED_FIELD_DEVICE_UDID"))
        #expect(installer.contains("es80_signed_field_artifact_private_runner.py"))
        #expect(installer.contains("read_private_identifier"))
        #expect(installer.contains("Private intended-device admission validated"))
        #expect(!installer.contains("Choose iPhone number"))
        #expect(!installer.contains("DEVICE_COUNT"))
    }

    @Test("connected-device discovery must match the private intended iPhone exactly once")
    func arbitraryConnectedIPhoneCannotBecomeTheFieldDevice() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("Verifying the intended iPhone is physically connected"))
        #expect(installer.contains("MATCH_COUNT=0"))
        #expect(installer.contains("ROW_NORMALIZED"))
        #expect(installer.contains("INTENDED_NORMALIZED"))
        #expect(installer.contains("$MATCH_COUNT\" == \"1"))
        #expect(installer.contains("No arbitrary-device fallback is permitted"))
        #expect(installer.contains("devicectl device install app --device \"$DEVICE_UDID\""))
        #expect(installer.contains("devicectl device process launch"))
    }

    @Test("private workspace and build cannot silently change the accepted source")
    func exactSourceIsRecheckedAroundPrivateBuild() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA"))
        #expect(installer.contains("Repository HEAD changed during private workspace bootstrap"))
        #expect(installer.contains("Private workspace bootstrap changed tracked or unignored accepted-source inputs"))
        #expect(installer.contains("Repository HEAD changed while the accepted field build was compiling"))
        #expect(installer.contains("Accepted-source inputs changed while the field build was compiling"))
        #expect(installer.contains("NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA"))
        #expect(installer.contains("NembraCapture.xcworkspace"))
        #expect(installer.contains("-scheme \"Nembra Capture\""))
    }

    @Test("installer does not echo the private device identifier through normal diagnostics")
    func deviceIdentifierStaysOutOfNembraPresentation() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("<redacted-device>"))
        #expect(installer.contains("unset DEVICE_UDID"))
        #expect(installer.contains("process launch"))
        #expect(installer.contains(">$INSTALL_LOG 2>&1"))
        #expect(!installer.contains("cat \"$INSTALL_LOG\""))
        #expect(!installer.contains("say \"Found $DEVICE_UDID\""))
        #expect(!installer.contains("printf '%s\\n' \"$DEVICE_UDID\""))
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
