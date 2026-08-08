import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One verified field admission")
struct PassiveBluetoothExperimentOneVerifiedAdmissionTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableData = Data("verified-admission-executable".utf8)
    private let infoPlistData = Data("verified-admission-info-plist".utf8)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)

    @Test("TODAY research admission requires exact recipe plus exact canonical embedded build tuple")
    func exactBuildTimeResearchConfigurationMintsPackageAdmission() throws {
        let runtimeIdentity = try makeRuntimeIdentity()
        let infoDictionary = researchBuildInfoDictionary()

        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: infoDictionary,
                runtimeBuildIdentity: runtimeIdentity
            )
        )

        #expect(admission.recipeID == .es80FingerprintV1)
        #expect(admission.runtimeBuildIdentity == runtimeIdentity)
    }

    @Test("recipe marker alone cannot authorize a mismatched or noncanonical build")
    func researchAdmissionRejectsBuildTupleDrift() throws {
        let runtimeIdentity = try makeRuntimeIdentity()

        var wrongRecipe = researchBuildInfoDictionary()
        wrongRecipe[PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey]
            = "ES80-ELECTRICAL-CORRELATION-v1"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: wrongRecipe,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var wrongBuildIdentifier = researchBuildInfoDictionary()
        wrongBuildIdentifier[
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey
        ] = "Capture Build V14-000000000000"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: wrongBuildIdentifier,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var wrongBuildInstance = researchBuildInfoDictionary()
        wrongBuildInstance[
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey
        ] = "11111111-2222-4333-8444-555555555555"
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: wrongBuildInstance,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        var wrongSource = researchBuildInfoDictionary()
        wrongSource[
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey
        ] = String(repeating: "0", count: 40)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: wrongSource,
                runtimeBuildIdentity: runtimeIdentity
            ) == nil
        )

        let noncanonicalRuntimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader
            .resolveEmbeddedMetadata(
                infoDictionary: [
                    PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                        "Capture Build V14-manual",
                    PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                        buildInstanceID,
                    PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                        sourceCommitSHA,
                ],
                executableData: executableData,
                infoPlistData: infoPlistData
            )
        var noncanonicalInfo = researchBuildInfoDictionary()
        noncanonicalInfo[
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey
        ] = noncanonicalRuntimeIdentity.buildIdentifier
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.researchBuildAdmission(
                infoDictionary: noncanonicalInfo,
                runtimeBuildIdentity: noncanonicalRuntimeIdentity
            ) == nil
        )
    }

    @Test("verified signed authority can mint only an audit-bound package admission")
    func verifiedAuthorizationMintsAdmissionWithoutChangingDefaultNoGo() throws {
        let signingKey = P256.Signing.PrivateKey()
        let runtimeIdentity = try makeRuntimeIdentity()
        let externalRecord = try json(externalRecordObject())
        let fieldEvidence = try json(
            fieldEvidenceObject(externalRecordSHA256: sha256Hex(externalRecord))
        )
        let payload = try json([
            "schemaVersion": PassiveBluetoothCaptureFieldAuthorizationVerifier
                .authorizationPayloadSchemaVersion,
            "decision": "GO",
            "externalBuildRecordSHA256": sha256Hex(externalRecord),
            "fieldBuildEvidenceRecordSHA256": sha256Hex(fieldEvidence),
        ])
        let signature = try signingKey.signature(for: payload)
        let envelope = try json([
            "schemaVersion": PassiveBluetoothCaptureFieldAuthorizationVerifier.envelopeSchemaVersion,
            "externalBuildRecordBase64": externalRecord.base64EncodedString(),
            "fieldBuildEvidenceRecordBase64": fieldEvidence.base64EncodedString(),
            "authorizationPayloadBase64": payload.base64EncodedString(),
            "signatureDERBase64": signature.derRepresentation.base64EncodedString(),
        ])

        let verified = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(
            envelope,
            publicKeyX963Representation: signingKey.publicKey.x963Representation,
            runtimeBuildIdentity: runtimeIdentity
        )
        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.admit(
                verifiedAuthorization: verified
            )
        )

        #expect(admission.buildIdentifier == buildIdentifier)
        #expect(admission.buildInstanceID == buildInstanceID)
        #expect(admission.sourceCommitSHA == sourceCommitSHA)
        #expect(admission.signedInstallableSHA256 == signedInstallableSHA256)
        #expect(admission.fieldEvidenceRecordSHA256 == sha256Hex(fieldEvidence))
        #expect(admission.authorizationPayloadSHA256 == sha256Hex(payload))

        // The package-test host does not carry the canonical field-build recipe marker, so minting
        // release-grade evidence inside this deterministic test does not mutate the running process
        // into a TODAY research build.
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("canonical live factory is gated by process-owned research admission or sealed verified authority")
    func canonicalFactoryKeepsBooleanPreferenceAndImportedEvidenceOut() throws {
        let source = try sourceFile(
            "Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator+CanonicalES80.swift"
        )

        let gateGuard = "PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"
        let researchGuard = "PassiveBluetoothExperimentOneFieldExecutionGate.currentResearchBuildAdmission != nil"
        let zeroFactoryStart = try #require(
            source.range(of: "static func makeAuthorizedES80() throws")?.lowerBound
        )
        let verifiedFactoryStart = try #require(
            source.range(
                of: "static func makeAuthorizedES80(\n        verifiedAdmission _: PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission"
            )?.lowerBound
        )
        let liveFactoryStart = try #require(
            source.range(
                of: "private static func makeLiveES80Coordinator() throws",
                range: verifiedFactoryStart..<source.endIndex
            )?.lowerBound
        )

        let zeroFactory = source[zeroFactoryStart..<verifiedFactoryStart]
        let zeroResearchGuard = try #require(zeroFactory.range(of: researchGuard))
        let zeroGateGuard = try #require(zeroFactory.range(of: gateGuard))
        let zeroLiveConstruction = try #require(
            zeroFactory.range(of: "return try makeLiveES80Coordinator()")
        )
        #expect(zeroResearchGuard.lowerBound < zeroLiveConstruction.lowerBound)
        #expect(zeroGateGuard.lowerBound < zeroLiveConstruction.lowerBound)

        let verifiedFactory = source[verifiedFactoryStart..<liveFactoryStart]
        let verifiedGuard = try #require(verifiedFactory.range(of: gateGuard))
        let verifiedLiveConstruction = try #require(
            verifiedFactory.range(of: "return try makeLiveES80Coordinator()")
        )
        #expect(verifiedGuard.lowerBound < verifiedLiveConstruction.lowerBound)

        #expect(source.contains("private static func makeLiveES80Coordinator() throws"))
        #expect(!source.contains("authorized: Bool"))
        #expect(!source.contains("permission: Bool"))
        #expect(!source.contains("UserDefaults"))
        #expect(!source.contains("ProcessInfo"))
    }

    @Test("current app consumes only the package-owned canonical factory")
    func appUsesNoCallerConstructedAdmissionOrRuntimeToggle() throws {
        let source = try repositorySourceFile("NembraApp/App/NembraApp.swift")
        let zeroArgumentFactory = "PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"

        #expect(source.components(separatedBy: zeroArgumentFactory).count - 1 == 2)
        #expect(!source.contains("verifiedAdmission:"))
        #expect(!source.contains("PassiveBluetoothCaptureVerifiedFieldAuthorization"))
        #expect(!source.contains("PassiveBluetoothCaptureFieldAuthorizationVerifier"))
        #expect(!source.contains("UserDefaults"))
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    private func researchBuildInfoDictionary() -> [String: Any] {
        [
            PassiveBluetoothExperimentOneFieldExecutionGate.researchFieldRecipeInfoDictionaryKey:
                PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                buildIdentifier,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                buildInstanceID,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                sourceCommitSHA,
        ]
    }

    private func externalRecordObject() -> [String: Any] {
        [
            "schemaVersion": 3,
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func fieldEvidenceObject(
        externalRecordSHA256: String
    ) -> [String: Any] {
        [
            "schemaVersion": 1,
            "externalBuildRecordSHA256": externalRecordSHA256,
            "signedInstallableSHA256": signedInstallableSHA256,
            "signedInstallableKind": "ipa",
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositorySourceFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
