import Foundation
import Testing
@testable import NembraBluetoothCapture
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture exact manifest attempt")
@MainActor
struct AuthenticatedStationaryCaptureExactManifestAttemptTests {
    private final class NeverConsumeStore:
        AuthenticatedStationaryCaptureAuthorizationConsumptionStore
    {
        func consumeIfUnseen(
            _: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
        ) throws -> Bool {
            Issue.record("manifest continuity validation must not consume replay state")
            return false
        }
    }

    private let bundleIdentifier = "com.jonathangana131.nembra.capturelearn"

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

    private func bindings() throws -> AuthenticatedStationaryCaptureExternalBindings {
        try AuthenticatedStationaryCaptureExternalBindings(
            tuyaDependencyLockSHA256: String(repeating: "1", count: 64),
            externalBuildRecordSHA256: String(repeating: "2", count: 64),
            signedBuildEvidenceSHA256: String(repeating: "3", count: 64),
            finalGORecordSHA256: String(repeating: "4", count: 64),
            intendedDevicePseudonymSHA256: String(repeating: "5", count: 64)
        )
    }

    private func manifestData(
        runtime: PassiveBluetoothCaptureRuntimeBuildIdentity,
        externalBindings: AuthenticatedStationaryCaptureExternalBindings,
        retainedIPASHA256: String
    ) throws -> Data {
        let object: [String: Any] = [
            "schema": AuthenticatedStationaryCaptureInstallManifestVerifier.schema,
            "version": AuthenticatedStationaryCaptureInstallManifestVerifier.schemaVersion,
            "procedureID": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
            "sourceCommitSHA": runtime.sourceCommitSHA,
            "bundleIdentifier": bundleIdentifier,
            "buildIdentifier": runtime.buildIdentifier,
            "buildInstanceID": runtime.buildInstanceID,
            "retainedIPASHA256": retainedIPASHA256,
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

    @Test("a different retained IPA cannot replace the manifest after challenge creation")
    func retainedIPASubstitutionFailsBeforeSignatureVerification() throws {
        let runtime = try runtimeIdentity()
        let externalBindings = try bindings()
        let admitted = try manifestData(
            runtime: runtime,
            externalBindings: externalBindings,
            retainedIPASHA256: String(repeating: "6", count: 64)
        )
        let substituted = try manifestData(
            runtime: runtime,
            externalBindings: externalBindings,
            retainedIPASHA256: String(repeating: "7", count: 64)
        )
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: NeverConsumeStore()
        )
        let prepared = try authorizer.prepareFromInstallManifestForTesting(
            admitted,
            challenge: Data(repeating: 0xA5, count: 32),
            currentBundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtime,
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 1_000_000_000
        )

        #expect(
            throws: AuthenticatedStationaryCaptureAppAuthorizerError
                .manifestChangedSinceAttemptBegan
        ) {
            try authorizer.validateInstallManifestForTesting(
                substituted,
                preparedAttempt: prepared,
                currentBundleIdentifier: bundleIdentifier,
                runtimeBuildIdentity: runtime
            )
        }
    }

    @Test("the same admitted manifest remains valid before the trust-root boundary")
    func exactAdmittedManifestPassesCompositionBoundary() throws {
        let runtime = try runtimeIdentity()
        let externalBindings = try bindings()
        let admitted = try manifestData(
            runtime: runtime,
            externalBindings: externalBindings,
            retainedIPASHA256: String(repeating: "6", count: 64)
        )
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: NeverConsumeStore()
        )
        let prepared = try authorizer.prepareFromInstallManifestForTesting(
            admitted,
            challenge: Data(repeating: 0xA5, count: 32),
            currentBundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtime,
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 1_000_000_000
        )

        try authorizer.validateInstallManifestForTesting(
            admitted,
            preparedAttempt: prepared,
            currentBundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtime
        )
    }

    @Test("normal app code has no public arbitrary-binding challenge seam")
    func publicSurfaceRequiresRetainedManifest() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppAuthorizer.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("public func beginAttempt(\n        installManifestData: Data"))
        #expect(source.contains("package func beginAttempt(\n        externalBindings:"))
        #expect(!source.contains("public func beginAttempt(\n        externalBindings:"))
        #expect(source.contains("installManifestSHA256: manifest.canonicalManifestSHA256"))
        #expect(source.contains("manifest.canonicalManifestSHA256 == admittedManifestSHA256"))
        #expect(!source.contains("publicKeyX963Representation:"))
        #expect(!source.contains("isAuthoritativeFieldBuild = true"))
    }
}