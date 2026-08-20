import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture app session")
@MainActor
struct AuthenticatedStationaryCaptureAppSessionTests {
    @Test("unfinished session revocation is terminal and idempotent")
    func revokeIsTerminal() {
        let session = AuthenticatedStationaryCaptureAppSession()
        #expect(session.stage == .idle)

        session.revoke()
        #expect(session.stage == .revoked)
        session.revoke()
        #expect(session.stage == .revoked)
    }

    @Test("ordered authority transitions fail closed before authorization")
    func authorityTransitionsRequireArmedSession() {
        let session = AuthenticatedStationaryCaptureAppSession()

        #expect(throws: AuthenticatedStationaryCaptureAppSessionError.invalidTransition) {
            try session.admitOFF1Start()
        }
        #expect(throws: AuthenticatedStationaryCaptureAppSessionError.invalidTransition) {
            try session.admitAuthenticationStart()
        }
        #expect(throws: AuthenticatedStationaryCaptureAppSessionError.invalidTransition) {
            try session.admitOfficialConnectionStart()
        }
        #expect(throws: AuthenticatedStationaryCaptureAppSessionError.invalidTransition) {
            try session.admitObservationStart()
        }
        #expect(throws: AuthenticatedStationaryCaptureAppSessionError.invalidTransition) {
            try session.sealAfterAcceptedArtifactFreeze()
        }
    }

    @Test("session source keeps prepared bytes and opaque capability private")
    func sourceKeepsAuthorityPrivateAndSingleUse() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppSession.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("private var preparedAttempt:"))
        #expect(source.contains("private var retainedInstallManifestData: Data?"))
        #expect(source.contains("private var capabilityGate: AuthenticatedStationaryCaptureCapabilityGate?"))
        #expect(source.contains("authorizer.beginAttempt(installManifestData:"))
        #expect(source.contains("capabilityGate = try authorizer.authorize("))
        #expect(source.contains("self.preparedAttempt = nil"))
        #expect(source.contains("self.retainedInstallManifestData = nil"))
        #expect(source.contains("catch {\n            revoke()\n            throw error"))
        #expect(source.contains("try capabilityGate.admitOFF1Start()"))
        #expect(source.contains("try capabilityGate.admitAuthenticationStart()"))
        #expect(source.contains("try capabilityGate.admitOfficialConnectionStart()"))
        #expect(source.contains("try capabilityGate.admitObservationStart()"))
        #expect(source.contains("try capabilityGate.seal()"))
        #expect(source.contains("capabilityGate?.revoke()"))
        #expect(!source.contains("AuthenticatedStationaryCaptureAttemptCapability"))
        #expect(!source.contains("publicKeyX963Representation"))
        #expect(!source.contains("permitsPhysicalProcedure"))
        #expect(!source.contains("reset()"))
    }

    @Test("signer rendezvous exposes no raw manifest or capability")
    func signerRendezvousIsMinimal() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppSession.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try #require(source.range(of: "public struct SignerRendezvous"))
        let end = try #require(
            source.range(of: "public private(set) var stage", range: start.upperBound..<source.endIndex)
        )
        let rendezvous = String(source[start.lowerBound..<end.lowerBound])

        #expect(rendezvous.contains("challengeSHA256"))
        #expect(rendezvous.contains("startedAtWallClockUnixMilliseconds"))
        #expect(rendezvous.contains("startedAtUptimeNanoseconds"))
        #expect(rendezvous.contains("procedureID"))
        #expect(!rendezvous.contains("manifest"))
        #expect(!rendezvous.contains("capability"))
        #expect(!rendezvous.contains("envelope"))
    }
}
