import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One private research build admission")
struct PassiveBluetoothExperimentOnePrivateResearchAdmissionTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableData = Data("today-research-executable".utf8)
    private let infoPlistData = Data("today-research-info-plist".utf8)

    @Test("canonical producer-shaped exact running build can mint only instance-bound research GO")
    func canonicalResearchBuildMintsInstanceBoundAdmission() throws {
        let identity = try makeRuntimeIdentity()
        let admission = try PassiveBluetoothExperimentOneFieldExecutionGate.researchAdmission(
            infoDictionary: infoDictionary(),
            runtimeBuildIdentity: identity
        )

        #expect(admission.build.buildIdentifier == "Capture Build V14-abcdef012345")
        #expect(admission.build.buildInstanceID == buildInstanceID)
        #expect(admission.build.sourceCommitSHA == sourceCommitSHA)
        #expect(admission.build.executableSHA256 == identity.executableSHA256)
        #expect(admission.build.infoPlistSHA256 == identity.infoPlistSHA256)
        #expect(admission.status == .goPrivateResearchBuild(admission.build))
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate
                .permitsPhysicalProcedure(status: admission.status)
        )

        // TODAY research authority is instance-bound. It must not mutate the default/release gate.
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("missing or wrong field recipe cannot mint research admission")
    func fieldRecipeIsMandatoryAndExact() throws {
        let identity = try makeRuntimeIdentity()
        var missing = infoDictionary()
        missing.removeValue(
            forKey: PassiveBluetoothExperimentOneFieldExecutionGate.fieldRecipeInfoDictionaryKey
        )
        #expect(throws: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchAdmissionError.missingFieldRecipe) {
            _ = try PassiveBluetoothExperimentOneFieldExecutionGate.researchAdmission(
                infoDictionary: missing,
                runtimeBuildIdentity: identity
            )
        }

        var wrong = infoDictionary()
        wrong[PassiveBluetoothExperimentOneFieldExecutionGate.fieldRecipeInfoDictionaryKey]
            = "ES80-FINGERPRINT-v999"
        #expect(throws: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchAdmissionError.unsupportedFieldRecipe) {
            _ = try PassiveBluetoothExperimentOneFieldExecutionGate.researchAdmission(
                infoDictionary: wrong,
                runtimeBuildIdentity: identity
            )
        }
    }

    @Test("embedded build tuple must match the independently resolved runtime identity")
    func embeddedBuildTupleCannotDriftFromRuntimeIdentity() throws {
        let identity = try makeRuntimeIdentity()
        var mismatched = infoDictionary()
        mismatched[PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey]
            = "00000000-0000-4000-8000-000000000000"

        #expect(throws: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchAdmissionError.buildMetadataMismatch) {
            _ = try PassiveBluetoothExperimentOneFieldExecutionGate.researchAdmission(
                infoDictionary: mismatched,
                runtimeBuildIdentity: identity
            )
        }
    }

    @Test("generic field-marked build is rejected unless build identifier matches exact source")
    func buildIdentifierMustMatchCanonicalSignedFieldProducerShape() throws {
        let identity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-wrongsource00",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
        var metadata = infoDictionary()
        metadata[PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey]
            = identity.buildIdentifier

        #expect(
            throws: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchAdmissionError
                .nonCanonicalResearchBuildIdentifier
        ) {
            _ = try PassiveBluetoothExperimentOneFieldExecutionGate.researchAdmission(
                infoDictionary: metadata,
                runtimeBuildIdentity: identity
            )
        }
    }

    @Test("research factory acquires package admission before any CoreBluetooth construction")
    func researchFactoryOrdersAuthorityBeforeTransport() throws {
        let source = try sourceFile(
            "Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator+CanonicalES80.swift"
        )
        let researchStart = try #require(
            source.range(of: "static func makeResearchAuthorizedES80ForCurrentApplication() throws")?.lowerBound
        )
        let releaseFactory = try #require(
            source.range(
                of: "private static func makeLiveES80Coordinator() throws",
                range: researchStart..<source.endIndex
            )?.lowerBound
        )
        let researchFactory = source[researchStart..<releaseFactory]
        let admission = try #require(
            researchFactory.range(of: ".researchAdmissionForCurrentApplication()")
        )
        let handoff = try #require(
            researchFactory.range(of: "makeLiveResearchES80Coordinator(admission: admission)")
        )
        #expect(admission.lowerBound < handoff.lowerBound)

        let researchLiveStart = try #require(
            source.range(of: "private static func makeLiveResearchES80Coordinator(")?.lowerBound
        )
        let researchLive = source[researchLiveStart...]
        let controller = try #require(
            researchLive.range(of: "ForegroundCoreBluetoothCaptureController(")
        )
        let boundInitializer = try #require(
            researchLive.range(of: "researchAdmission: admission")
        )
        #expect(controller.lowerBound < boundInitializer.lowerBound)
        #expect(!researchLive.contains("fieldExecutionStatus: admission.status"))
        #expect(!researchFactory.contains("UserDefaults"))
        #expect(!researchFactory.contains("ProcessInfo"))
        #expect(!researchFactory.contains("authorized: Bool"))
    }

    private func infoDictionary() -> [String: Any] {
        [
            PassiveBluetoothExperimentOneFieldExecutionGate.fieldRecipeInfoDictionaryKey:
                PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                "Capture Build V14-abcdef012345",
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                buildInstanceID,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                sourceCommitSHA,
        ]
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: infoDictionary(),
            executableData: executableData,
            infoPlistData: infoPlistData
        )
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
}
