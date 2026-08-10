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

        #expect(installer.contains("Verifying the intended iPhone 12 / iOS 27 baseline"))
        #expect(installer.contains("MATCH_COUNT=0"))
        #expect(installer.contains("ROW_NORMALIZED"))
        #expect(installer.contains("INTENDED_NORMALIZED"))
        #expect(installer.contains("$MATCH_COUNT\" == \"1"))
        #expect(installer.contains("No arbitrary-device fallback is permitted"))
    }

    @Test("private intended device must also be the exact V14 hardware and OS baseline")
    func intendedDeviceMustBeIPhone12OnIOS27() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("DEVICE_OS_VERSION"))
        #expect(installer.contains("$DEVICE_OS_VERSION\" == 27.*"))
        #expect(installer.contains("iPhone13,2"))
        #expect(installer.contains("not the V14 iPhone 12 hardware baseline"))
        #expect(installer.contains("Intended baseline proven: iPhone 12 / iOS $DEVICE_OS_VERSION"))
    }

    @Test("devicectl uses a non-private CoreDevice selector correlated to the private UDID")
    func rawPrivateUDIDCannotEnterDevicectlArgv() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("devicectl list devices --hide-headers"))
        #expect(installer.contains(".coredevice.local"))
        #expect(installer.contains("COREDEVICE_ID"))
        #expect(installer.contains("devicectl device install app --device \"$COREDEVICE_ID\""))
        #expect(installer.contains("devicectl device process launch"))
        #expect(installer.contains("--device \"$COREDEVICE_ID\""))
        #expect(!installer.contains("devicectl device install app --device \"$DEVICE_UDID\""))
        #expect(!installer.contains("--device \"$DEVICE_UDID\""))
        #expect(installer.contains("not placed in devicectl argv"))
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

    @Test("exact built device app provenance is read back before installation")
    func builtArtifactMustMatchRequestedSourceAndFieldProduct() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let readbackRange = try requiredRange(
            in: installer,
            from: "APP_INFO_PLIST=\"$APP/Info.plist\"",
            to: "say \"Installing SDK-integrated Capture on the intended iPhone\""
        )
        let readback = installer[readbackRange]

        #expect(installer.contains("[[ -x /usr/bin/plutil ]]"))
        #expect(readback.contains("NembraCaptureBuildIdentifier"))
        #expect(readback.contains("NembraCaptureSourceCommitSHA"))
        #expect(readback.contains("CFBundleIdentifier"))
        #expect(readback.contains("$BUILT_BUILD_IDENTIFIER\" == \"$BUILD_LABEL"))
        #expect(readback.contains("$BUILT_SOURCE_SHA\" == \"$SOURCE_SHA"))
        #expect(readback.contains("$BUILT_BUNDLE_ID\" == \"$BUNDLE_ID"))
        #expect(readback.contains("Built app provenance matched exact requested source and field product"))
    }

    @Test("installer does not echo the private device identifier through normal diagnostics")
    func deviceIdentifierStaysOutOfNembraPresentation() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("<redacted-device>"))
        #expect(installer.contains("<redacted-device-selector>"))
        #expect(installer.contains("unset DEVICE_UDID COREDEVICE_ID"))
        #expect(installer.contains("process launch"))
        #expect(installer.contains(">$INSTALL_LOG 2>&1"))
        #expect(!installer.contains("cat \"$INSTALL_LOG\""))
        #expect(!installer.contains("say \"Found $DEVICE_UDID\""))
        #expect(!installer.contains("printf '%s\\n' \"$DEVICE_UDID\""))
    }

    private func requiredRange(in source: String, from start: String, to end: String) throws -> Range<String.Index> {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return startRange.lowerBound..<endRange.lowerBound
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
