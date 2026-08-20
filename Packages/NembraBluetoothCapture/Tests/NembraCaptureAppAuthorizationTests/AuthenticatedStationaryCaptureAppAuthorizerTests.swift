import Foundation
import Testing
@testable import NembraBluetoothCapture
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture app authorizer")
@MainActor
struct AuthenticatedStationaryCaptureAppAuthorizerTests {
    private final class RecordingConsumptionStore:
        AuthenticatedStationaryCaptureAuthorizationConsumptionStore
    {
        var requests: [AuthenticatedStationaryCaptureAuthorizationConsumptionRequest] = []

        func consumeIfUnseen(
            _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
        ) throws -> Bool {
            requests.append(request)
            return true
        }
    }

    private func bindings() throws -> AuthenticatedStationaryCaptureExternalBindings {
        try AuthenticatedStationaryCaptureExternalBindings(
            tuyaDependencyLockSHA256: String(repeating: "1", count: 64),
            externalBuildRecordSHA256: String(repeating: "2", count: 64),
            signedBuildEvidenceSHA256: String(repeating: "3", count: 64),
            finalGORecordSHA256: String(repeating: "4", count: 64),
            intendedDevicePseudonymSHA256: String(repeating: "5", count: 64)
        )
    }

    private func runtimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-0123456789ab",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "12345678-90ab-4def-8abc-567890abcdef",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "0123456789abcdef0123456789abcdef01234567",
            ],
            executableData: Data("abc".utf8),
            infoPlistData: Data("plist-a".utf8)
        )
    }

    @Test("prepared attempt exposes only signer rendezvous facts, not a caller-minted capability")
    func preparedAttemptExposesChallengeWithoutPhysicalAuthority() throws {
        let store = RecordingConsumptionStore()
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(consumptionStore: store)
        let prepared = try authorizer.prepareForTesting(
            externalBindings: bindings(),
            challenge: Data(repeating: 0xA5, count: 32),
            bundleIdentifier: "com.jonathangana131.nembra.capturelearn",
            runtimeBuildIdentity: runtimeIdentity(),
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 1_000_000_000
        )

        #expect(prepared.challengeSHA256 == "fc8b64001c5fdd0f2f40fb67dae4a865a2c5bd17836676d6d5b58b7917e33717")
        #expect(prepared.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID)
        #expect(prepared.startedAtWallClockUnixMilliseconds == 2_000_000)
        #expect(prepared.startedAtUptimeNanoseconds == 1_000_000_000)
        #expect(store.requests.isEmpty)
    }

    @Test("production authorization remains fail closed while the independent trust root is absent")
    func productionAuthorizationCannotBypassMissingTrustRoot() throws {
        let store = RecordingConsumptionStore()
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(consumptionStore: store)
        let prepared = try authorizer.prepareForTesting(
            externalBindings: bindings(),
            challenge: Data(repeating: 0xA5, count: 32),
            bundleIdentifier: "com.jonathangana131.nembra.capturelearn",
            runtimeBuildIdentity: runtimeIdentity(),
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 1_000_000_000
        )

        #expect(
            throws: AuthenticatedStationaryCaptureFieldAuthorizationError
                .authorizationTrustAnchorNotConfigured
        ) {
            _ = try authorizer.authorize(
                envelopeData: Data("caller bytes cannot select a trust root".utf8),
                preparedAttempt: prepared
            )
        }
        #expect(store.requests.isEmpty)
    }

    @Test("invalid caller challenge shape cannot create a prepared attempt")
    func invalidChallengeFailsBeforeSignerRendezvous() throws {
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: RecordingConsumptionStore()
        )

        #expect(throws: AuthenticatedStationaryCaptureFieldAuthorizationError.invalidAttemptClock) {
            _ = try authorizer.prepareForTesting(
                externalBindings: bindings(),
                challenge: Data(repeating: 0xA5, count: 31),
                bundleIdentifier: "com.jonathangana131.nembra.capturelearn",
                runtimeBuildIdentity: runtimeIdentity(),
                wallClockUnixMilliseconds: 2_000_000,
                uptimeNanoseconds: 1_000_000_000
            )
        }
    }

    @Test("adapter source has no caller-selectable trust key or physical authorization Boolean")
    func sourceKeepsAuthorityPackageOwned() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppAuthorizer.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("makeCurrentApplicationAttempt"))
        #expect(source.contains("verifyForCurrentApplication"))
        #expect(source.contains("ThisDeviceAuthorizationConsumptionStore"))
        #expect(!source.contains("publicKeyX963Representation:"))
        #expect(!source.contains("permitsPhysicalProcedure"))
        #expect(!source.contains("isAuthoritativeFieldBuild = true"))
    }
}
