import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture authenticated field-capability app wiring")
struct TuyaAuthenticatedFieldCapabilityAppWiringSourceTests {
    @Test("standalone Capture imports the app authorization module and owns the opaque lifecycle gate")
    func standaloneAppOwnsAuthorizationComposition() throws {
        let app = try source()

        #expect(app.contains("import NembraCaptureAppAuthorization"))
        #expect(app.contains("AuthenticatedStationaryCaptureAppAuthorizer"))
        #expect(app.contains("AuthenticatedStationaryCaptureCapabilityGate?"))
    }

    @Test("OFF1 cannot begin until the verifier-minted lifecycle gate admits the one allowed start")
    func off1StartIsCapabilityGated() throws {
        let section = try section(
            from: "private func beginBaselineAfterCurrentOperatorAttestation()",
            through: "private func beginCorrelationSeries()"
        )
        let admission = try #require(section.range(of: "admitOFF1Start()"))
        let correlation = try #require(section.range(of: "beginCorrelationSeries()"))

        #expect(admission.lowerBound < correlation.lowerBound)
        #expect(hasFailClosedGateResolution(before: admission.lowerBound, in: section))
    }

    @Test("authentication and official SDK connection both consume their ordered capability admissions")
    func authenticationAndOfficialConnectionAreCapabilityGated() throws {
        let authentication = try section(
            from: "func authenticate()",
            through: "private func beginOfficialConnection(candidate: Candidate)"
        )
        let authenticationAdmission = try #require(
            authentication.range(of: "admitAuthenticationStart()")
        )
        #expect(hasFailClosedGateResolution(
            before: authenticationAdmission.lowerBound,
            in: authentication
        ))

        let connection = try section(
            from: "private func beginOfficialConnection(candidate: Candidate)",
            through: "private func authenticated(token: TuyaReadOnlyConnectionToken)"
        )
        let connectionAdmission = try #require(
            connection.range(of: "admitOfficialConnectionStart()")
        )
        let connect = try #require(connection.range(of: "newDriver.connect("))

        #expect(connectionAdmission.lowerBound < connect.lowerBound)
        #expect(hasFailClosedGateResolution(
            before: connectionAdmission.lowerBound,
            in: connection
        ))
    }

    @Test("authenticated transport cannot become observation before capability admission")
    func observationPromotionIsCapabilityGated() throws {
        let section = try section(
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken)",
            through: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken)"
        )
        let admission = try #require(section.range(of: "admitObservationStart()"))
        let promotion = try #require(section.range(of: "phase = .observing"))

        #expect(admission.lowerBound < promotion.lowerBound)
        #expect(hasFailClosedGateResolution(before: admission.lowerBound, in: section))
    }

    @Test("accepted artifact promotion seals capability only after package accepted-prefix sealing")
    func acceptedArtifactSealsCapabilityAfterPackageFreeze() throws {
        let section = try section(
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            through: "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)"
        )
        let packageSeal = try #require(section.range(of: "sealAcceptedObservation(for: token)"))
        let capabilitySeal = try #require(section.range(of: ".seal()"))
        let acceptedPromotion = try #require(section.range(of: "self.phase = .accepted"))

        #expect(packageSeal.lowerBound < capabilitySeal.lowerBound)
        #expect(capabilitySeal.lowerBound < acceptedPromotion.lowerBound)
        #expect(hasFailClosedGateResolution(before: capabilitySeal.lowerBound, in: section))
    }

    @Test("a missing lifecycle gate can never be skipped by optional chaining")
    func missingGateFailsClosedInsteadOfSilentlySkippingAdmission() throws {
        let app = try source()

        for forbidden in [
            "fieldAuthorizationGate?.admitOFF1Start()",
            "fieldAuthorizationGate?.admitAuthenticationStart()",
            "fieldAuthorizationGate?.admitOfficialConnectionStart()",
            "fieldAuthorizationGate?.admitObservationStart()",
            "fieldAuthorizationGate?.seal()",
        ] {
            #expect(!app.contains(forbidden), "Optional authority admission would fail open: \(forbidden)")
        }
    }

    @Test("unfinished authority has an app lifecycle revocation path")
    func unfinishedAuthorityCanBeRevoked() throws {
        let app = try source()

        #expect(app.contains(".revoke()"))
        #expect(app.contains("fieldAuthorizationGate = nil"))
        #expect(app.contains("func appDidLoseForeground()"))
        #expect(app.contains("func abandonCorrelationForViewExit()"))
    }

    private func hasFailClosedGateResolution(
        before boundary: String.Index,
        in section: String
    ) -> Bool {
        let prefix = String(section[..<boundary])
        if prefix.contains("requireFieldAuthorizationGate(") {
            return true
        }
        guard let guardRange = prefix.range(of: "guard let", options: .backwards) else {
            return false
        }
        return prefix[guardRange.lowerBound...].contains("fieldAuthorizationGate")
    }

    private func section(from startMarker: String, through endMarker: String) throws -> String {
        let app = try source()
        let start = try #require(app.range(of: startMarker))
        let end = try #require(app.range(of: endMarker, range: start.upperBound..<app.endIndex))
        return String(app[start.lowerBound..<end.lowerBound])
    }

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }
}