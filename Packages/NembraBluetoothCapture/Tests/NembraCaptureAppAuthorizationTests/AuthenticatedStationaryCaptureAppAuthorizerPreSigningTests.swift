import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture pre-signing admission")
@MainActor
struct AuthenticatedStationaryCaptureAppAuthorizerPreSigningTests {
    private let bundleIdentifier = "com.jonathangana131.nembra.capturelearn"
    private let sourceCommitSHA = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "12345678-90ab-cdef-1234-567890abcdef"

    @Test("exact retained install is proven before a signer challenge is created")
    func exactRetainedInstallPrecedesSignerRendezvous() throws {
        let store = RecordingConsumptionStore()
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(consumptionStore: store)
        let runtime = try runtimeIdentity()
        let manifest = try manifestData(runtime: runtime)
        let challenge = Data(repeating: 0xA5, count: 32)

        let prepared = try authorizer.prepareFromInstallManifestForTesting(
            manifest,
            challenge: challenge,
            currentBundleIdentifier: bundleIdentifier,
            runtimeBuildIdentity: runtime,
            wallClockUnixMilliseconds: 2_000_000,
            uptimeNanoseconds: 10_000_000_000
        )

        #expect(prepared.challengeSHA256 == sha256Hex(challenge))
        #expect(prepared.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID)
        #expect(store.requests.isEmpty)
    }

    @Test("wrong bundle cannot obtain a signer rendezvous")
    func wrongBundleFailsBeforeAttemptCreation() throws {
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: RecordingConsumptionStore()
        )
        let runtime = try runtimeIdentity()
        let manifest = try manifestData(runtime: runtime)

        #expect(throws: AuthenticatedStationaryCaptureAppAuthorizerError.manifestBundleMismatch) {
            _ = try authorizer.prepareFromInstallManifestForTesting(
                manifest,
                challenge: Data(repeating: 0xA5, count: 32),
                currentBundleIdentifier: "com.example.substituted",
                runtimeBuildIdentity: runtime,
                wallClockUnixMilliseconds: 2_000_000,
                uptimeNanoseconds: 10_000_000_000
            )
        }
    }

    @Test("runtime byte drift cannot obtain a signer rendezvous")
    func runtimeDriftFailsBeforeAttemptCreation() throws {
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: RecordingConsumptionStore()
        )
        let acceptedRuntime = try runtimeIdentity()
        let manifest = try manifestData(runtime: acceptedRuntime)
        let driftedRuntime = try runtimeIdentity(executableData: Data("different-executable".utf8))

        #expect(throws: AuthenticatedStationaryCaptureAppAuthorizerError.manifestRuntimeMismatch) {
            _ = try authorizer.prepareFromInstallManifestForTesting(
                manifest,
                challenge: Data(repeating: 0xA5, count: 32),
                currentBundleIdentifier: bundleIdentifier,
                runtimeBuildIdentity: driftedRuntime,
                wallClockUnixMilliseconds: 2_000_000,
                uptimeNanoseconds: 10_000_000_000
            )
        }
    }

    @Test("future authorization envelope cannot be smuggled into pre-signing install data")
    func postInstallFieldFailsBeforeAttemptCreation() throws {
        let authorizer = AuthenticatedStationaryCaptureAppAuthorizer(
            consumptionStore: RecordingConsumptionStore()
        )
        let runtime = try runtimeIdentity()
        let canonical = try manifestData(runtime: runtime)
        var object = try #require(JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        object["authorizationEnvelopeSHA256"] = String(repeating: "a", count: 64)
        let injected = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )

        #expect(
            throws: AuthenticatedStationaryCaptureInstallManifestError
                .unexpectedManifestField("authorizationEnvelopeSHA256")
        ) {
            _ = try authorizer.prepareFromInstallManifestForTesting(
                injected,
                challenge: Data(repeating: 0xA5, count: 32),
                currentBundleIdentifier: bundleIdentifier,
                runtimeBuildIdentity: runtime,
                wallClockUnixMilliseconds: 2_000_000,
                uptimeNanoseconds: 10_000_000_000
            )
        }
    }

    @Test("production source validates retained install before the lower-level attempt constructor")
    func sourceOrderIsFailClosed() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppAuthorizer.swift"
            ),
            encoding: .utf8
        )

        let manifestValidation = try #require(
            source.range(of: "validateInstallManifestForRunningApplication(")
        )
        let attemptCreation = try #require(
            source.range(of: "return try beginAttempt(externalBindings: manifest.externalBindings())")
        )
        #expect(manifestValidation.lowerBound < attemptCreation.lowerBound)
        #expect(source.contains("public func beginAttempt(\n        installManifestData: Data"))
        #expect(!source.contains("publicKeyX963Representation:"))
    }

    private func runtimeIdentity(
        executableData: Data = Data("authorizer-executable".utf8),
        infoPlistData: Data = Data("authorizer-plist".utf8)
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-\(sourceCommitSHA.prefix(12))",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    private func manifestData(
        runtime: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> Data {
        let object: [String: Any] = [
            "schema": AuthenticatedStationaryCaptureInstallManifestVerifier.schema,
            "version": AuthenticatedStationaryCaptureInstallManifestVerifier.schemaVersion,
            "procedureID": AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
            "sourceCommitSHA": runtime.sourceCommitSHA,
            "bundleIdentifier": bundleIdentifier,
            "buildIdentifier": runtime.buildIdentifier,
            "buildInstanceID": runtime.buildInstanceID,
            "retainedIPASHA256": String(repeating: "1", count: 64),
            "executableSHA256": runtime.executableSHA256,
            "infoPlistSHA256": runtime.infoPlistSHA256,
            "tuyaDependencyLockSHA256": String(repeating: "2", count: 64),
            "externalBuildRecordSHA256": String(repeating: "3", count: 64),
            "signedBuildEvidenceSHA256": String(repeating: "4", count: 64),
            "finalGORecordSHA256": String(repeating: "5", count: 64),
            "intendedDevicePseudonymSHA256": String(repeating: "6", count: 64),
        ]
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private final class RecordingConsumptionStore:
    AuthenticatedStationaryCaptureAuthorizationConsumptionStore
{
    private(set) var requests: [AuthenticatedStationaryCaptureAuthorizationConsumptionRequest] = []

    func consumeIfUnseen(
        _ request: AuthenticatedStationaryCaptureAuthorizationConsumptionRequest
    ) throws -> Bool {
        requests.append(request)
        return true
    }
}
