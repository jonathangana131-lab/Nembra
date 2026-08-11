import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field GO prerequisite consumption")
struct TuyaFieldGoPrerequisiteSourceTests {
    @Test("field app consumes exact compiled build provenance before physical authority")
    func buildProvenanceIsProductAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(app.contains("NembraCaptureBuildIdentity.current"))
        #expect(app.contains("isAuthoritativeFieldBuild"))
        #expect(app.contains("buildIdentifier"))
        #expect(app.contains("sourceCommitSHA"))
        #expect(project.contains("NembraCaptureBuildIdentity.swift in Sources"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureBuildIdentifier"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureSourceCommitSHA"))
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

        guard let baseline = app.range(of: "func startBaseline()"),
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

    @Test("canonical acceptance is impossible when compiled build provenance is not authoritative")
    func acceptanceChecksBuildIdentityAtTheSealBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let ready = app.range(of: "case .readyForStationaryMapping:"),
              let accepted = app.range(of: "phase = .accepted", range: ready.upperBound..<app.endIndex),
              let buildCheck = app.range(of: "isAuthoritativeFieldBuild", range: ready.upperBound..<accepted.lowerBound) else {
            Issue.record("The canonical-ready path must re-check exact compiled build provenance before UI acceptance.")
            return
        }
        #expect(ready.lowerBound < buildCheck.lowerBound)
        #expect(buildCheck.lowerBound < accepted.lowerBound)
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
