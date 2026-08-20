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

    private let bundleIdentifier = "com.jonathangana131.nembra.capturelearn"

    private func bindings(
        finalGORecordSHA256: String = String(repeating: "4", count: 64)
    ) throws -> AuthenticatedStationaryCaptureExternalBindings {
        try AuthenticatedStationaryCaptureExternalBindings(
            tuyaDependencyLockSHA256: String(repeating: "1", count: 64),
            externalBuildRecordSHA256: String(repeating: "2", count: 64),
            signedBuildEvidenceSHA256: String(repeating: "3", count: 64),
            finalGORecordSHA256: finalGORecordSHA256,
            intendedDevicePseudonymSHA256: String(repeating: "5", count: 64)
        )
    }

    private func runtimeIdentity(
        executableData: Data = Data("abc".utf8),
        infoPlistData: Data = Data("plist-a".utf8)
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-0123456789ab",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "12345678-90ab-4def-8abc-567890abcdef",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "0123456789abcdef0123456789abcdef01234567",
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    private func manifestData(
        runtime: PassiveBluetoothCaptureRuntimeBuildIdentity,
        externalBindings: AuthenticatedStationaryCaptureExternalBindings,
        bundleIdentifier: String? = nil
    ) throws -> Data {
        let object: [String: Any] = [
            "schema": AuthenticatedStationaryCaptureInstallManifestVerifier.schema,
            "version": AuthenticatedStationaryCaptureInstallManifestVerifier.schemaVersion,
            "procedureID": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
            "sourceCommitSHA": runtime.sourceCommitSHA,
            "bundleIdentifier": bundleIdentifier ?? self.bundleIdentifier,
            "buildIdentifier": runtime.buildIdentifier,
            "buildInstanceID": runtime.buildInstanceID,
            "retainedIPASHA256": String(repeating: "6", count: 64),
            "executableSHA256": runtime.executableSHA256,
            "infoPlistSHA256": runtime.infoPlistSHA256,
            "tuyaDependencyLockSHA256": externalBindings.tuyaDependencyLockSHA256,
            "externalBuildRecordSHA256": externalBindings.externalBuildRecordSHA256,
            "signedBuildEvidenceSHA256": externalBindings.signedBuildEvidenceSHA256,
            "finalGORecordSHA256": externalBindings.finalGORecordSHA256,
            "intendedDevicePseudonymSHA256": externalBindings.intendedDevicePseudonymSHA256,
        ]
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func preparedAttempt(
        authorizer: AuthenticatedStationaryCaptureAppAuthorizer,
        externalBindings: AuthenticatedStationaryCaptureExternalBindings,
        runtime: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> AuthenticatedStationaryCapturePreparedAttempt {
        try authorizer.prepareForTesting(
            externalBindings: externalBindings,
            challenge: Data(repeating: 0xA5, count: 32),
            bundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtime,
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 1_000_000_000
        )
    }

    @Test("prepared attempt exposes signer rendezvous facts without physical authority")
    func preparedAttemptExposesChallengeWithoutPhysicalAuthority() throws {
        let store = RecordingConsumptionStore()
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(consumptionStore: store)
        let prepared = try preparedAttempt(
            authorizer: authorizer,
            externalBindings: bindings(),
            runtime: runtimeIdentity()
        )

        #expect(prepared.challengeSHA256 == "fc8b64001c5fdd0f2f40fb67dae4a865a2c5bd17836676d6d5b58b7917e33717")
        #expect(prepared.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID)
        #expect(prepared.startedAtWallClockUnixMilliseconds == 2_000_000)
        #expect(prepared.startedAtUptimeNanoseconds == 1_000_000_000)
        #expect(store.requests.isEmpty)
    }

    @Test("matching pre-install manifest cross-binds running build and stable attempt evidence")
    func matchingInstallManifestPassesCompositionBoundary() throws {
        let store = RecordingConsumptionStore()
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(consumptionStore: store)
        let runtime = try runtimeIdentity()
        let externalBindings = try bindings()
        let prepared = try preparedAttempt(
            authorizer: authorizer,
            externalBindings: externalBindings,
            runtime: runtime
        )
        let manifest = try manifestData(
            runtime: runtime,
            externalBindings: externalBindings
        )

        try authorizer.validateInstallManifestForTesting(
            manifest,
            preparedAttempt: prepared,
            currentBundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtime
        )
        #expect(store.requests.isEmpty)
    }

    @Test("pre-install manifest rejects post-install authorization-envelope fields")
    func authorizationEnvelopeCannotEnterPreInstallManifest() throws {
        let runtime = try runtimeIdentity()
        let externalBindings = try bindings()
        let canonical = try manifestData(
            runtime: runtime,
            externalBindings: externalBindings
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        object["authorizationEnvelopeSHA256"] = String(repeating: "a", count: 64)
        let withPostInstallField = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )

        #expect(
            throws: AuthenticatedStationaryCaptureInstallManifestError
                .unexpectedManifestField("authorizationEnvelopeSHA256")
        ) {
            _ = try AuthenticatedStationaryCaptureInstallManifestVerifier
                .decodeCanonical(withPostInstallField)
        }
    }

    @Test("runtime build and prepared-attempt binding drift fail closed")
    func buildAndAttemptBindingDriftFailClosed() throws {
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: RecordingConsumptionStore()
        )
        let runtime = try runtimeIdentity()
        let acceptedBindings = try bindings()
        let prepared = try preparedAttempt(
            authorizer: authorizer,
            externalBindings: acceptedBindings,
            runtime: runtime
        )

        let driftedRuntime = try runtimeIdentity(executableData: Data("different-app".utf8))
        let runtimeManifest = try manifestData(
            runtime: runtime,
            externalBindings: acceptedBindings
        )
        #expect(throws: AuthenticatedStationaryCaptureAppAuthorizerError.manifestRuntimeMismatch) {
            try authorizer.validateInstallManifestForTesting(
                runtimeManifest,
                preparedAttempt: prepared,
                currentBundleIdentifier: bundleIdentifier,
                runtimeBuildIdentity: driftedRuntime
            )
        }

        let driftedBindings = try bindings(finalGORecordSHA256: String(repeating: "b", count: 64))
        let bindingsManifest = try manifestData(
            runtime: runtime,
            externalBindings: driftedBindings
        )
        #expect(
            throws: AuthenticatedStationaryCaptureAppAuthorizerError
                .manifestAttemptBindingsMismatch
        ) {
            try authorizer.validateInstallManifestForTesting(
                bindingsManifest,
                preparedAttempt: prepared,
                currentBundleIdentifier: bundleIdentifier,
                runtimeBuildIdentity: runtime
            )
        }
    }

    @Test("wrong running bundle cannot consume a structurally valid Capture manifest")
    func bundleMismatchFailsClosed() throws {
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: RecordingConsumptionStore()
        )
        let runtime = try runtimeIdentity()
        let externalBindings = try bindings()
        let prepared = try preparedAttempt(
            authorizer: authorizer,
            externalBindings: externalBindings,
            runtime: runtime
        )
        let manifest = try manifestData(
            runtime: runtime,
            externalBindings: externalBindings
        )

        #expect(throws: AuthenticatedStationaryCaptureAppAuthorizerError.manifestBundleMismatch) {
            try authorizer.validateInstallManifestForTesting(
                manifest,
                preparedAttempt: prepared,
                currentBundleIdentifier: "com.example.not-capture",
                runtimeBuildIdentity: runtime
            )
        }
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
                bundleIdentifier: bundleIdentifier,
                runtimeBuildIdentity: runtimeIdentity(),
                wallClockUnixMilliseconds: 2_000_000,
                uptimeNanoseconds: 1_000_000_000
            )
        }
    }

    @Test("adapter source keeps trust and raw physical authority package-owned")
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
        #expect(source.contains("AuthenticatedStationaryCaptureInstallManifestVerifier"))
        #expect(source.contains("manifest.matches(runtimeBuildIdentity:"))
        #expect(source.contains("manifest.externalBindings() == preparedAttempt.packageAttempt.externalBindings"))
        #expect(source.contains("verifyForCurrentApplication"))
        #expect(source.contains("ThisDeviceAuthorizationConsumptionStore"))
        #expect(source.contains("throws -> AuthenticatedStationaryCaptureCapabilityGate"))
        #expect(source.contains("return AuthenticatedStationaryCaptureCapabilityGate(capability: capability)"))
        #expect(source.contains("private func beginAttempt(\n        externalBindings:"))
        #expect(!source.contains("public func beginAttempt(\n        externalBindings:"))
        #expect(!source.contains("throws -> AuthenticatedStationaryCaptureAttemptCapability"))
        #expect(!source.contains("authorizationEnvelopeSHA256"))
        #expect(!source.contains("publicKeyX963Representation:"))
        #expect(!source.contains("permitsPhysicalProcedure"))
        #expect(!source.contains("isAuthoritativeFieldBuild = true"))
    }
}
