import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Keep the one-shot app-container custody boundary on the V16 exact-head source-test surface.
@Suite("Capture authorization inbox app adapter")
struct CaptureSimulatorQAHarnessSourceTests_AuthorizationInboxAppAdapter {
    @Test("standalone adapter prepares from inbox and publishes the canonical signer rendezvous")
    func adapterPublishesPreparedRendezvous() throws {
        let controller = try repositoryFile(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )

        #expect(controller.contains("AuthenticatedStationaryCaptureAuthorizationInbox"))
        #expect(controller.contains("func prepareAttemptFromInbox()"))
        #expect(controller.contains(".takeInstallManifest()"))
        #expect(controller.contains("session.prepare(installManifestData: manifestData)"))
        #expect(controller.contains("AuthenticatedStationaryCaptureSignerRendezvousOutbox"))
        #expect(controller.contains(".publish(rendezvous)"))
        #expect(controller.contains("session.revoke()"))
    }

    @Test("standalone adapter authorizes only from the one-shot envelope inbox")
    func adapterUsesDescriptorBoundEnvelopeInbox() throws {
        let controller = try repositoryFile(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )

        #expect(controller.contains("func authorizeFromInbox() throws"))
        #expect(controller.contains(".takeAuthorizationEnvelope()"))
        #expect(controller.contains("session.acceptEnvelope(envelopeData)"))

        #expect(!controller.contains("retainedInstallManifestData: Data"))
        #expect(!controller.contains("func authorize(envelopeData: Data)"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureAppAuthorizer"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureCapabilityGate"))
    }

    @Test("standalone target actually compiles the inbox-bound adapter")
    func adapterRemainsInStandaloneTarget() throws {
        let project = try repositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(project.contains("NembraCaptureFieldAuthorizationController.swift in Sources"))
        #expect(project.contains("NembraCaptureAppAuthorization in Frameworks"))
    }

    private func repositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}