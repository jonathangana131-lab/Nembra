import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field authenticated-preflight integration")
struct TuyaFieldAppPreflightIntegrationSourceTests {
    @Test("field app uses structured application-update chronology without invented bytes")
    func structuredSDKUpdateIsNotFabricatedIntoTransportBytes() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("recordApplicationUpdate(isNonEmpty:"))
        #expect(source.contains("!update.isEmpty"))
        #expect(source.contains("for: token"))
        #expect(!source.contains("recordApplicationPayload("))
        #expect(!source.contains("JSONSerialization.data(withJSONObject: update"))
        #expect(source.contains("rawFD50BytesCaptured: false"))
        #expect(source.contains("dpQueriesSent: false"))
        #expect(source.contains("dpCommandsSent: false"))
    }

    @Test("only the accepted prior physical UUID authorizes the current target")
    func targetAuthorityDoesNotPromoteHints() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("var likely: Bool { knownID }"))
        #expect(!source.contains("score >= 600"))
        #expect(!source.contains("knownID || (fd50 && tuyaCompany)"))
        #expect(source.contains("accepted-prior-physical-corebluetooth-uuid"))
    }

    @Test("official Tuya connect failure uses documented no-error handler")
    func connectBLEFailureShapeIsCurrent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("failure: @escaping () -> Void"))
        #expect(!source.contains("failure: @escaping (String) -> Void"))
        #expect(!source.contains("failure: { error in"))
    }

    @Test("a fresh exact scooter membership verdict is required before CoreBluetooth scan")
    func membershipPrecedesDiscovery() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let start = source.range(of: "func startBaseline()"),
              let verify = source.range(of: "verifySDKMembership", range: start.upperBound..<source.endIndex),
              let begin = source.range(of: "self.beginBaselineScan()", range: verify.upperBound..<source.endIndex),
              let scan = source.range(of: "central.scanForPeripherals", range: begin.upperBound..<source.endIndex) else {
            Issue.record("Field source must re-verify SDK membership before beginning the OFF baseline scan.")
            return
        }
        #expect(start.lowerBound < verify.lowerBound)
        #expect(verify.lowerBound < begin.lowerBound)
        #expect(begin.lowerBound < scan.lowerBound)
        #expect(source.contains("sdk_device_membership_required_before_scan"))
    }

    @Test("canonical preflight remains the stationary readiness authority")
    func canonicalAuthorityRemainsIntegrated() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("import NembraBluetoothCapture"))
        #expect(source.contains("TuyaAuthenticatedReadOnlySessionLedger()"))
        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: ledgerSnapshot)"))
        #expect(source.contains("authoritativePreflightReady"))
        #expect(source.contains("var passed: Bool"))
        #expect(source.contains("TuyaSDKAccountDeviceMembershipGate.verdict"))
        #expect(!source.contains("central.connect("))
    }

    @Test("observation suspension cannot be counted into the forty five second gate")
    func suspensionGapFailsClosedBeforeObservationAdvance() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("maximumObservationPollGapNanoseconds"))
        #expect(source.contains("observation_poll_gap_exceeded"))
        guard let watchdog = source.range(of: "private func startWatchdog(token:"),
              let gapFailure = source.range(of: "observation_poll_gap_exceeded", range: watchdog.upperBound..<source.endIndex),
              let observationAdvance = source.range(of: "sessionLedger.observeCurrentConnection(for: token)", range: gapFailure.upperBound..<source.endIndex) else {
            Issue.record("Field source must reject a long monotonic observation gap before advancing ledger liveness.")
            return
        }
        #expect(gapFailure.lowerBound < observationAdvance.lowerBound)
    }

    @Test("verification login callback does not outrank current SDK login authority")
    func loginCallbackRechecksSDKStateAndRedactsIdentity() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let success = source.range(of: "private func finishLoginSuccess()"),
              let reread = source.range(of: "OfficialTuyaFactory.accountLoggedIn", range: success.upperBound..<source.endIndex) else {
            Issue.record("Login success must re-read the official SDK account state.")
            return
        }
        #expect(success.lowerBound < reread.lowerBound)
        #expect(source.contains("<redacted-account>"))
        #expect(source.contains("redactedError("))
        #expect(source.contains("submittedIdentity:"))
    }

    @Test("field artifact and scan gate require exact stamped build provenance")
    func exactBuildIdentityIsMechanicallyWired() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(source.contains("CaptureFieldBuildIdentity.from(infoDictionary: Bundle.main.infoDictionary ?? [:])"))
        #expect(source.contains("guard fieldBuildStamped else"))
        #expect(source.contains("buildIdentifier: fieldBuildIdentity?.buildIdentifier"))
        #expect(source.contains("buildCommitSHA: fieldBuildIdentity?.commitSHA"))
        #expect(source.contains("buildIdentityValid: fieldBuildStamped"))
        #expect(source.contains("schemaVersion: 6"))

        #expect(project.contains("INFOPLIST_KEY_NembraCaptureBuildIdentifier = \"$(NEMBRA_CAPTURE_BUILD_IDENTIFIER)\";"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureBuildCommitSHA = \"$(NEMBRA_CAPTURE_BUILD_COMMIT_SHA)\";"))

        #expect(installer.contains("SOURCE_SHA=\"$(git rev-parse HEAD)\""))
        #expect(installer.contains("NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL"))
        #expect(installer.contains("NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
