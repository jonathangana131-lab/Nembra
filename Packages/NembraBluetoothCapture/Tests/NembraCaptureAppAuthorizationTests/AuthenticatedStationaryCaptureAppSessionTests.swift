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

    @Test("out-of-order authority transitions terminally revoke the attempt")
    func invalidOrderingRevokesAttempt() {
        let actions: [(AuthenticatedStationaryCaptureAppSession) throws -> Void] = [
            { try $0.acceptEnvelope(Data()) },
            { try $0.admitOFF1Start() },
            { try $0.admitAuthenticationStart() },
            { try $0.admitOfficialConnectionStart() },
            { try $0.admitObservationStart() },
            { try $0.sealAfterAcceptedArtifactFreeze() },
        ]

        for action in actions {
            let session = AuthenticatedStationaryCaptureAppSession()
            #expect(throws: AuthenticatedStationaryCaptureAppSessionError.invalidTransition) {
                try action(session)
            }
            #expect(session.stage == .revoked)
        }
    }

    @Test("session source keeps prepared bytes and opaque capability private")
    func sourceKeepsAuthorityPrivateAndSingleUse() throws {
        let source = try sessionSource()

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

    @Test("every post-authorization gate failure synchronizes the outer session to revoked")
    func everyGateFailureRevokesOuterSession() throws {
        let source = try sessionSource()
        for function in [
            "public func admitOFF1Start() throws",
            "public func admitAuthenticationStart() throws",
            "public func admitOfficialConnectionStart() throws",
            "public func admitObservationStart() throws",
            "public func sealAfterAcceptedArtifactFreeze() throws",
        ] {
            let body = try functionBody(function, in: source)
            #expect(body.contains("catch {"), "Missing failure boundary in \(function)")
            #expect(body.contains("revoke()"), "Gate failure can leave stale outer stage in \(function)")
            #expect(body.contains("throw error"), "Gate failure must preserve the original cause in \(function)")
        }
    }

    @Test("signer rendezvous exposes no raw manifest or capability")
    func signerRendezvousIsMinimal() throws {
        let source = try sessionSource()
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

    private func functionBody(_ marker: String, in source: String) throws -> String {
        let start = try #require(source.range(of: marker))
        let next = source.range(of: "\n    public func ", range: start.upperBound..<source.endIndex)
            ?? source.range(of: "\n    /// Terminally retires", range: start.upperBound..<source.endIndex)
            ?? source.endIndex..<source.endIndex
        return String(source[start.lowerBound..<next.lowerBound])
    }

    private func sessionSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppSession.swift"
            )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}