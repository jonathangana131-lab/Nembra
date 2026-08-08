import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Verified Experiment One field execution authority")
struct PassiveBluetoothVerifiedFieldExecutionGateTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableData = Data("exact accepted field executable".utf8)
    private let infoPlistData = Data("exact accepted field Info.plist".utf8)

    @Test("verified exact-build authorization is the only GO vocabulary input")
    func verifiedAuthorizationMapsToGo() throws {
        let authorization = try makeVerifiedAuthorization()
        let status = PassiveBluetoothExperimentOneFieldExecutionGate.status(for: authorization)

        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure(for: authorization))
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure(status: status))
        if case let .go(mappedAuthorization) = status {
            #expect(mappedAuthorization == authorization)
        } else {
            #expect(Bool(false), "A package-verified exact-build authorization must map to GO")
        }
    }

    @MainActor
    @Test("default coordinator remains locked without verified authorization")
    func defaultCoordinatorRemainsLocked() throws {
        let coordinator = try PassiveBluetoothExperimentOneCoordinator()

        #expect(!coordinator.status.physicalProcedurePermitted)
        #expect(
            coordinator.status.fieldExecutionStatus
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(coordinator.status.connection == .unavailable)
        #expect(throws: PassiveBluetoothExperimentOneCoordinator.CoordinatorError.physicalProcedureLocked) {
            try coordinator.startCurrentPowerCycleWindow()
        }
    }

    @MainActor
    @Test("verified authorization is retained by the live coordinator authority")
    func verifiedAuthorizationConstructsAuthorizedCoordinator() throws {
        let authorization = try makeVerifiedAuthorization()
        let coordinator = try PassiveBluetoothExperimentOneCoordinator(
            fieldAuthorization: authorization
        )

        #expect(coordinator.status.physicalProcedurePermitted)
        if case let .go(mappedAuthorization) = coordinator.status.fieldExecutionStatus {
            #expect(mappedAuthorization == authorization)
        } else {
            #expect(Bool(false), "Authorized coordinator must retain the verified GO authority")
        }
        #expect(coordinator.status.connection != .unavailable)
    }

    private func makeVerifiedAuthorization() throws -> PassiveBluetoothCaptureVerifiedFieldAuthorization {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: executableData
        )

        let record = try json([
            "schemaVersion": 3,
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ])
        let payload = try json([
            "schemaVersion": 1,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(record),
        ])
        let signature = try signingKey.signature(for: payload)
        let envelope = try json([
            "schemaVersion": 1,
            "externalBuildRecordBase64": record.base64EncodedString(),
            "authorizationPayloadBase64": payload.base64EncodedString(),
            "signatureDERBase64": signature.derRepresentation.base64EncodedString(),
        ])

        return try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
            envelope,
            publicKeyX963Representation: signingKey.publicKey.x963Representation,
            runtimeBuildIdentity: runtimeIdentity,
            runtimeInfoPlistSHA256: sha256Hex(infoPlistData)
        )
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
