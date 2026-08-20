import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field GO prerequisite consumption")
struct TuyaFieldGoPrerequisiteSourceTests {
    @Test("field app keeps compiled build provenance as a prerequisite and signed session as authority")
    func buildProvenanceIsPrerequisiteNotAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let plist = try readRepositoryFile("NembraCapture-Info.plist")

        #expect(app.contains("NembraCaptureBuildIdentity.current"))
        #expect(app.contains("hasCompleteFieldBuildMetadata"))
        #expect(app.contains("fieldAuthorization.stage == .armed"))
        #expect(app.contains("fieldAuthorization.admitOFF1Start()"))
        #expect(!app.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(identity.contains("var isAuthoritativeFieldBuild: Bool {\n        false\n    }"))
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
              let admission = app.range(of: "fieldAuthorization.admitOFF1Start()", range: baseline.upperBound..<app.endIndex),
              let correlationStart = app.range(of: "self.beginCorrelationSeries()", range: admission.upperBound..<app.endIndex),
              let baselineLease = app.range(of: "TuyaSDKAccountIdentityLeaseGate.verdict", range: baseline.upperBound..<admission.lowerBound) else {
            Issue.record("OFF1 correlation must revalidate the account-bound membership lease and consume signed session authority before package correlation starts.")
            return
        }
        #expect(baseline.lowerBound < baselineLease.lowerBound)
        #expect(baselineLease.lowerBound < admission.lowerBound)
        #expect(admission.lowerBound < correlationStart.lowerBound)
    }

    @Test("account authority loss has a dedicated terminal instead of masquerading as continuity or disconnect")
    func sourceAuthorityLossIsConsumedTruthfully() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let ledger = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")

        #expect(ledger.contains("markSourceAuthorityInvalidated"))
        #expect(ledger.contains("Tuya SDK source authority was invalidated."))
        #expect(app.contains("markSourceAuthorityInvalidated"))
        #expect(app.contains("fieldAuthorization.revoke()"))

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
              let markAuthenticated = app.range(of: "sessionLedger.markAuthenticated", range: authenticated.upperBound..<nextFunction.lowerBound),
              let observationAdmission = app.range(of: "fieldAuthorization.admitObservationStart()", range: authenticated.upperBound..<nextFunction.lowerBound) else {
            Issue.record("Tuya transport-success handling must settle local BLE and consume one-time observation authority before observing.")
            return
        }
        #expect(settlement.lowerBound < markAuthenticated.lowerBound)
        #expect(markAuthenticated.lowerBound < observationAdmission.lowerBound)
        #expect(app.contains("TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds"))
    }

    @Test("canonical acceptance rechecks metadata and live observation authority at both seal boundaries")
    func acceptanceChecksIndependentAuthorityAtSealBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let ready = app.range(of: "case .readyForStationaryMapping:"),
              let accepted = app.range(of: "self.phase = .accepted", range: ready.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate canonical-ready acceptance path.")
            return
        }
        let acceptance = String(app[ready.lowerBound..<accepted.lowerBound])
        #expect(acceptance.occurrenceCount(of: "buildIdentity.hasCompleteFieldBuildMetadata") >= 2)
        #expect(acceptance.occurrenceCount(of: "fieldAuthorization.stage == .observationAdmitted") >= 2)
        #expect(acceptance.contains("freezeAcceptedArtifactForAuthorizationSeal()"))
        #expect(acceptance.contains("fieldAuthorization.sealAfterAcceptedArtifactFreeze()"))
        let live = try #require(acceptance.range(of: "fieldAuthorization.stage == .observationAdmitted"))
        let seal = try #require(acceptance.range(of: "fieldAuthorization.sealAfterAcceptedArtifactFreeze()"))
        #expect(live.lowerBound < seal.lowerBound)
        #expect(!acceptance.contains("isAuthoritativeFieldBuild"))
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

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        var count = 0
        var searchStart = startIndex
        while searchStart < endIndex,
              let match = range(of: needle, range: searchStart..<endIndex) {
            count += 1
            searchStart = match.upperBound
        }
        return count
    }
}
