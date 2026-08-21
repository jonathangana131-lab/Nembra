import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture physical app-container transport probe")
struct TuyaPhysicalAppContainerTransportProbeSourceTests {
    private let relativePath = "scripts/field/probe_capture_app_container_transport.command"

    @Test("probe binds only the Capture bundle transport without transferring authorization payloads")
    func probeUsesOnlyNonAuthorizingScratchTransport() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("BUNDLE_ID='com.jonathangana131.nembra.capturelearn'"))
        #expect(probe.contains("FIELD_AUTHORIZATION_SUBDIRECTORY='Library/Application Support/NembraCapture/FieldAuthorization'"))
        #expect(probe.contains("devicectl device info files"))
        #expect(probe.contains("--domain-type appDataContainer"))
        #expect(probe.contains("--domain-identifier \"$BUNDLE_ID\""))
        #expect(probe.contains("REMOTE_SENTINEL=\"tmp/nembra-capture-transport-probe-$NONCE.bin\""))
        #expect(probe.contains("field_authorization_subdirectory_listing_succeeded=true"))
        #expect(probe.contains("authorization_payload_file_transferred=false"))
        #expect(!probe.contains("field_authorization_directory_listed_read_only=true"))
        #expect(!probe.contains("field_authorization_directory_present=true"))
        #expect(!probe.contains("authorization_subject_touched=false"))
        #expect(!probe.contains("--remove-existing-content"))
        #expect(!probe.contains("retained-install-manifest.json"))
        #expect(!probe.contains("authorization-envelope.json"))
        #expect(!probe.contains("signer-rendezvous.json"))
    }

    @Test("probe requires exact bidirectional bytes and preserves the physical NO-GO boundary")
    func probeRequiresRoundTripAndFailsClosedOnAuthority() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("/bin/bash \"$CONTRACT_EXEC\""))
        #expect(probe.contains("devicectl device copy to"))
        #expect(probe.contains("devicectl device copy from"))
        #expect(probe.contains("/bin/dd if=/dev/urandom"))
        #expect(probe.contains("INBOUND_SHA256"))
        #expect(probe.contains("OUTBOUND_SHA256"))
        #expect(probe.contains("/usr/bin/cmp -s"))
        #expect(probe.contains("exact_round_trip=true"))
        #expect(probe.contains("captureAuthorized=false"))
        #expect(probe.contains("physicalAuthorityCreated=false"))
        #expect(probe.contains("protocolSemanticsCreated=false"))
        #expect(probe.contains("probe_initiated_bluetooth=false"))
        #expect(probe.contains("probe_initiated_tuya=false"))
        #expect(probe.contains("probe_initiated_es80_contact=false"))
        #expect(!probe.contains("bluetoothContacted=false"))
        #expect(!probe.contains("tuyaContacted=false"))
        #expect(!probe.contains("es80Contacted=false"))
        #expect(probe.contains("installed_build_identity_verified=false"))
        #expect(probe.contains("NOT PROVEN: handoff-directory filesystem existence beyond devicectl listing success"))
        #expect(probe.contains("whether another process or already-running app contacted Bluetooth/Tuya/ES80"))
    }

    @Test("probe cannot promote bundle transport into exact installed-build evidence")
    func probeKeepsInstalledBuildIdentityExplicitlyUnverified() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("installed_build_identity_verified=false"))
        #expect(!probe.contains("installed_build_identity_verified=true"))
        #expect(probe.contains("does not prove the exact accepted Capture build is the installed bundle"))
    }

    @Test("probe takes device identity only from the environment and never positional argv")
    func probeRejectsPositionalRawDeviceIdentity() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("[[ \"$#\" -eq 0 ]]"))
        #expect(probe.contains("positional arguments are forbidden"))
        #expect(probe.contains("DEVICE_UDID=\"${NEMBRA_CAPTURE_DEVICE_UDID:-}\""))
        #expect(probe.contains("unset NEMBRA_CAPTURE_DEVICE_UDID"))
        #expect(!probe.contains("${1:-}"))
        #expect(!probe.contains("argument 1"))
    }

    @Test("probe keeps raw physical-device output ephemeral and publishes only a pseudonym")
    func probePseudonymizesDeviceIdentityInResult() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("PRIVATE_RUNTIME_DIR"))
        #expect(probe.contains("trap cleanup_private_runtime EXIT"))
        #expect(probe.contains("trap 'exit 129' HUP"))
        #expect(probe.contains("trap 'exit 130' INT"))
        #expect(probe.contains("trap 'exit 143' TERM"))
        #expect(probe.contains("> \"$PRIVATE_RUNTIME_DIR/field-authorization-directory-listing.txt\" 2>&1"))
        #expect(probe.contains("> \"$PRIVATE_RUNTIME_DIR/copy-to.txt\" 2>&1"))
        #expect(probe.contains("> \"$PRIVATE_RUNTIME_DIR/copy-from.txt\" 2>&1"))
        #expect(probe.contains("DEVICE_PSEUDONYM"))
        #expect(probe.contains("device_pseudonym_sha256=%s"))
        #expect(probe.contains("raw_device_output_persisted=false"))
        #expect(!probe.contains("device_udid=%s"))
        #expect(!probe.contains("udid=%s"))
        #expect(probe.contains("NEMBRA_CAPTURE_DEVICE_UDID"))
    }

    @Test("every attempt has a unique evidence directory and success is atomically sealed")
    func probeCannotPromoteAStaleResultFromAnEarlierAttempt() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("ARTIFACTS_ROOT="))
        #expect(probe.contains("RUN_ID=\"$(/usr/bin/uuidgen"))
        #expect(probe.contains("RUN_DIR=\"$ARTIFACTS_ROOT/run-$RUN_ID\""))
        #expect(probe.contains("/bin/mkdir \"$RUN_DIR\""))
        #expect(probe.contains("ARTIFACTS_DIR=\"$RUN_DIR\""))
        #expect(probe.contains("evidence_run_id=%s"))
        #expect(probe.contains("RESULT_TMP=\"$ARTIFACTS_DIR/.result-$NONCE.tmp\""))
        #expect(probe.contains("RESULT_PATH=\"$ARTIFACTS_DIR/result.txt\""))
        #expect(probe.contains("/bin/mv -f -- \"$RESULT_TMP\" \"$RESULT_PATH\""))
        #expect(probe.contains("/bin/rm -f -- \"$LOCAL_SENTINEL\" \"$ROUNDTRIP_SENTINEL\""))
        #expect(probe.contains("umask 077"))
        #expect(probe.contains("accidentally promote stale success"))
    }

    @Test("physical result binds exact repository probe and contract bytes")
    func probeRecordsExactCheckedInProvenance() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("PROBE_RELATIVE_PATH='scripts/field/probe_capture_app_container_transport.command'"))
        #expect(probe.contains("CONTRACT_RELATIVE_PATH='scripts/ci/xcode27_devicectl_manifest_transport_contract.sh'"))
        #expect(probe.contains("REPOSITORY_HEAD="))
        #expect(probe.contains("rev-parse --verify 'HEAD^{commit}'"))
        #expect(probe.contains("PROBE_TRACKED_BLOB="))
        #expect(probe.contains("CONTRACT_TRACKED_BLOB="))
        #expect(probe.contains("PROBE_WORKTREE_BLOB="))
        #expect(probe.contains("CONTRACT_WORKTREE_BLOB="))
        #expect(probe.contains("PROBE_WORKTREE_BLOB\" == \"$PROBE_TRACKED_BLOB"))
        #expect(probe.contains("CONTRACT_WORKTREE_BLOB\" == \"$CONTRACT_TRACKED_BLOB"))
        #expect(probe.contains("cat-file blob \"$CONTRACT_TRACKED_BLOB\""))
        #expect(probe.contains("hash-object \"$CONTRACT_EXEC\""))
        #expect(probe.contains("repository_head=%s"))
        #expect(probe.contains("probe_git_blob=%s"))
        #expect(probe.contains("probe_sha256=%s"))
        #expect(probe.contains("transport_contract_git_blob=%s"))
        #expect(probe.contains("transport_contract_sha256=%s"))
        #expect(probe.contains("xcode_identity=%s"))
        #expect(probe.contains("PROVEN PROVENANCE:"))
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