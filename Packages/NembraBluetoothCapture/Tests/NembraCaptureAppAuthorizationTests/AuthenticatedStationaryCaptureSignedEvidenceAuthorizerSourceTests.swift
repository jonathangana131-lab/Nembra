import Foundation
import Testing
@testable import NembraBluetoothCapture
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture signed-evidence app boundary")
struct AuthenticatedStationaryCaptureSignedEvidenceAuthorizerSourceTests {
    @Test("production challenge creation starts from exact signed-build evidence")
    func productionBeginAttemptDoesNotAcceptArbitraryBindingTuples() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppAuthorizer.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("public func beginAttempt(\n        signedBuildEvidenceData: Data"))
        #expect(source.contains("AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier"))
        #expect(source.contains(".decodeCanonical(signedBuildEvidenceData)"))
        #expect(source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()"))
        #expect(source.contains("signedBuildEvidenceDoesNotMatchRunningApplication"))
        #expect(source.contains("package func beginAttempt(\n        externalBindings:"))
        #expect(!source.contains("public func beginAttempt(\n        externalBindings:"))
        #expect(!source.contains("publicKeyX963Representation:"))
        #expect(!source.contains("isAuthoritativeFieldBuild = true"))
    }

    @Test("signed-build evidence remains non-authorizing until the independent envelope verifies")
    func signedEvidenceSourceContainsNoPhysicalCapabilityMint() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraBluetoothCapture/AuthenticatedStationaryCaptureSignedBuildEvidence.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("signed-field-artifact-digests-not-authorization"))
        #expect(source.contains("signedBuildEvidenceSHA256: canonicalEvidenceSHA256"))
        #expect(!source.contains("AuthenticatedStationaryCaptureAttemptCapability("))
        #expect(!source.contains("permitsPhysicalProcedure"))
        #expect(!source.contains("publicKeyX963Representation"))
    }
}