import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture authenticated field-capability app wiring")
struct TuyaAuthenticatedFieldCapabilityAppWiringSourceTests {
    @Test("standalone Capture owns only the thin field-authorization controller")
    func standaloneAppOwnsThinAuthorizationComposition() throws {
        let app = try source()
        let adapter = try adapterSource()

        #expect(app.contains("private let fieldAuthorizationController = NembraCaptureFieldAuthorizationController()"))
        #expect(!app.contains("AuthenticatedStationaryCaptureAppAuthorizer"))
        #expect(!app.contains("AuthenticatedStationaryCaptureCapabilityGate"))
        #expect(adapter.contains("private let session: AuthenticatedStationaryCaptureAppSession"))
        #expect(adapter.contains("try session.prepare(installManifestData:"))
        #expect(adapter.contains("try session.acceptEnvelope(envelopeData)"))
    }

    @Test("OFF1 cannot begin until the single-use app session admits the one allowed start")
    func off1StartIsSessionGated() throws {
        let section = try section(
            from: "private func beginBaselineAfterCurrentOperatorAttestation()",
            through: "private func beginCorrelationSeries()"
        )
        let admission = try #require(section.range(of: "fieldAuthorizationController.admitOFF1Start()"))
        let correlation = try #require(section.range(of: "beginCorrelationSeries()"))

        #expect(admission.lowerBound < correlation.lowerBound)
        #expect(hasFailClosedAdmission(after: admission.lowerBound, in: section))
    }

    @Test("authentication and official SDK connection consume ordered session admissions")
    func authenticationAndOfficialConnectionAreSessionGated() throws {
        let authentication = try section(
            from: "func authenticate()",
            through: "private func beginOfficialConnection(candidate: Candidate)"
        )
        let authenticationAdmission = try #require(
            authentication.range(of: "fieldAuthorizationController.admitAuthenticationStart()")
        )
        #expect(hasFailClosedAdmission(
            after: authenticationAdmission.lowerBound,
            in: authentication
        ))

        let connection = try section(
            from: "private func beginOfficialConnection(candidate: Candidate)",
            through: "private func authenticated(token: TuyaReadOnlyConnectionToken)"
        )
        let connectionAdmission = try #require(
            connection.range(of: "fieldAuthorizationController.admitOfficialConnectionStart()")
        )
        let connect = try #require(connection.range(of: "newDriver.connect("))

        #expect(connectionAdmission.lowerBound < connect.lowerBound)
        #expect(hasFailClosedAdmission(
            after: connectionAdmission.lowerBound,
            in: connection
        ))
    }

    @Test("authenticated transport cannot become observation before session admission")
    func observationPromotionIsSessionGated() throws {
        let section = try section(
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken)",
            through: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken)"
        )
        let admission = try #require(
            section.range(of: "fieldAuthorizationController.admitObservationStart()")
        )
        let promotion = try #require(section.range(of: "phase = .observing"))

        #expect(admission.lowerBound < promotion.lowerBound)
        #expect(hasFailClosedAdmission(after: admission.lowerBound, in: section))
    }

    @Test("accepted artifact promotion seals session only after package accepted-prefix sealing")
    func acceptedArtifactSealsSessionAfterPackageFreeze() throws {
        let section = try section(
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            through: "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)"
        )
        let packageSeal = try #require(section.range(of: "sealAcceptedObservation(for: token)"))
        let sessionSeal = try #require(
            section.range(of: "fieldAuthorizationController.sealAfterAcceptedArtifactFreeze()")
        )
        let acceptedPromotion = try #require(section.range(of: "self.phase = .accepted"))

        #expect(packageSeal.lowerBound < sessionSeal.lowerBound)
        #expect(sessionSeal.lowerBound < acceptedPromotion.lowerBound)
        #expect(hasFailClosedAdmission(after: sessionSeal.lowerBound, in: section))
    }

    @Test("unfinished authority has explicit app lifecycle revocation paths")
    func unfinishedAuthorityCanBeRevoked() throws {
        let app = try source()

        #expect(app.contains("fieldAuthorizationController.revoke()"))
        #expect(app.contains("func appDidLoseForeground()"))
        #expect(app.contains("func abandonCorrelationForViewExit()"))
        #expect(app.contains("func invalidateSDKMembership()"))
    }

    @Test("entrypoint never owns or optional-chains the verifier capability")
    func entrypointDoesNotCreateParallelAuthorityState() throws {
        let app = try source()

        #expect(!app.contains("fieldAuthorizationGate"))
        #expect(!app.contains("AuthenticatedStationaryCaptureAttemptCapability"))
        #expect(!app.contains("AuthenticatedStationaryCaptureCapabilityGate"))
        #expect(!app.contains("?.admitOFF1Start()"))
        #expect(!app.contains("?.admitAuthenticationStart()"))
        #expect(!app.contains("?.admitOfficialConnectionStart()"))
        #expect(!app.contains("?.admitObservationStart()"))
    }

    private func hasFailClosedAdmission(
        after boundary: String.Index,
        in section: String
    ) -> Bool {
        let suffix = String(section[boundary...])
        guard let catchRange = suffix.range(of: "catch") else { return false }
        let postCatch = suffix[catchRange.lowerBound...]
        return postCatch.contains("failLocally(") || postCatch.contains("invalidateInternalLifecycle(")
    }

    private func section(from startMarker: String, through endMarker: String) throws -> String {
        let app = try source()
        let start = try #require(app.range(of: startMarker))
        let end = try #require(app.range(of: endMarker, range: start.upperBound..<app.endIndex))
        return String(app[start.lowerBound..<end.lowerBound])
    }

    private func source() throws -> String {
        try appSource(named: "NembraCaptureEntrypoint.swift")
    }

    private func adapterSource() throws -> String {
        try appSource(named: "NembraCaptureFieldAuthorizationController.swift")
    }

    private func appSource(named name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/\(name)"),
            encoding: .utf8
        )
    }
}