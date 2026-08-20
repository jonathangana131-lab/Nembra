import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture carrier authenticated field capability app wiring")
struct CaptureSimulatorQAHarnessSourceTests_AuthenticatedFieldCapabilityAppWiring {
    @Test("real entrypoint either owns the complete reviewed lifecycle or the pinned materializer owns that exact transition")
    func entrypointLifecycleIsCompleteOrPinnedForMaterialization() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        if app.contains("private let fieldAuthorization = NembraCaptureFieldAuthorizationController()") {
            let handoff = try #require(app.range(of: "advanceInboxHandoffIfAvailable()"))
            let off1 = try #require(app.range(of: "admitOFF1Start()"))
            let authentication = try #require(app.range(of: "admitAuthenticationStart()"))
            let connection = try #require(app.range(of: "admitOfficialConnectionStart()"))
            let observation = try #require(app.range(of: "admitObservationStart()"))
            let freeze = try #require(app.range(of: "ExactByteArtifactSeal(sealing:"))
            let seal = try #require(app.range(of: "sealAfterAcceptedArtifactFreeze()"))
            let accepted = try #require(app.range(of: "self.phase = .accepted"))

            #expect(handoff.lowerBound < off1.lowerBound)
            #expect(off1.lowerBound < authentication.lowerBound)
            #expect(authentication.lowerBound < connection.lowerBound)
            #expect(connection.lowerBound < observation.lowerBound)
            #expect(freeze.lowerBound < seal.lowerBound)
            #expect(seal.lowerBound < accepted.lowerBound)
            #expect(app.contains("fieldAuthorization.stage == .armed"))
            #expect(app.contains("fieldAuthorization.stage != .armed"))
            #expect(app.contains("fieldAuthorization.revoke()"))
            #expect(!app.contains("fieldAuthorization?.admit"))
            #expect(!app.contains("isAuthoritativeFieldBuild = true"))
        } else {
            let workflow = try readRepositoryFile(".github/workflows/capture-carrier-authority-v2-materialize-once.yml")
            #expect(workflow.contains("EXPECTED_SOURCE_BLOB: 627c17949d15aaf26ca28c12abb9bb684ab0e731"))
            #expect(workflow.contains("private let fieldAuthorization = NembraCaptureFieldAuthorizationController()"))
            #expect(workflow.contains("advanceInboxHandoffIfAvailable()"))
            #expect(workflow.contains("admitOFF1Start()"))
            #expect(workflow.contains("admitAuthenticationStart()"))
            #expect(workflow.contains("admitOfficialConnectionStart()"))
            #expect(workflow.contains("admitObservationStart()"))
            #expect(workflow.contains("ExactByteArtifactSeal(sealing:"))
            #expect(workflow.contains("sealAfterAcceptedArtifactFreeze()"))
            #expect(workflow.contains("git diff --check"))
        }
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

@Suite("Capture carrier authorization inbox adapter")
struct CaptureSimulatorQAHarnessSourceTests_AuthorizationInboxAppAdapter {
    @Test("app adapter remains a thin one-shot inbox bridge over package-owned authority")
    func adapterFailsClosedAndNeverCreatesParallelAuthority() throws {
        let controller = try readRepositoryFile("NembraApp/App/NembraCaptureFieldAuthorizationController.swift")

        #expect(controller.contains("private let session: AuthenticatedStationaryCaptureAppSession"))
        #expect(controller.contains("AuthenticatedStationaryCaptureAuthorizationInbox()"))
        #expect(controller.contains("takeInstallManifest()"))
        #expect(controller.contains("takeAuthorizationEnvelope()"))
        #expect(controller.contains("AuthenticatedStationaryCaptureSignerRendezvousOutbox()"))
        #expect(controller.contains("retirePublishedRendezvous()"))
        #expect(controller.contains("func advanceInboxHandoffIfAvailable() throws -> HandoffProgress"))
        #expect(controller.contains("case .idle:"))
        #expect(controller.contains("return .waitingForManifest"))
        #expect(controller.contains("case .awaitingEnvelope:"))
        #expect(controller.contains("return .waitingForEnvelope"))
        #expect(controller.contains("case .armed:"))
        #expect(controller.contains("return .armed"))
        #expect(controller.contains("case .off1Started, .authenticationAdmitted, .officialConnectionAdmitted, .observationAdmitted:"))
        #expect(controller.contains("return .lifecycleInProgress"))
        #expect(controller.contains("case .sealed:"))
        #expect(controller.contains("return .sealed"))
        #expect(controller.contains("case .revoked:"))
        #expect(controller.contains("return .revoked"))

        for delegatedAdmission in [
            "try session.admitOFF1Start()",
            "try session.admitAuthenticationStart()",
            "try session.admitOfficialConnectionStart()",
            "try session.admitObservationStart()",
            "try session.sealAfterAcceptedArtifactFreeze()"
        ] {
            #expect(controller.contains(delegatedAdmission), "missing package-owned lifecycle delegation: \(delegatedAdmission)")
        }

        #expect(controller.contains("session.revoke()"))
        #expect(!controller.contains("isAuthoritativeFieldBuild = true"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureAttemptCapability"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureCapabilityGate"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
