import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Keep the one-shot app-container custody boundary on the V16 exact-head source-test surface.
@Suite("Capture authorization inbox app adapter")
struct CaptureSimulatorQAHarnessSourceTests_AuthorizationInboxAppAdapter {
    @Test("standalone adapter only prepares and authorizes through package custody primitives")
    func adapterUsesDescriptorBoundTransport() throws {
        let controller = try repositoryFile(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )

        #expect(controller.contains("AuthenticatedStationaryCaptureAuthorizationInbox"))
        #expect(controller.contains("private func prepareAttemptFromInbox()"))
        #expect(controller.contains(".takeInstallManifest()"))
        #expect(controller.contains("func prepareSignerRendezvousDocumentFromInbox() throws -> Data"))
        #expect(controller.contains("AuthenticatedStationaryCaptureSignerRendezvousOutbox"))
        #expect(controller.contains(".publish(rendezvous)"))
        #expect(controller.contains("func authorizeFromInbox() throws"))
        #expect(controller.contains(".takeAuthorizationEnvelope()"))
        #expect(controller.contains("outbox.retirePublishedRendezvous()"))
        #expect(controller.contains("session.prepare(installManifestData: manifestData)"))
        #expect(controller.contains("session.acceptEnvelope(envelopeData)"))

        // Both consumed-manifest publication failure and outbound-rendezvous retirement failure
        // must kill the attempt before any hidden retry/authority path can survive.
        #expect(controller.components(separatedBy: "session.revoke()").count - 1 >= 2)

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