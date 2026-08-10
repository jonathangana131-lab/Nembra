#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess

BRANCH = "integration/v14-capture-p0-hotpath-convergence-sol2"
PARENT = "8e4d28c9bd1c3ba6dd3a9c9292bd9f1ff27a40ac"
ENTRY = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
WORKFLOW = Path(".github/workflows/materialize-v14-capture-p0-hotpath-convergence-sol2.yml")
SELF = Path("scripts/ci/materialize_v14_capture_p0_hotpath_convergence_sol2.py")
EXPECTED_ENTRY_BLOB = "49527449240a20aef3de76276085371fbbccae10"
TEST_ROOT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests")

DONORS = {
    "TuyaSecureLinkViewMembershipAdmissionSourceTests.swift": (
        "sol/v14-capture-view-membership-admission-8e4",
        "fad2d84671326b5b925c7feecde5c4181e8efcd9",
    ),
    "TuyaApplicationUpdateSecretRedactionSourceTests.swift": (
        "red/v14-capture-application-secret-redaction-current-sol",
        "a7ae9bf21c2cbfb4602556c678dc52cce6cd9aea",
    ),
    "TuyaStationaryFailureCopySourceTests.swift": (
        "fix/v14-capture-stationary-failure-copy-sol",
        "478522e148faa83961742d84dd5ed0e4c5f628b2",
    ),
    "TuyaCaptureForegroundIntegritySourceTests.swift": (
        "fix/v14-capture-foreground-integrity-r2-sol",
        "9888832c0e9a6989114f1b5e2156119c0b65d38d",
    ),
}


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


def fetch_donor(branch: str, sha: str) -> None:
    remote_ref = f"refs/remotes/origin/{branch}"
    run("git", "fetch", "origin", f"refs/heads/{branch}:{remote_ref}")
    actual = run("git", "rev-parse", remote_ref, capture=True)
    require(actual == sha, f"donor {branch} moved: expected {sha}, got {actual}")


def recover_tests() -> None:
    TEST_ROOT.mkdir(parents=True, exist_ok=True)
    for name, (branch, sha) in DONORS.items():
        fetch_donor(branch, sha)
        repo_path = f"Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/{name}"
        content = run("git", "show", f"{sha}:{repo_path}", capture=True)
        (TEST_ROOT / name).write_text(content + "\n", encoding="utf-8")


def compose_entrypoint() -> None:
    source = ENTRY.read_text(encoding="utf-8")

    # #2377 — view-lifetime admission: callbacks cannot mint membership authority off-screen.
    source = replace_once(
        source,
        "    private var membershipRequestID = UUID()\n    private var officialConnectionRequestID = UUID()\n",
        "    private var membershipRequestID = UUID()\n    private var acceptsViewScopedMembershipRequests = false\n    private var officialConnectionRequestID = UUID()\n",
        "membership admission storage",
    )
    source = replace_once(
        source,
        "    deinit { watchdog?.cancel() }\n\n    func abandonCorrelationForViewExit() {\n",
        "    deinit { watchdog?.cancel() }\n\n"
        "    func activateMembershipRequestsForView() {\n"
        "        acceptsViewScopedMembershipRequests = true\n"
        "    }\n\n"
        "    func restoreMembershipRequestsAfterForegroundReturn() {\n"
        "        // System authorization UI can transiently inactivate the scene while preflight is still idle.\n"
        "        // Reopen only that non-radio preflight state; never reopen an authenticated/correlation generation.\n"
        "        guard phase == .idle, currentConnectionToken == nil, localBLESettlementToken == nil,\n"
        "              driver == nil, processCorrelationLease == nil, correlationSession == nil else { return }\n"
        "        acceptsViewScopedMembershipRequests = true\n"
        "    }\n\n"
        "    func abandonCorrelationForViewExit() {\n",
        "membership activation methods",
    )
    source = replace_once(
        source,
        "    func abandonCorrelationForViewExit() {\n"
        "        // Revoke every pre-radio asynchronous grant before inspecting current transport state.\n"
        "        // Late membership or ledger-generation work must not start OFF1/authentication off-screen.\n"
        "        membershipRequestID = UUID()\n",
        "    func abandonCorrelationForViewExit() {\n"
        "        // Close screen-lifetime admission before revoking every already-issued grant.\n"
        "        // Later SwiftUI/account callbacks cannot mint replacement membership authority off-screen.\n"
        "        acceptsViewScopedMembershipRequests = false\n"
        "        membershipRequestID = UUID()\n",
        "view-exit admission closure",
    )
    source = replace_once(
        source,
        "    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {\n        membershipAccountUID = nil\n",
        "    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {\n"
        "        guard acceptsViewScopedMembershipRequests else {\n"
        "            completion?(false)\n"
        "            return\n"
        "        }\n"
        "        membershipAccountUID = nil\n",
        "membership verification admission guard",
    )
    source = replace_once(
        source,
        "        .task {\n            sdkAccount.bootstrap()\n",
        "        .task {\n            test.activateMembershipRequestsForView()\n            sdkAccount.bootstrap()\n",
        "view appearance admission open",
    )

    # #2375 — explicit foreground-integrity authority fence.
    marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
    require(source.count(marker) == 1, "foreground insertion marker mismatch")
    foreground_method = '''    func appDidLoseForeground() {
        // Capture evidence is foreground-only. Close admission and revoke pending async grants first.
        acceptsViewScopedMembershipRequests = false
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

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
            ? "Capture left the foreground during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        Task { @MainActor [weak self] in
            guard let self, self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

'''
    source = source.replace(marker, foreground_method + marker, 1)
    source = replace_once(
        source,
        "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n",
        "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n"
        "    @Environment(\\.scenePhase) private var scenePhase\n",
        "scene phase environment",
    )
    source = replace_once(
        source,
        "        .onDisappear {\n            test.abandonCorrelationForViewExit()\n        }\n\n",
        "        .onDisappear {\n"
        "            test.abandonCorrelationForViewExit()\n"
        "        }\n"
        "        .onChange(of: scenePhase) { _, newPhase in\n"
        "            if newPhase == .active {\n"
        "                test.restoreMembershipRequestsAfterForegroundReturn()\n"
        "            } else {\n"
        "                test.appDidLoseForeground()\n"
        "            }\n"
        "        }\n\n",
        "scene phase lifecycle observer",
    )

    # #2376 — recursive secret custody before event/export admission.
    old_dps = '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            sanitized[String(describing: key)] = String(describing: value)
        }
        onApplicationUpdate?(sanitized)
    }
'''
    new_dps = '''    private static let secretKeyFragments = [
        "localkey", "accesstoken", "refreshtoken", "authkey", "seckey"
    ]

    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var redacted: [AnyHashable: Any] = [:]
            for (key, value) in dictionary {
                let normalized = String(describing: key).lowercased().filter { $0.isLetter || $0.isNumber }
                if secretKeyFragments.contains(where: normalized.contains) {
                    redacted[key] = "<redacted>"
                } else {
                    redacted[key] = redactApplicationSecrets(value)
                }
            }
            return redacted
        }
        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        return object
    }

    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalized = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: normalized.contains) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }
        onApplicationUpdate?(sanitized)
    }
'''
    source = replace_once(source, old_dps, new_dps, "application update redaction")

    # #2378 — stationary-only recovery after Tuya handoff.
    source = replace_once(
        source,
        "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture.",
        "Authenticated session produced no application update before the observation deadline. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
        "application timeout recovery copy",
    )
    source = replace_once(
        source,
        "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture.",
        "Tuya's current local-BLE session ended before acceptance. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
        "local BLE loss recovery copy",
    )

    ENTRY.write_text(source, encoding="utf-8")


def strengthen_foreground_regression() -> None:
    path = TEST_ROOT / "TuyaCaptureForegroundIntegritySourceTests.swift"
    source = path.read_text(encoding="utf-8")
    needle = '        #expect(view.contains("test.appDidLoseForeground()"))\n'
    require(source.count(needle) == 1, "foreground regression anchor missing")
    extra = needle + '''        #expect(view.contains("test.restoreMembershipRequestsAfterForegroundReturn()"))
        #expect(controller.contains("func restoreMembershipRequestsAfterForegroundReturn()"))
        let restore = String(try section(
            in: controller,
            from: "func restoreMembershipRequestsAfterForegroundReturn()",
            to: "func abandonCorrelationForViewExit()"
        ))
        #expect(restore.contains("guard phase == .idle"))
        #expect(restore.contains("currentConnectionToken == nil"))
        #expect(restore.contains("localBLESettlementToken == nil"))
        #expect(restore.contains("driver == nil"))
        #expect(restore.contains("processCorrelationLease == nil"))
        #expect(restore.contains("correlationSession == nil"))
        for forbidden in ["connectBLE", "disconnectBLE", "publishDps", "queryDps", "writeValue"] {
            #expect(!restore.contains(forbidden))
        }
'''
    path.write_text(source.replace(needle, extra, 1), encoding="utf-8")


def validate() -> None:
    source = ENTRY.read_text(encoding="utf-8")
    controller = source[source.index("private final class SecureLinkController"):source.index("@MainActor\nprivate protocol OfficialTuyaDriver")]
    driver = source[source.index("@MainActor\nprivate final class SmartLifeDriver"):source.index("#endif\n\nprivate enum AppleAccountAuthorizationError")]

    require("guard acceptsViewScopedMembershipRequests else" in controller, "membership admission guard absent")
    require("func restoreMembershipRequestsAfterForegroundReturn()" in controller, "safe foreground return absent")
    restore = controller[controller.index("func restoreMembershipRequestsAfterForegroundReturn()"):controller.index("func abandonCorrelationForViewExit()")]
    for required in ("guard phase == .idle", "currentConnectionToken == nil", "localBLESettlementToken == nil", "driver == nil", "processCorrelationLease == nil", "correlationSession == nil"):
        require(required in restore, f"restore fence missing {required}")

    foreground = controller[controller.index("func appDidLoseForeground()"):controller.index("var privateConfig: Bool")]
    require(foreground.index("acceptsViewScopedMembershipRequests = false") < foreground.index("membershipRequestID = UUID()"), "foreground admission ordering")
    require(foreground.index("officialConnectionRequestID = UUID()") < foreground.index("if processCorrelationLease"), "foreground grant ordering")
    for required in ("abandonPackageCorrelation()", "invalidateObservationContinuity(", "invalidateInternalLifecycle("):
        require(required in foreground, f"foreground lifecycle missing {required}")
    for forbidden in ("releasePackageCorrelationLease()", "recordObservedTransportLoss", "endConnection", "disconnectBLE", "publishDps", "queryDps", "writeValue"):
        require(forbidden not in foreground, f"foreground invented authority: {forbidden}")

    require("@Environment(\\.scenePhase) private var scenePhase" in source, "scenePhase missing")
    require("test.restoreMembershipRequestsAfterForegroundReturn()" in source, "active return missing")
    require("test.appDidLoseForeground()" in source, "foreground loss missing")

    for fragment in ("localkey", "accesstoken", "refreshtoken", "authkey", "seckey"):
        require(fragment in driver, f"secret fragment missing: {fragment}")
    for required in (
        "private static func redactApplicationSecrets(_ object: Any) -> Any",
        "array.map(redactApplicationSecrets)",
        "String(describing: Self.redactApplicationSecrets(value))",
        'sanitized[keyString] = "<redacted>"',
        "onApplicationUpdate?(sanitized)",
    ):
        require(required in driver, f"redaction contract missing: {required}")
    for forbidden in ("publishDps", "queryDps", "writeValue"):
        require(forbidden not in driver, f"driver command authority appeared: {forbidden}")

    recovery = "Export diagnostics; relaunch Capture before any new stationary read-only attempt."
    require(controller.count(recovery) == 2, "stationary recovery copy count mismatch")
    require("ride capture" not in controller and "outdoor ride" not in controller, "stale ride copy remains")

    run("git", "diff", "--check")
    if shutil.which("swiftc"):
        run("swiftc", "-parse", str(ENTRY))
        for name in DONORS:
            run("swiftc", "-parse", str(TEST_ROOT / name))


def main() -> None:
    require(run("git", "rev-parse", f"{PARENT}:{ENTRY}", capture=True) == EXPECTED_ENTRY_BLOB, "exact product entry blob moved")
    changed = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    require(sorted(changed) == sorted([str(WORKFLOW), str(SELF)]), f"unexpected helper pre-scope: {changed}")
    run("git", "diff", "--quiet", PARENT, "HEAD", "--", str(ENTRY))

    recover_tests()
    compose_entrypoint()
    strengthen_foreground_regression()
    validate()

    run("git", "config", "user.name", "nembra-sol-integration-closer")
    run("git", "config", "user.email", "actions@users.noreply.github.com")
    run("git", "rm", str(WORKFLOW), str(SELF))
    run("git", "add", str(ENTRY), *(str(TEST_ROOT / name) for name in DONORS))
    run("git", "diff", "--cached", "--check")
    run("git", "commit", "-m", "fix(capture): converge final secure-link hot-path truth")

    effective = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    expected = sorted([str(ENTRY), *(str(TEST_ROOT / name) for name in DONORS)])
    require(sorted(effective) == expected, f"unexpected effective product scope: {effective}")
    run("git", "diff", "--check", PARENT, "HEAD")
    run("git", "push", "origin", f"HEAD:{BRANCH}")


if __name__ == "__main__":
    main()
