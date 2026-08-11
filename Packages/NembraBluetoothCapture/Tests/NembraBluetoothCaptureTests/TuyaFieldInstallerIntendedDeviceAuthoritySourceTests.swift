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

    @Test("intended-device identity is bound to Final GO digest before device discovery")
    func intendedDeviceIdentityMustMatchFinalGoDigest() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"))
        #expect(installer.contains("hashlib.sha256(value.encode(\"utf-8\")).hexdigest()"))
        #expect(installer.contains("hmac.compare_digest(actual_digest, expected_digest)"))
        #expect(installer.contains("private intended-device identifier does not match Final GO authority"))
        #expect(installer.contains("unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"))
        let digestCheck = installer.range(of: "hmac.compare_digest(actual_digest, expected_digest)")
        let deviceDiscovery = installer.range(of: "Verifying the intended iPhone 12 / iOS 27 baseline")
        #expect(digestCheck != nil)
        #expect(deviceDiscovery != nil)
        if let digestCheck, let deviceDiscovery {
            #expect(digestCheck.lowerBound < deviceDiscovery.lowerBound)
        }
    }

    @Test("accepted source carries the hardened private intended-device reader")
    func privateDeviceReaderExistsAndFailsClosed() throws {
        let helper = try readRepositoryFile("scripts/ci/es80_signed_field_artifact_private_runner.py")

        #expect(helper.contains("def read_private_identifier(path: Path, repository_root: Path) -> str"))
        #expect(helper.contains("O_NOFOLLOW"))
        #expect(helper.contains("O_DIRECTORY"))
        #expect(helper.contains("dir_fd=parent_descriptor"))
        #expect(helper.contains("must live outside the Nembra repository"))
        #expect(helper.contains("stat.S_ISREG"))
        #expect(helper.contains("metadata.st_mode & 0o077"))
        #expect(helper.contains("metadata.st_uid != os.geteuid()"))
        #expect(helper.contains("metadata.st_nlink != 1"))
        #expect(helper.contains("_stable_file_identity(final_metadata) != _stable_file_identity(metadata)"))
        #expect(helper.contains("value != value.strip()"))
        #expect(helper.contains("value in os.fspath(path)"))
    }

    @Test("field provenance executes the hardened private reader self-test")
    func fieldProvenanceExercisesPrivateDeviceCustody() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")

        #expect(workflow.contains("- scripts/ci/es80_signed_field_artifact_private_runner.py"))
        #expect(workflow.contains("/usr/bin/python3 -m py_compile scripts/ci/es80_signed_field_artifact_private_runner.py"))
        #expect(workflow.contains("/usr/bin/python3 -I scripts/ci/es80_signed_field_artifact_private_runner.py --self-test"))
        #expect(workflow.contains("github.event.pull_request.head.repo.full_name == github.repository"))
    }

    @Test("private build outputs are narrowly ignored while arbitrary untracked state remains rejected")
    func generatedPrivateWorkspaceDoesNotTripAcceptedSourceGuard() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let ignore = try readRepositoryFile(".gitignore")

        for expected in ["LocalSecrets/", "Pods/", "NembraCapture.xcworkspace/", "Podfile.lock"] {
            #expect(ignore.split(separator: "\n").contains(Substring(expected)))
        }
        #expect(installer.contains("verify_accepted_checkout_source()"))
        #expect(installer.contains("status --porcelain=v1 --untracked-files=no"))
        #expect(installer.contains("[\"/usr/bin/git\", \"ls-tree\", \"-r\", \"-z\", source_sha]"))
        #expect(installer.contains("field_input_directories = (\"LocalSecrets\", \"Pods\", \"NembraCapture.xcworkspace\")"))
        #expect(installer.contains("relative == \"Podfile.lock\""))
        #expect(installer.contains("untracked accepted-source path outside field-input allowlist"))
        #expect(installer.contains("verify_accepted_checkout_source \"Private workspace bootstrap changed accepted-source inputs.\""))
        #expect(installer.contains("verify_accepted_checkout_source \"Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart.\""))
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
        #expect(installer.contains("Repository HEAD no longer matches the accepted source."))
        #expect(installer.contains("Tracked source differs from the accepted commit."))
        #expect(installer.contains("Raw accepted-source byte audit failed."))
        #expect(installer.contains("verify_accepted_checkout_source \"Private workspace bootstrap changed accepted-source inputs.\""))
        #expect(installer.contains("verify_accepted_checkout_source \"Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart.\""))
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
        #expect(readback.contains("NembraCaptureTuyaDependencyLockSHA256"))
        #expect(readback.contains("NembraCaptureProcedureIdentifier"))
        #expect(readback.contains("CFBundleIdentifier"))
        #expect(readback.contains("$BUILT_BUILD_IDENTIFIER\" == \"$BUILD_LABEL"))
        #expect(readback.contains("$BUILT_SOURCE_SHA\" == \"$SOURCE_SHA"))
        #expect(readback.contains("$BUILT_TUYA_DEPENDENCY_LOCK_SHA256\" == \"$TUYA_DEPENDENCY_LOCK_SHA256"))
        #expect(readback.contains("$BUILT_PROCEDURE_IDENTIFIER\" == \"$PROCEDURE_ID"))
        #expect(readback.contains("$BUILT_BUNDLE_ID\" == \"$BUNDLE_ID"))
        #expect(readback.contains("Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"))
    }

    @Test("installer does not echo the private device identifier through normal diagnostics")
    func deviceIdentifierStaysOutOfNembraPresentation() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("<redacted-device>"))
        #expect(installer.contains("<redacted-device-selector>"))
        #expect(installer.contains("unset DEVICE_UDID COREDEVICE_ID"))
        #expect(installer.contains("process launch"))
        #expect(installer.contains("chmod 600 \"$INSTALL_LOG\""))
        #expect(installer.contains(">\"$INSTALL_LOG\" 2>&1"))
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