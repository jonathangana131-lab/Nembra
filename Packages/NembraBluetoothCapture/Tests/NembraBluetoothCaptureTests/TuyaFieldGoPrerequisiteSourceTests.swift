import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field GO prerequisite consumption")
struct TuyaFieldGoPrerequisiteSourceTests {
    @Test("field app consumes exact compiled metadata while physical authority stays independently signed")
    func buildProvenanceRemainsNonAuthorizingMetadata() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let plist = try readRepositoryFile("NembraCapture-Info.plist")

        #expect(app.contains("NembraCaptureBuildIdentity.current"))
        #expect(app.contains("hasCompleteFieldBuildMetadata"))
        #expect(identity.contains("var isAuthoritativeFieldBuild: Bool {\n        false\n    }"))
        #expect(app.contains("fieldAuthorization"))
        #expect(app.contains("buildIdentifier"))
        #expect(app.contains("sourceCommitSHA"))
        #expect(project.contains("NembraCaptureBuildIdentity.swift in Sources"))
        #expect(plist.contains("<key>NembraCaptureBuildIdentifier</key>"))
        #expect(plist.contains("<key>NembraCaptureBuildInstanceID</key>"))
        #expect(plist.contains("<string>$(NEMBRA_CAPTURE_BUILD_INSTANCE_ID)</string>"))
        #expect(plist.contains("<key>NembraCaptureBuildCommitSHA</key>"))
        #expect(plist.contains("<string>$(NEMBRA_CAPTURE_BUILD_COMMIT_SHA)</string>"))
        #expect(!plist.contains("<key>NembraCaptureSourceCommitSHA</key>"))
    }

    @Test("membership proof is leased to the same current Tuya account UID")
    func accountIdentityLeaseIsRevalidated() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(app.contains("currentAccountUID"))
        #expect(app.contains("membershipAccountUID"))
        #expect(app.contains("membershipDeviceID"))
        #expect(app.contains("ThingSmartUser.sharedInstance()?.uid"))
        #expect(app.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))

        guard let baseline = app.range(of: "private func beginBaselineAfterCurrentOperatorAttestation()"),
              let correlationStart = app.range(of: "self.beginCorrelationSeries()", range: baseline.upperBound..<app.endIndex),
              let baselineLease = app.range(of: "TuyaSDKAccountIdentityLeaseGate.verdict", range: baseline.upperBound..<correlationStart.lowerBound) else {
            Issue.record("OFF1 correlation must revalidate the account-bound membership lease before the package-owned correlation series starts.")
            return
        }
        #expect(baseline.lowerBound < baselineLease.lowerBound)
        #expect(baselineLease.lowerBound < correlationStart.lowerBound)
    }

    @Test("account authority loss has a dedicated terminal instead of masquerading as continuity or disconnect")
    func sourceAuthorityLossIsConsumedTruthfully() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let ledger = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")

        #expect(ledger.contains("markSourceAuthorityInvalidated"))
        #expect(ledger.contains("Tuya SDK source authority was invalidated."))
        #expect(app.contains("markSourceAuthorityInvalidated"))

        guard let invalidationHelper = app.range(of: "invalidateSourceAuthority"),
              let terminalCall = app.range(
                of: "markSourceAuthorityInvalidated",
                range: invalidationHelper.lowerBound..<app.endIndex
              ) else {
            Issue.record("Field app needs an explicit source-authority invalidation path backed by the package terminal.")
            return
        }
        #expect(invalidationHelper.lowerBound < terminalCall.lowerBound)
    }

    @Test("account UID remains source authority only and is excluded from export")
    func accountUIDIsNotArtifactContent() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let exportStart = app.range(of: "struct Export"),
              let exportEnd = app.range(of: "struct Event", range: exportStart.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate Export schema.")
            return
        }
        let exportSchema = String(app[exportStart.lowerBound..<exportEnd.lowerBound])
        #expect(!exportSchema.contains("AccountUID"))
        #expect(!exportSchema.contains("accountUID"))
        #expect(!exportSchema.contains("membershipAccountUID"))
    }

    @Test("transport success uses bounded local-status settlement before authentication authority")
    func localStatusSettlesBeforeAuthenticationChronology() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let nextFunction = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex),
              let settlement = app.range(of: "TuyaLocalBLEAcquisitionWindow.verdict", range: authenticated.upperBound..<nextFunction.lowerBound),
              let markAuthenticated = app.range(of: "sessionLedger.markAuthenticated", range: authenticated.upperBound..<nextFunction.lowerBound) else {
            Issue.record("Tuya transport-success handling must use the bounded local-BLE settlement window before marking authenticated.")
            return
        }
        #expect(settlement.lowerBound < markAuthenticated.lowerBound)
        #expect(app.contains("TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds"))
    }

    @Test("canonical acceptance retains complete metadata plus signed observation authority through sealing")
    func acceptanceChecksSignedAttemptAtTheSealBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let watchdogStart = app.range(of: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)"),
              let watchdogEnd = app.range(of: "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)", range: watchdogStart.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate canonical acceptance watchdog.")
            return
        }
        let watchdog = String(app[watchdogStart.lowerBound..<watchdogEnd.lowerBound])

        #expect(watchdog.contains("buildIdentity.hasCompleteFieldBuildMetadata"))
        #expect(watchdog.contains("fieldAuthorizationObservationAdmitted"))
        #expect(!watchdog.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(watchdog.contains("freezeAcceptedArtifactForAuthorizationSeal()"))
        #expect(watchdog.contains("fieldAuthorization.sealAfterAcceptedArtifactFreeze()"))

        let metadataCheck = try #require(watchdog.range(of: "buildIdentity.hasCompleteFieldBuildMetadata"))
        let observationAuthority = try #require(watchdog.range(of: "fieldAuthorizationObservationAdmitted"))
        let freeze = try #require(watchdog.range(of: "freezeAcceptedArtifactForAuthorizationSeal()"))
        let signedSeal = try #require(watchdog.range(of: "fieldAuthorization.sealAfterAcceptedArtifactFreeze()"))
        let accepted = try #require(watchdog.range(of: "self.phase = .accepted"))
        #expect(metadataCheck.lowerBound < freeze.lowerBound)
        #expect(observationAuthority.lowerBound < freeze.lowerBound)
        #expect(freeze.lowerBound < signedSeal.lowerBound)
        #expect(signedSeal.lowerBound < accepted.lowerBound)
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