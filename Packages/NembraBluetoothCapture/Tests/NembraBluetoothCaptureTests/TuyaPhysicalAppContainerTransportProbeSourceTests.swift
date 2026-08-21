import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture physical app-container transport probe")
struct TuyaPhysicalAppContainerTransportProbeSourceTests {
    private let relativePath = "scripts/field/probe_capture_app_container_transport.command"

    @Test("probe binds only the Capture bundle transport without touching authorization subjects")
    func probeUsesOnlyNonAuthorizingScratchTransport() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("BUNDLE_ID='com.jonathangana131.nembra.capturelearn'"))
        #expect(probe.contains("FIELD_AUTHORIZATION_SUBDIRECTORY='Library/Application Support/NembraCapture/FieldAuthorization'"))
        #expect(probe.contains("devicectl device info files"))
        #expect(probe.contains("--domain-type appDataContainer"))
        #expect(probe.contains("--domain-identifier \"$BUNDLE_ID\""))
        #expect(probe.contains("REMOTE_SENTINEL=\"tmp/nembra-capture-transport-probe-$NONCE.bin\""))
        #expect(!probe.contains("--remove-existing-content"))
        #expect(!probe.contains("retained-install-manifest.json"))
        #expect(!probe.contains("authorization-envelope.json"))
        #expect(!probe.contains("signer-rendezvous.json"))
    }

    @Test("probe requires exact bidirectional bytes and preserves the physical NO-GO boundary")
    func probeRequiresRoundTripAndFailsClosedOnAuthority() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("/bin/bash \"$CONTRACT\""))
        #expect(probe.contains("devicectl device copy to"))
        #expect(probe.contains("devicectl device copy from"))
        #expect(probe.contains("/bin/dd if=/dev/urandom"))
        #expect(probe.contains("INBOUND_SHA256"))
        #expect(probe.contains("OUTBOUND_SHA256"))
        #expect(probe.contains("/usr/bin/cmp -s"))
        #expect(probe.contains("exact_round_trip=true"))
        #expect(probe.contains("authorization_subject_touched=false"))
        #expect(probe.contains("captureAuthorized=false"))
        #expect(probe.contains("physicalAuthorityCreated=false"))
        #expect(probe.contains("protocolSemanticsCreated=false"))
        #expect(probe.contains("bluetoothContacted=false"))
        #expect(probe.contains("tuyaContacted=false"))
        #expect(probe.contains("es80Contacted=false"))
        #expect(probe.contains("installed_build_identity_verified=false"))
        #expect(probe.contains("NOT PROVEN: exact installed Capture build identity"))
    }

    @Test("probe cannot promote bundle transport into exact installed-build evidence")
    func probeKeepsInstalledBuildIdentityExplicitlyUnverified() throws {
        let probe = try readRepositoryFile(relativePath)

        #expect(probe.contains("installed_build_identity_verified=false"))
        #expect(!probe.contains("installed_build_identity_verified=true"))
        #expect(probe.contains("does not prove the exact accepted Capture build is the installed bundle"))
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
