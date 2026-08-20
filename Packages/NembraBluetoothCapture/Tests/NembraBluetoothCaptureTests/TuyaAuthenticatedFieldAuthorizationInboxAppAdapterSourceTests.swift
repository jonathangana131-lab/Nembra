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

        // Consumed-manifest publication failure, outbound-rendezvous retirement failure, and any
        // later app lifecycle revocation must kill package authority. Normal revocation also retires
        // the non-authorizing rendezvous best-effort so an abandoned attempt cannot block the next
        // field attempt; cleanup failure remains fail-closed because publish is no-replace.
        #expect(controller.components(separatedBy: "session.revoke()").count - 1 >= 3)
        let revokeStart = try #require(controller.range(of: "func revoke() {"))
        let revokeTail = controller[revokeStart.lowerBound...]
        #expect(revokeTail.contains("session.revoke()"))
        #expect(revokeTail.contains("AuthenticatedStationaryCaptureSignerRendezvousOutbox"))
        #expect(revokeTail.contains(".retirePublishedRendezvous()"))

        #expect(!controller.contains("retainedInstallManifestData: Data"))
        #expect(!controller.contains("func authorize(envelopeData: Data)"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureAppAuthorizer"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureCapabilityGate"))
    }

    @Test("polling seam waits only for truly absent next files and never treats presence as authority")
    func pollingSeamSeparatesWaitingFromVerificationFailure() throws {
        let controller = try repositoryFile(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )
        let start = try #require(
            controller.range(of: "func advanceInboxHandoffIfAvailable() throws -> HandoffProgress")
        )
        let end = try #require(
            controller.range(
                of: "func admitOFF1Start() throws",
                range: start.upperBound..<controller.endIndex
            )
        )
        let section = String(controller[start.lowerBound..<end.lowerBound])

        #expect(section.contains("switch session.stage"))
        #expect(section.contains("case .idle:"))
        #expect(section.contains("prepareSignerRendezvousDocumentFromInbox()"))
        #expect(section.contains("case .awaitingEnvelope:"))
        #expect(section.contains("authorizeFromInbox()"))
        #expect(section.contains("AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject"))
        #expect(section.contains("AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename"))
        #expect(section.contains("AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename"))
        #expect(section.contains("return .waitingForManifest"))
        #expect(section.contains("return .waitingForEnvelope"))
        #expect(section.contains("return .armed"))

        // The polling seam may swallow only the exact missing-subject cases. It must not add a
        // catch-all that would convert malformed/custody/signature failures into a harmless wait.
        #expect(!section.contains("catch {"))
        #expect(!section.contains("try?"))
        #expect(!section.contains("return .armed\n            } catch"))
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