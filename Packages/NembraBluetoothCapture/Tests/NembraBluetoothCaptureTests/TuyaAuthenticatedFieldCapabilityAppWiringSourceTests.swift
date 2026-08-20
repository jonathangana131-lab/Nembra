import Foundation
import Testing
@testable import NembraBluetoothCapture

/// The type name deliberately carries the existing V16 exact-head filter so these app-wiring
/// requirements cannot remain dormant while the standalone product advances.
@Suite("Capture authenticated field-capability app wiring")
struct CaptureSimulatorQAHarnessSourceTests_AuthenticatedFieldCapabilityAppWiring {
    @Test("standalone target compiles the app authorization coordinator")
    func standaloneTargetCompilesAuthorizationComposition() throws {
        let project = try repositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let coordinator = try repositoryFile(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )

        #expect(project.contains("NembraCaptureFieldAuthorizationController.swift in Sources"))
        #expect(project.contains("NembraCaptureAppAuthorization in Frameworks"))
        #expect(coordinator.contains("AuthenticatedStationaryCaptureAppSession"))
        #expect(!coordinator.contains("AuthenticatedStationaryCaptureCapabilityGate?"))
        #expect(!coordinator.contains("AuthenticatedStationaryCaptureAppAuthorizer"))
    }

    @Test("real SecureLink controller owns one app authorization coordinator")
    func secureLinkOwnsAuthorizationCoordinator() throws {
        let app = try appSource()

        #expect(app.contains("NembraCaptureFieldAuthorizationController"))
        #expect(app.contains("fieldAuthorization"))
    }

    @Test("OFF1 cannot begin until the app authorization session admits its one allowed start")
    func off1StartIsCapabilityGated() throws {
        let section = try appSection(
            from: "private func beginBaselineAfterCurrentOperatorAttestation()",
            through: "private func beginCorrelationSeries()"
        )
        let admission = try #require(section.range(of: "admitOFF1Start()"))
        let correlation = try #require(section.range(of: "beginCorrelationSeries()"))

        #expect(admission.lowerBound < correlation.lowerBound)
        #expect(hasFailClosedAuthorizationHandling(around: admission.lowerBound, in: section))
    }

    @Test("authentication and official SDK connection both consume ordered session admissions")
    func authenticationAndOfficialConnectionAreCapabilityGated() throws {
        let authentication = try appSection(
            from: "func authenticate()",
            through: "private func beginOfficialConnection(candidate: CaptureTargetDevice)"
        )
        let authenticationAdmission = try #require(
            authentication.range(of: "admitAuthenticationStart()")
        )
        #expect(hasFailClosedAuthorizationHandling(
            around: authenticationAdmission.lowerBound,
            in: authentication
        ))

        let connection = try appSection(
            from: "private func beginOfficialConnection(candidate: CaptureTargetDevice)",
            through: "private func authenticated(token: TuyaReadOnlyConnectionToken)"
        )
        let connectionAdmission = try #require(
            connection.range(of: "admitOfficialConnectionStart()")
        )
        let factory = try #require(connection.range(of: "OfficialTuyaFactory.make()"))
        let connect = try #require(connection.range(of: "newDriver.connect("))

        #expect(connectionAdmission.lowerBound < factory.lowerBound)
        #expect(connectionAdmission.lowerBound < connect.lowerBound)
        #expect(hasFailClosedAuthorizationHandling(
            around: connectionAdmission.lowerBound,
            in: connection
        ))
    }

    @Test("authenticated transport cannot become observation before session admission")
    func observationPromotionIsCapabilityGated() throws {
        let section = try appSection(
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken)",
            through: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken)"
        )
        let admission = try #require(section.range(of: "admitObservationStart()"))
        let promotion = try #require(section.range(of: "phase = .observing"))

        #expect(admission.lowerBound < promotion.lowerBound)
        #expect(hasFailClosedAuthorizationHandling(around: admission.lowerBound, in: section))
    }

    @Test("accepted artifact promotion seals session only after package accepted-prefix freeze")
    func acceptedArtifactSealsSessionAfterPackageFreeze() throws {
        let section = try appSection(
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            through: "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)"
        )
        let packageSeal = try #require(section.range(of: "sealAcceptedObservation(for: token)"))
        let capabilitySeal = try #require(
            section.range(of: "sealAfterAcceptedArtifactFreeze()")
        )
        let acceptedPromotion = try #require(section.range(of: "self.phase = .accepted"))

        #expect(packageSeal.lowerBound < capabilitySeal.lowerBound)
        #expect(capabilitySeal.lowerBound < acceptedPromotion.lowerBound)
        #expect(hasFailClosedAuthorizationHandling(
            around: capabilitySeal.lowerBound,
            in: section
        ))
    }

    @Test("authority admissions cannot be silently skipped by optional chaining")
    func missingAuthorityFailsClosedInsteadOfOptionalSkipping() throws {
        let app = try appSource()

        for forbidden in [
            "fieldAuthorization?.admitOFF1Start()",
            "fieldAuthorization?.admitAuthenticationStart()",
            "fieldAuthorization?.admitOfficialConnectionStart()",
            "fieldAuthorization?.admitObservationStart()",
            "fieldAuthorization?.sealAfterAcceptedArtifactFreeze()",
        ] {
            #expect(!app.contains(forbidden), "Optional authority admission would fail open: \(forbidden)")
        }
    }

    @Test("unfinished authority is revoked on foreground and view abandonment")
    func unfinishedAuthorityHasLifecycleRevocation() throws {
        let app = try appSource()
        let foreground = try appSection(
            from: "func appDidLoseForeground()",
            through: "func prepareForShare()"
        )
        let viewExit = try appSection(
            from: "func abandonCorrelationForViewExit()",
            through: "func appDidLoseForeground()"
        )

        #expect(app.contains("fieldAuthorization.revoke()"))
        #expect(foreground.contains("fieldAuthorization.revoke()"))
        #expect(viewExit.contains("fieldAuthorization.revoke()"))
    }

    private func hasFailClosedAuthorizationHandling(
        around boundary: String.Index,
        in section: String
    ) -> Bool {
        let prefix = String(section[..<boundary])
        let suffix = String(section[boundary...])
        let recentPrefix = String(prefix.suffix(1_000))
        let nearSuffix = String(suffix.prefix(1_000))
        let context = recentPrefix + nearSuffix
        return context.contains("do {")
            && context.contains("catch")
            && (context.contains("failLocally(")
                || context.contains("failAndRetireSession(")
                || context.contains("retireSession"))
    }

    private func appSection(from startMarker: String, through endMarker: String) throws -> String {
        let app = try appSource()
        let start = try #require(app.range(of: startMarker))
        let end = try #require(app.range(of: endMarker, range: start.upperBound..<app.endIndex))
        return String(app[start.lowerBound..<end.lowerBound])
    }

    private func appSource() throws -> String {
        try repositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
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
