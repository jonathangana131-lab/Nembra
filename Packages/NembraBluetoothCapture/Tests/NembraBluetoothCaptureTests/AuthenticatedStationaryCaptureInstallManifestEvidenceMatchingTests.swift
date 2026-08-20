import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated stationary install-manifest evidence matching")
struct AuthenticatedStationaryCaptureInstallManifestEvidenceMatchingTests {
    @Test("manifest matches only the exact bounded authorization-envelope bytes")
    func exactEnvelopeBytesAreRequired() throws {
        let manifest = try AuthenticatedStationaryCaptureInstallManifestVerifier.decodeCanonical(
            manifestData(authorizationEnvelopeSHA256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        )

        #expect(manifest.matchesAuthorizationEnvelope(Data("abc".utf8)))
        #expect(!manifest.matchesAuthorizationEnvelope(Data("abd".utf8)))
        #expect(!manifest.matchesAuthorizationEnvelope(Data()))
    }

    @Test("oversized envelope input fails closed before it can be treated as the bound subject")
    func oversizedEnvelopeFailsClosed() throws {
        let manifest = try AuthenticatedStationaryCaptureInstallManifestVerifier.decodeCanonical(
            manifestData(authorizationEnvelopeSHA256: String(repeating: "7", count: 64))
        )
        let oversized = Data(
            repeating: 0x41,
            count: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.maximumEnvelopeByteCount + 1
        )

        #expect(!manifest.matchesAuthorizationEnvelope(oversized))
    }

    private func manifestData(authorizationEnvelopeSHA256: String) -> Data {
        Data((
            "{"
            + "\"authorizationEnvelopeSHA256\":\"\(authorizationEnvelopeSHA256)\","
            + "\"buildIdentifier\":\"Capture Build V14-0123456789ab\","
            + "\"buildInstanceID\":\"12345678-90ab-4def-8abc-567890abcdef\","
            + "\"bundleIdentifier\":\"com.jonathangana131.nembra.capturelearn\","
            + "\"executableSHA256\":\"1111111111111111111111111111111111111111111111111111111111111111\","
            + "\"externalBuildRecordSHA256\":\"2222222222222222222222222222222222222222222222222222222222222222\","
            + "\"finalGORecordSHA256\":\"3333333333333333333333333333333333333333333333333333333333333333\","
            + "\"infoPlistSHA256\":\"4444444444444444444444444444444444444444444444444444444444444444\","
            + "\"intendedDevicePseudonymSHA256\":\"5555555555555555555555555555555555555555555555555555555555555555\","
            + "\"procedureID\":\"ES80-AUTHENTICATED-STATIONARY-v1\","
            + "\"retainedIPASHA256\":\"7777777777777777777777777777777777777777777777777777777777777777\","
            + "\"schema\":\"nembra.es80-authenticated-stationary-install-manifest\","
            + "\"signedBuildEvidenceSHA256\":\"6666666666666666666666666666666666666666666666666666666666666666\","
            + "\"sourceCommitSHA\":\"0123456789abcdef0123456789abcdef01234567\","
            + "\"tuyaDependencyLockSHA256\":\"8888888888888888888888888888888888888888888888888888888888888888\","
            + "\"version\":1}"
        ).utf8)
    }
}
