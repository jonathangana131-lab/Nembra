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
    }

    @Test("authentication and official SDK connection both consume their ordered capability admissions")
    func authenticationAndOfficialConnectionAreCapabilityGated() throws {
        let section = try section(
            from: "func authenticate()",
            through: "private func authenticated(token: TuyaReadOnlyConnectionToken)"
        )
        let authenticationAdmission = try #require(
            section.range(of: "admitAuthenticationStart()")
        )
        let connectionAdmission = try #require(
            section.range(of: "admitOfficialConnectionStart()")
        )
        let connect = try #require(section.range(of: "newDriver.connect("))

        #expect(authenticationAdmission.lowerBound < connectionAdmission.lowerBound)
        #expect(connectionAdmission.lowerBound < connect.lowerBound)
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
    }

    @Test("unfinished authority has an app lifecycle revocation path")
    func unfinishedAuthorityCanBeRevoked() throws {
        let app = try source()

        #expect(app.contains(".revoke()"))
        #expect(app.contains("func appDidLoseForeground()"))
        #expect(app.contains("func abandonCorrelationForViewExit()"))
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
