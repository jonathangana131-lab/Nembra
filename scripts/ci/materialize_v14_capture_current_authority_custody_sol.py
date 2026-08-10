#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess

BRANCH = "integration/v14-capture-current-authority-custody-sol"
PARENT = "782deb76ac501363aab972de9f1246cf2b28705b"
ENTRY = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
ENTRY_BLOB = "6ce67526093459b76cbe3fc917767258ab985ac3"
WORKFLOW = Path(".github/workflows/materialize-v14-capture-current-authority-custody-sol.yml")
SELF = Path("scripts/ci/materialize_v14_capture_current_authority_custody_sol.py")
TEST_ROOT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests")
APP_SECRET_TEST = TEST_ROOT / "TuyaApplicationUpdateSecretRedactionSourceTests.swift"
FOREGROUND_TEST = TEST_ROOT / "TuyaCaptureForegroundIntegritySourceTests.swift"
MEMBERSHIP_TEST = TEST_ROOT / "TuyaSecureLinkViewMembershipProofRevocationSourceTests.swift"
LOGIN_TEST = TEST_ROOT / "TuyaVerificationCodeRedactionSourceTests.swift"
STATIONARY_TEST = TEST_ROOT / "TuyaStationaryFailureCopySourceTests.swift"


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        args,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    require(count == 1, f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


def compose_entrypoint() -> None:
    source = ENTRY.read_text(encoding="utf-8")

    # The merged application-update sanitizer already closes #2376, but its recognized
    # credential family omitted the export promise's explicit session-key spelling.
    source = replace_once(
        source,
        '        "authkey",\n        "seckey",\n    ]\n',
        '        "authkey",\n        "seckey",\n        "sessionkey",\n    ]\n',
        "application session-key redaction fragment",
    )

    # Centralize the screen/foreground membership lease teardown. The earned proof is
    # view-lifetime authority and must disappear before any async grant or transport check.
    old_methods = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }

    func abandonCorrelationForViewExit() {
        // Close the screen-lifetime admission boundary before revoking every already-issued grant.
        // A later SwiftUI/account callback must not mint a replacement membership probe off-screen.
        acceptsViewScopedMembershipRequests = false
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil
'''
    new_methods = '''    private func revokeMembershipAuthorityForViewLifetime() {
        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
        membershipStatus = "Exact scooter membership must be verified again for this Secure Link foreground session."
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
    }

    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }

    func appDidBecomeActive() {
        let canResumePreflight = phase == .idle
            || phase == .correlated
            || phase == .selected
            || canRestartFromFreshOFF1
        guard canResumePreflight,
              currentConnectionToken == nil,
              localBLESettlementToken == nil,
              driver == nil,
              processCorrelationLease == nil,
              correlationSession == nil else { return }
        acceptsViewScopedMembershipRequests = true
        if sdkAccountLoggedIn {
            verifySDKMembership()
        }
    }

    func abandonCorrelationForViewExit() {
        // Revoke the earned screen-lifetime membership proof before every async grant or
        // transport/session inspection. Reappearance must earn membership again.
        revokeMembershipAuthorityForViewLifetime()
        watchdog?.cancel()
        watchdog = nil
'''
    source = replace_once(source, old_methods, new_methods, "view lifetime membership teardown")

    # Explicit foreground integrity. Sealed accepted evidence survives backgrounding; active
    # correlation/authentication/observation does not. Strong task capture preserves #2381.
    marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
    require(source.count(marker) == 1, "foreground insertion marker mismatch")
    foreground = '''    func appDidLoseForeground() {
        revokeMembershipAuthorityForViewLifetime()
        watchdog?.cancel()
        watchdog = nil

        // Once the immutable accepted artifact exists, losing foreground cannot rewrite history.
        if phase == .accepted { return }
        // A prior loss may already have started exact-generation retirement; do not double-terminal it.
        if phase == .failed { return }

        if processCorrelationLease != nil || correlationSession != nil {
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        Task { @MainActor [self] in
            guard currentConnectionToken == token else { return }
            if wasObserving {
                await invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

'''
    source = source.replace(marker, foreground + marker, 1)

    source = replace_once(
        source,
        "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n",
        "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n"
        "    @Environment(\\.scenePhase) private var scenePhase\n",
        "scene phase environment",
    )
    source = replace_once(
        source,
        '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
''',
        '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                test.appDidBecomeActive()
            } else {
                test.appDidLoseForeground()
            }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
''',
        "scene phase lifecycle observer",
    )

    # #2386: preserve the snapshotted verification code until vendor error text is scrubbed.
    old_login_failure = "failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity) } }"
    require(source.count(old_login_failure) == 2, "expected both email and phone login failure closures")
    source = source.replace(
        old_login_failure,
        "failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code) } }",
    )
    source = replace_once(
        source,
        '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \\(Self.redactedError(error, submittedIdentity: submittedIdentity))"
    }
''',
        '''    private func finishLoginFailure(
        _ error: Error?,
        submittedIdentity: String,
        submittedVerificationCode: String
    ) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \\(Self.redactedError(
            error,
            submittedIdentity: submittedIdentity,
            submittedVerificationCode: submittedVerificationCode
        ))"
    }
''',
        "verification-code failure custody",
    )
    source = replace_once(
        source,
        '''    private static func redactedError(_ error: Error?, submittedIdentity: String) -> String {
        let raw = error?.localizedDescription ?? "unknown error"
        let identity = submittedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { return raw }
        return raw.replacingOccurrences(
            of: identity,
            with: "<redacted-account>",
            options: [.caseInsensitive, .literal]
        )
    }
''',
        '''    private static func redactedError(_ error: Error?, submittedIdentity: String) -> String {
        redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: "")
    }

    private static func redactedError(
        _ error: Error?,
        submittedIdentity: String,
        submittedVerificationCode: String
    ) -> String {
        var redacted = error?.localizedDescription ?? "unknown error"
        let identity = submittedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: identity,
                with: "<redacted-account>",
                options: [.caseInsensitive, .literal]
            )
        }
        let code = submittedVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: code,
                with: "<redacted-verification-code>",
                options: [.literal]
            )
        }
        return redacted
    }
''',
        "verification-code centralized scrubber",
    )

    # #2378: after one-shot official Tuya handoff, recovery that requires a fresh package
    # correlation must say relaunch and must remain stationary-only.
    replacements = {
        "Source authority changed while canonical acceptance was sealing. Restart from OFF1; the sealed package chronology is diagnostic only.":
            "Source authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only.",
        "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred.":
            "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
        "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred.":
            "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
        "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture.":
            "Authenticated session produced no application update before the observation deadline. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
        "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture.":
            "Tuya's current local-BLE session ended before acceptance. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
        "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Restart from OFF1 rather than rebuilding accepted evidence from mutable post-seal state.":
            "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Relaunch Capture before a new stationary read-only attempt; do not rebuild accepted evidence from mutable post-seal state.",
    }
    for old, new in replacements.items():
        source = replace_once(source, old, new, f"stationary recovery: {old[:36]}")

    ENTRY.write_text(source, encoding="utf-8")


def write_tests() -> None:
    TEST_ROOT.mkdir(parents=True, exist_ok=True)

    existing = APP_SECRET_TEST.read_text(encoding="utf-8")
    existing = replace_once(
        existing,
        '        #expect(driver.contains("seckey"))\n',
        '        #expect(driver.contains("seckey"))\n        #expect(driver.contains("sessionkey"))\n',
        "session-key source regression",
    )
    APP_SECRET_TEST.write_text(existing, encoding="utf-8")

    FOREGROUND_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("scene lifetime fences active evidence while preserving sealed acceptance")
    func scenePhaseOwnsForegroundAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        let loss = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        let restore = String(try section(in: controller, from: "func appDidBecomeActive()", to: "func abandonCorrelationForViewExit()"))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("test.appDidBecomeActive()"))
        #expect(view.contains("test.appDidLoseForeground()"))

        let revoke = try requiredOffset(containing: "revokeMembershipAuthorityForViewLifetime()", in: loss)
        let watchdog = try requiredOffset(containing: "watchdog?.cancel()", in: loss)
        let transport = try requiredOffset(containing: "if processCorrelationLease != nil || correlationSession != nil", in: loss)
        #expect(revoke < watchdog)
        #expect(watchdog < transport)
        #expect(loss.contains("if phase == .accepted { return }"))
        #expect(loss.contains("if phase == .failed { return }"))
        #expect(loss.contains("abandonPackageCorrelation()"))
        #expect(loss.contains("invalidateObservationContinuity("))
        #expect(loss.contains("invalidateInternalLifecycle("))
        #expect(loss.contains("Task { @MainActor [self] in"))
        #expect(!loss.contains("[weak self]"))
        for forbidden in ["recordObservedTransportLoss", "endConnection", "disconnectBLE", "publishDps", "queryDps", "writeValue"] {
            #expect(!loss.contains(forbidden))
        }

        #expect(restore.contains("phase == .idle"))
        #expect(restore.contains("phase == .correlated"))
        #expect(restore.contains("phase == .selected"))
        #expect(restore.contains("canRestartFromFreshOFF1"))
        #expect(restore.contains("currentConnectionToken == nil"))
        #expect(restore.contains("driver == nil"))
        #expect(restore.contains("acceptsViewScopedMembershipRequests = true"))
        #expect(restore.contains("verifySDKMembership()"))
        for forbidden in ["connectBLE", "disconnectBLE", "publishDps", "queryDps", "writeValue"] {
            #expect(!restore.contains(forbidden))
        }
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { Issue.record("Expected token missing: \(token)"); throw SourceContractError.sectionMissing }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")

    MEMBERSHIP_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view-lifetime membership proof revocation")
struct TuyaSecureLinkViewMembershipProofRevocationSourceTests {
    @Test("view exit clears earned membership before async grants and transport inspection")
    func exitRevokesMembershipProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let revoke = String(try section(in: controller, from: "private func revokeMembershipAuthorityForViewLifetime()", to: "func activateMembershipRequestsForView()"))
        let cleanup = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))

        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: revoke)
        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: revoke)
        let clearAccount = try requiredOffset(containing: "membershipAccountUID = nil", in: revoke)
        let clearDevice = try requiredOffset(containing: "membershipDeviceID = nil", in: revoke)
        let revokeMembership = try requiredOffset(containing: "membershipRequestID = UUID()", in: revoke)
        let revokeOfficial = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: revoke)
        #expect(closeAdmission < clearVerified)
        #expect(clearVerified < revokeMembership)
        #expect(clearAccount < revokeMembership)
        #expect(clearDevice < revokeMembership)
        #expect(revokeMembership < revokeOfficial)

        let helperCall = try requiredOffset(containing: "revokeMembershipAuthorityForViewLifetime()", in: cleanup)
        let transportInspection = try requiredOffset(containing: "if let token = currentConnectionToken", in: cleanup)
        #expect(helperCall < transportInspection)
    }

    @Test("reappearance opens admission then freshly verifies membership")
    func reappearanceReearnsMembership() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        let open = try requiredOffset(containing: "test.activateMembershipRequestsForView()", in: task)
        let bootstrap = try requiredOffset(containing: "sdkAccount.bootstrap()", in: task)
        let verify = try requiredOffset(containing: "test.verifySDKMembership()", in: task)
        #expect(open < bootstrap)
        #expect(bootstrap < verify)
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { Issue.record("Expected token missing: \(token)"); throw SourceContractError.sectionMissing }
        return range.lowerBound
    }
    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)"); throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")

    LOGIN_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya verification-code credential redaction source contract")
struct TuyaVerificationCodeRedactionSourceTests {
    @Test("both email and phone failures scrub the snapshotted submitted code")
    func loginFailureCannotEchoVerificationCode() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = String(try section(in: source, from: "@MainActor\nprivate final class OfficialTuyaAccountAuthorizer", to: "@MainActor\nprivate struct SecureLinkView"))
        let call = "finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code)"
        #expect(authorizer.components(separatedBy: call).count - 1 == 2)
        #expect(authorizer.contains("let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)"))
        #expect(authorizer.contains("submittedVerificationCode: String"))
        #expect(authorizer.contains("let code = submittedVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)"))
        #expect(authorizer.contains("of: code"))
        #expect(authorizer.contains("with: \"<redacted-verification-code>\""))
    }

    @Test("UI clearing occurs only after the submitted code is passed into failure custody")
    func loginFailureScrubsBeforeForgettingCredential() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let failure = String(try section(in: source, from: "private func finishLoginFailure(", to: "private func finishAppleLoginFailure"))
        #expect(failure.contains("submittedVerificationCode"))
        #expect(failure.contains("verificationCode = \"\""))
        #expect(failure.contains("submittedVerificationCode: submittedVerificationCode"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)"); throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")

    STATIONARY_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture stationary-only failure recovery copy")
struct TuyaStationaryFailureCopySourceTests {
    @Test("post-handoff failures require relaunch and a new stationary read-only attempt")
    func postHandoffFailureCopyStaysStationaryOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "private protocol OfficialTuyaDriver"))
        #expect(!controller.contains("ride capture"))
        #expect(!controller.contains("outdoor ride"))
        let recovery = "Export diagnostics; relaunch Capture before any new stationary read-only attempt."
        #expect(controller.components(separatedBy: recovery).count - 1 == 2)
    }

    @Test("official Tuya handoff makes bare OFF1 restart copy invalid")
    func officialHandoffRecoveryRequiresRelaunch() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let postHandoff = String(try section(in: source, from: "private func beginOfficialConnection(candidate: Candidate)", to: "private protocol OfficialTuyaDriver"))
        #expect(!postHandoff.lowercased().contains("restart from off1"))
        let required = [
            "Source authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only.",
            "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
            "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
            "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Relaunch Capture before a new stationary read-only attempt; do not rebuild accepted evidence from mutable post-seal state."
        ]
        for message in required { #expect(postHandoff.contains(message)) }
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)"); throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")


def validate() -> None:
    source = ENTRY.read_text(encoding="utf-8")
    controller = source[source.index("private final class SecureLinkController"):source.index("@MainActor\nprivate protocol OfficialTuyaDriver")]
    driver = source[source.index("@MainActor\nprivate final class SmartLifeDriver"):source.index("#endif\n\nprivate enum AppleAccountAuthorizationError")]
    authorizer = source[source.index("@MainActor\nprivate final class OfficialTuyaAccountAuthorizer"):source.index("@MainActor\nprivate struct SecureLinkView")]

    require('"sessionkey"' in driver, "session-key secret fragment absent")
    require("private func revokeMembershipAuthorityForViewLifetime()" in controller, "membership revoker absent")
    revoke = controller[controller.index("private func revokeMembershipAuthorityForViewLifetime()"):controller.index("func activateMembershipRequestsForView()")]
    for token in (
        "acceptsViewScopedMembershipRequests = false",
        "sdkDeviceMembershipVerified = false",
        "membershipAccountUID = nil",
        "membershipDeviceID = nil",
        "membershipRequestID = UUID()",
        "officialConnectionRequestID = UUID()",
    ):
        require(token in revoke, f"membership revocation missing {token}")

    loss = controller[controller.index("func appDidLoseForeground()"):controller.index("var privateConfig: Bool")]
    require("if phase == .accepted { return }" in loss, "sealed acceptance foreground preservation absent")
    require("Task { @MainActor [self] in" in loss, "strong terminal lifetime absent")
    require("[weak self]" not in loss, "foreground terminal task weakened")
    for token in ("abandonPackageCorrelation()", "invalidateObservationContinuity(", "invalidateInternalLifecycle("):
        require(token in loss, f"foreground lifecycle missing {token}")
    for forbidden in ("recordObservedTransportLoss", "endConnection", "disconnectBLE", "publishDps", "queryDps", "writeValue"):
        require(forbidden not in loss, f"foreground invented authority: {forbidden}")

    require("@Environment(\\.scenePhase) private var scenePhase" in source, "scene phase environment absent")
    require("test.appDidBecomeActive()" in source and "test.appDidLoseForeground()" in source, "scene transition callbacks absent")

    login_call = "finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code)"
    require(authorizer.count(login_call) == 2, "both login methods must carry verification-code snapshot")
    require('with: "<redacted-verification-code>"' in authorizer, "verification-code redaction marker absent")
    require("of: code" in authorizer, "submitted verification code is not scrub operand")

    recovery = "Export diagnostics; relaunch Capture before any new stationary read-only attempt."
    require(controller.count(recovery) == 2, "stationary export recovery count mismatch")
    require("ride capture" not in controller and "outdoor ride" not in controller, "obsolete ride wording remains")
    post_handoff = controller[controller.index("private func beginOfficialConnection(candidate: Candidate)"):]
    require("restart from off1" not in post_handoff.lower(), "post-handoff bare OFF1 recovery remains")

    run("git", "diff", "--check")
    if shutil.which("swiftc"):
        run("swiftc", "-parse", str(ENTRY))
        for path in (APP_SECRET_TEST, FOREGROUND_TEST, MEMBERSHIP_TEST, LOGIN_TEST, STATIONARY_TEST):
            run("swiftc", "-parse", str(path))


def main() -> None:
    require(run("git", "rev-parse", f"{PARENT}:{ENTRY}", capture=True) == ENTRY_BLOB, "exact product entry blob moved")
    pre = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    require(sorted(pre) == sorted([str(WORKFLOW), str(SELF)]), f"unexpected helper pre-scope: {pre}")
    run("git", "diff", "--quiet", PARENT, "HEAD", "--", str(ENTRY), str(APP_SECRET_TEST))

    compose_entrypoint()
    write_tests()
    validate()

    run("git", "config", "user.name", "nembra-sol-integration-closer")
    run("git", "config", "user.email", "actions@users.noreply.github.com")
    run("git", "rm", str(WORKFLOW), str(SELF))
    final_paths = [ENTRY, APP_SECRET_TEST, FOREGROUND_TEST, MEMBERSHIP_TEST, LOGIN_TEST, STATIONARY_TEST]
    run("git", "add", *(str(path) for path in final_paths))
    run("git", "diff", "--cached", "--check")
    run("git", "commit", "-m", "fix(capture): close current authority and credential custody gaps")

    effective = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    expected = sorted(str(path) for path in final_paths)
    require(sorted(effective) == expected, f"unexpected effective product scope: {effective}")
    run("git", "diff", "--check", PARENT, "HEAD")
    run("git", "push", "origin", f"HEAD:{BRANCH}")


if __name__ == "__main__":
    main()
