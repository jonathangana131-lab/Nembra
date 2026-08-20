import Foundation
import Testing
@testable import NembraBluetoothCapture

extension CaptureSimulatorQAHarnessSourceTests {
    @Test("authenticated field capability is consumed only through the thin app controller")
    func AuthenticatedFieldCapabilityAppWiring() throws {
        let app = try readAuthorityRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try readAuthorityRepositoryFile("NembraApp/App/NembraCaptureFieldAuthorizationController.swift")

        #expect(app.contains("private let fieldAuthorization = NembraCaptureFieldAuthorizationController()"))
        #expect(app.contains("advanceInboxHandoffIfAvailable()"))
        #expect(app.contains("fieldAuthorization.stage == .armed"))
        #expect(app.contains("admitOFF1Start()"))
        #expect(app.contains("admitAuthenticationStart()"))
        #expect(app.contains("admitOfficialConnectionStart()"))
        #expect(app.contains("admitObservationStart()"))
        #expect(app.contains("sealAfterAcceptedArtifactFreeze()"))

        let handoff = try authorityIndex(of: "advanceInboxHandoffIfAvailable()", in: app)
        let off1 = try authorityIndex(of: "admitOFF1Start()", in: app)
        let authentication = try authorityIndex(of: "admitAuthenticationStart()", in: app)
        let officialConnection = try authorityIndex(of: "admitOfficialConnectionStart()", in: app)
        let observation = try authorityIndex(of: "admitObservationStart()", in: app)
        let packageSeal = try authorityIndex(of: "sealAcceptedObservation(for: token)", in: app)
        let exactFreeze = try authorityIndex(of: "ExactByteArtifactSeal(sealing:", in: app)
        let authorizationSeal = try authorityIndex(of: "sealAfterAcceptedArtifactFreeze()", in: app)
        let accepted = try authorityIndex(of: "self.phase = .accepted", in: app)

        #expect(handoff < off1)
        #expect(off1 < authentication)
        #expect(authentication < officialConnection)
        #expect(officialConnection < observation)
        #expect(observation < packageSeal)
        #expect(packageSeal < exactFreeze)
        #expect(exactFreeze < authorizationSeal)
        #expect(authorizationSeal < accepted)

        #expect(!app.contains("fieldAuthorization?.admit"))
        #expect(!app.contains("fieldAuthorization?.sealAfterAcceptedArtifactFreeze"))
        #expect(!app.contains("AuthenticatedStationaryCaptureAttemptCapability"))
        #expect(!app.contains("AuthenticatedStationaryCaptureCapabilityGate"))

        #expect(controller.contains("import NembraCaptureAppAuthorization"))
        #expect(controller.contains("private let session: AuthenticatedStationaryCaptureAppSession"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureCapabilityGate?"))
        #expect(!controller.contains("AuthenticatedStationaryCaptureAppAuthorizer"))
    }

    @Test("authorization inbox adapter treats absence as wait and every present invalid subject as terminal")
    func AuthorizationInboxAppAdapter() throws {
        let controller = try readAuthorityRepositoryFile("NembraApp/App/NembraCaptureFieldAuthorizationController.swift")

        #expect(controller.contains("takeInstallManifest()"))
        #expect(controller.contains("takeAuthorizationEnvelope()"))
        #expect(controller.contains("retirePublishedRendezvous()"))
        #expect(controller.contains("session.acceptEnvelope(envelopeData)"))
        #expect(controller.contains("case .idle:"))
        #expect(controller.contains("case .awaitingEnvelope:"))
        #expect(controller.contains("case .armed:"))
        #expect(controller.contains("return .waitingForManifest"))
        #expect(controller.contains("return .waitingForEnvelope"))
        #expect(controller.contains("return .armed"))

        let manifestMissing = "catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(let subject)\n            where subject == AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename"
        let envelopeMissing = "catch AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(let subject)\n                where subject == AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename"
        #expect(controller.contains(manifestMissing))
        #expect(controller.contains(envelopeMissing))

        #expect(authorityOccurrences(of: "session.revoke()", in: controller) >= 4)
        #expect(!controller.contains("try? session.acceptEnvelope"))
        #expect(!controller.contains("try? prepareSignerRendezvousDocumentFromInbox"))
        #expect(!controller.contains("publishDps"))
        #expect(!controller.contains("writeValue"))
        #expect(!controller.contains("resetFactory"))
        #expect(!controller.contains("unbind"))
    }

    private func readAuthorityRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func authorityIndex(of needle: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: needle) else {
            Issue.record("Expected authority source token missing: \(needle)")
            throw CaptureFieldAuthorizationSourceContractError.tokenMissing
        }
        return range.lowerBound
    }

    private func authorityOccurrences(of needle: String, in source: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var remainder = source[...]
        while let range = remainder.range(of: needle) {
            count += 1
            remainder = remainder[range.upperBound...]
        }
        return count
    }

    private enum CaptureFieldAuthorizationSourceContractError: Error {
        case tokenMissing
    }
}
