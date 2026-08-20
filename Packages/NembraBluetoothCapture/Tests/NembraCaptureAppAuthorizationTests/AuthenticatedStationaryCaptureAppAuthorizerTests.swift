import Foundation
import NembraBluetoothCapture
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture app authorizer")
struct AuthenticatedStationaryCaptureAppAuthorizerTests {
    private final class RecordingConsumptionStore:
        AuthenticatedStationaryCaptureAuthorizationConsumptionStore
    {
        var calls = 0

        func consumeIfUnseen(
            _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
        ) throws -> Bool {
            calls += 1
            return true
        }
    }

    @MainActor
    @Test("prepared attempt exposes only signer rendezvous facts")
    func preparedAttemptExposesRendezvousFacts() throws {
        let store = RecordingConsumptionStore()
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: store
        )
        let prepared = try authorizer.prepareForTesting(
            externalBindings: try makeBindings(),
            challenge: Data(repeating: 0xAB, count: 32),
            bundleIdentifier: "com.jonathangana131.nembra.capturelearn",
            runtimeBuildIdentity: try makeRuntimeIdentity(),
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 10_000_000_000
        )

        #expect(
            prepared.challengeSHA256
                == "9a2db2e23f1504cd056606553ac049c5e718e8f9ce9233876df1a7a1821af885"
        )
        #expect(prepared.startedAtWallClockUnixMilliseconds == 2_000_000)
        #expect(prepared.startedAtUptimeNanoseconds == 10_000_000_000)
        #expect(
            prepared.procedureID
                == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID
        )
        #expect(store.calls == 0)
    }

    @MainActor
    @Test("nil production trust root blocks authorization before replay consumption")
    func nilTrustRootFailsBeforeConsumption() throws {
        let store = RecordingConsumptionStore()
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: store
        )
        let prepared = try authorizer.prepareForTesting(
            externalBindings: try makeBindings(),
            challenge: Data(repeating: 0xAB, count: 32),
            bundleIdentifier: "com.jonathangana131.nembra.capturelearn",
            runtimeBuildIdentity: try makeRuntimeIdentity(),
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 10_000_000_000
        )

        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .authorizationTrustAnchorNotConfigured
        ) {
            _ = try authorizer.authorize(
                envelopeData: Data("caller-controlled-envelope".utf8),
                preparedAttempt: prepared
            )
        }
        #expect(store.calls == 0)
    }

    @MainActor
    @Test("invalid deterministic attempt cannot become a prepared app attempt")
    func invalidAttemptIsRejected() throws {
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: RecordingConsumptionStore()
        )

        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError.invalidAttemptClock
        ) {
            _ = try authorizer.prepareForTesting(
                externalBindings: try makeBindings(),
                challenge: Data(repeating: 0xAB, count: 31),
                bundleIdentifier: "com.jonathangana131.nembra.capturelearn",
                runtimeBuildIdentity: try makeRuntimeIdentity(),
                wallClockUnixMilliseconds: 2_000_000,
                uptimeNanoseconds: 10_000_000_000
            )
        }
    }

    private func makeBindings() throws -> AuthenticatedStationaryCaptureExternalBindings {
        try AuthenticatedStationaryCaptureExternalBindings(
            tuyaDependencyLockSHA256: String(repeating: "1", count: 64),
            externalBuildRecordSHA256: String(repeating: "2", count: 64),
            signedBuildEvidenceSHA256: String(repeating: "3", count: 64),
            finalGORecordSHA256: String(repeating: "4", count: 64),
            intendedDevicePseudonymSHA256: String(repeating: "5", count: 64)
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-0123456789ab",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "12345678-1234-4abc-8def-123456789abc",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "0123456789abcdef0123456789abcdef01234567",
            ],
            executableData: Data("executable".utf8),
            infoPlistData: Data("plist".utf8)
        )
    }
}
