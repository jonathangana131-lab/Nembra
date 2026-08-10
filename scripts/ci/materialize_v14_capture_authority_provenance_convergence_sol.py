#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess

BRANCH = "integration/v14-capture-authority-provenance-convergence-sol"
PARENT = "6b778f2104af34dbe5b80da31ddb3ca422f9667c"
ENTRY = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
ENTRY_BLOB = "cd91a0777b8370e64312a30117acdaf50c9dd68a"
WORKFLOW = Path(".github/workflows/materialize-v14-capture-authority-provenance-convergence-sol.yml")
SELF = Path("scripts/ci/materialize_v14_capture_authority_provenance_convergence_sol.py")
TEST_ROOT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests")

DONORS = {
    "TuyaCaptureForegroundIntegrityCurrentSourceTests.swift": (
        "agent/v14-capture-foreground-integrity-870f-red-sol",
        "ec55d27270d80bdfa556eff3b598880dd8f5c231",
    ),
    "TuyaSecureLinkViewMembershipStatusRevocationSourceTests.swift": (
        "agent/v14-capture-membership-status-revocation-red-4b41",
        "8e004bdc39357c832c11d98d5013d2097937967f",
    ),
    "TuyaApplicationEventMetadataPrecedenceSourceTests.swift": (
        "agent/v14-capture-application-event-metadata-precedence-red",
        "a8eb9b93eea7e5de1a9c80468cadf378989b5edd",
    ),
    "TuyaApplicationAccountUIDExportCustodySourceTests.swift": (
        "agent/v14-capture-account-uid-export-red-870f-sol",
        "8010d108a043fbe2ff03fa3bb0d1518aa7047c08",
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
    require(count == 1, f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def recover_red_contracts() -> None:
    TEST_ROOT.mkdir(parents=True, exist_ok=True)
    for name, (branch, sha) in DONORS.items():
        remote_ref = f"refs/remotes/origin/{branch}"
        run("git", "fetch", "origin", f"refs/heads/{branch}:{remote_ref}")
        actual = run("git", "rev-parse", remote_ref, capture=True)
        require(actual == sha, f"red donor moved for {name}: expected {sha}, got {actual}")
        repo_path = f"Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/{name}"
        content = run("git", "show", f"{sha}:{repo_path}", capture=True)
        (TEST_ROOT / name).write_text(content + "\n", encoding="utf-8")


def compose_product() -> None:
    source = ENTRY.read_text(encoding="utf-8")

    # View/foreground lifetime authority bookkeeping.
    source = replace_once(
        source,
        "    private var membershipRequestID = UUID()\n    private var acceptsViewScopedMembershipRequests = false\n    private var officialConnectionRequestID = UUID()\n",
        "    private var membershipRequestID = UUID()\n"
        "    private var acceptsViewScopedMembershipRequests = false\n"
        "    private var foregroundIntegrityLossHandled = false\n"
        "    private var officialConnectionRequestID = UUID()\n",
        "foreground episode storage",
    )
    source = replace_once(
        source,
        "    func activateMembershipRequestsForView() {\n        acceptsViewScopedMembershipRequests = true\n    }\n",
        "    func activateMembershipRequestsForView() {\n"
        "        foregroundIntegrityLossHandled = false\n"
        "        acceptsViewScopedMembershipRequests = true\n"
        "    }\n",
        "foreground activation",
    )

    # Revoking the proof must also revoke its positive operator-facing copy before request rotation.
    view_exit_lease = (
        "        sdkDeviceMembershipVerified = false\n"
        "        membershipAccountUID = nil\n"
        "        membershipDeviceID = nil\n"
        "        membershipRequestID = UUID()\n"
    )
    source = replace_once(
        source,
        view_exit_lease,
        "        sdkDeviceMembershipVerified = false\n"
        "        membershipAccountUID = nil\n"
        "        membershipDeviceID = nil\n"
        "        membershipStatus = \"Exact scooter membership must be verified again for the current Secure Link view lifetime.\"\n"
        "        membershipRequestID = UUID()\n",
        "view-exit membership status revocation",
    )
    source = replace_once(
        source,
        "        watchdog?.cancel()\n        watchdog = nil\n\n        if let token = currentConnectionToken {\n",
        "        watchdog?.cancel()\n"
        "        watchdog = nil\n\n"
        "        // Foreground loss already owns terminal retirement for this view lifetime.\n"
        "        // Do not race a second exact-generation terminal when onDisappear follows it.\n"
        "        if foregroundIntegrityLossHandled { return }\n\n"
        "        if let token = currentConnectionToken {\n",
        "view-exit foreground idempotence",
    )

    marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
    require(source.count(marker) == 1, "foreground insertion marker moved")
    foreground = '''    func appDidLoseForeground() {
        // Immutable accepted evidence is already sealed. Backgrounding must not mutate it.
        guard phase != .accepted else { return }
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true

        // Foreground-only Capture authority closes synchronously before any radio/session inspection.
        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again for the current Secure Link view lifetime."
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        if processCorrelationLease != nil || correlationSession != nil {
            // Scanner transport retires before the process lease. The generic discovery reset then
            // clears all target/correlation presentation authority from the interrupted attempt.
            abandonPackageCorrelation()
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        if phase == .correlated || phase == .selected {
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground after target correlation. Restart from OFF1; correlated or selected target authority cannot cross a foreground interruption."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                // OfficialTuyaFactory.make() permanently retires package correlation for this process.
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch Capture before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // Finite terminal work must outlive SwiftUI StateObject teardown. Exact-token fencing
        // prevents this foreground episode from touching any later authenticated generation.
        Task { @MainActor [self] in
            guard self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch Capture before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

'''
    source = source.replace(marker, foreground + marker, 1)

    # Scene lifetime is a first-class authority boundary. System auth sheets can temporarily make
    # the scene inactive while preflight is idle, so a later active transition reopens admission
    # and freshly re-earns membership; no target/session authority is restored by that transition.
    source = replace_once(
        source,
        "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n",
        "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n"
        "    @Environment(\\.scenePhase) private var scenePhase\n",
        "scene phase environment",
    )
    source = replace_once(
        source,
        "        .task {\n"
        "            test.activateMembershipRequestsForView()\n"
        "            sdkAccount.bootstrap()\n"
        "            if sdkAccount.loggedIn { test.verifySDKMembership() }\n",
        "        .task {\n"
        "            if scenePhase == .active {\n"
        "                test.activateMembershipRequestsForView()\n"
        "            } else {\n"
        "                test.appDidLoseForeground()\n"
        "            }\n"
        "            sdkAccount.bootstrap()\n"
        "            if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }\n",
        "scene-aware initial membership",
    )
    source = replace_once(
        source,
        "        .onDisappear {\n"
        "            test.abandonCorrelationForViewExit()\n"
        "        }\n"
        "        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n",
        "        .onDisappear {\n"
        "            test.abandonCorrelationForViewExit()\n"
        "        }\n"
        "        .onChange(of: scenePhase) { _, newPhase in\n"
        "            if newPhase == .active {\n"
        "                test.activateMembershipRequestsForView()\n"
        "                if sdkAccount.loggedIn { test.verifySDKMembership() }\n"
        "            } else {\n"
        "                test.appDidLoseForeground()\n"
        "            }\n"
        "        }\n"
        "        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n",
        "scene transition observer",
    )

    # Accepted application events must not export the exact verified account UID, and untrusted
    # SDK keys must not overwrite Nembra-owned event provenance.
    old_log = '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
'''
    new_log = '''            guard let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !verifiedAccountUID.isEmpty else {
                await invalidateSourceAuthority(
                    token: token,
                    message: "Verified account-UID custody became unavailable before application evidence could be sealed.",
                    kind: "sdk_account_uid_custody_unavailable"
                )
                return
            }
            let exportSafeUpdate = update.mapValues { value in
                value.replacingOccurrences(
                    of: verifiedAccountUID,
                    with: "<redacted-account-uid>",
                    options: [.caseInsensitive, .literal]
                )
            }
            log("tuya_application_update", exportSafeUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
'''
    source = replace_once(source, old_log, new_log, "application event custody")

    # Secret-promise convergence briefly introduced a duplicate classifier entry. Keep one.
    source = replace_once(
        source,
        '        "accesstoken",\n        "refreshtoken",\n        "sessionkey",\n        "authkey",\n',
        '        "accesstoken",\n        "refreshtoken",\n        "authkey",\n',
        "duplicate sessionkey simplification",
    )

    ENTRY.write_text(source, encoding="utf-8")


def validate_source_contracts() -> None:
    source = ENTRY.read_text(encoding="utf-8")
    controller = source[source.index("private final class SecureLinkController"):source.index("@MainActor\nprivate protocol OfficialTuyaDriver")]
    view = source[source.index("private struct SecureLinkView: View"):source.index("private var hero: some View")]
    cleanup = controller[controller.index("func appDidLoseForeground()"):controller.index("var privateConfig: Bool")]
    receiver = controller[controller.index("private func receivedApplicationUpdate("):controller.index("private func startWatchdog")]
    driver = source[source.index("@MainActor\nprivate final class SmartLifeDriver"):source.index("#endif\n\nprivate enum AppleAccountAuthorizationError")]

    require("@Environment(\\.scenePhase) private var scenePhase" in view, "scenePhase missing")
    require(".onChange(of: scenePhase)" in view, "scene observer missing")
    require("guard phase != .accepted else { return }" in cleanup, "sealed acceptance foreground guard missing")
    for token in (
        "sdkDeviceMembershipVerified = false",
        "membershipAccountUID = nil",
        "membershipDeviceID = nil",
        "membershipRequestID = UUID()",
        "officialConnectionRequestID = UUID()",
        "abandonPackageCorrelation()",
        "resetDiscoverySessionOnly()",
        "phase == .correlated || phase == .selected",
        "invalidateObservationContinuity(",
        "invalidateInternalLifecycle(",
        "Task { @MainActor [self] in",
    ):
        require(token in cleanup, f"foreground contract missing: {token}")
    for forbidden in ("recordObservedTransportLoss", "endConnection", "disconnectBLE", "releasePackageCorrelationLease()"):
        require(forbidden not in cleanup, f"foreground path invents authority: {forbidden}")

    view_exit = controller[controller.index("func abandonCorrelationForViewExit()"):controller.index("func appDidLoseForeground()")]
    clear_verified = view_exit.index("sdkDeviceMembershipVerified = false")
    reset_status = view_exit.index("membershipStatus =")
    revoke_request = view_exit.index("membershipRequestID = UUID()")
    require(clear_verified < reset_status < revoke_request, "membership status revocation ordering wrong")
    require("membership verified and leased" not in view_exit.lower(), "stale positive membership copy remains")

    require("<redacted-account-uid>" in receiver, "account UID value redaction missing")
    require('log("tuya_application_update", update.merging([' not in receiver, "raw update still enters event custody")
    require(']) { _, trusted in trusted })' in receiver, "trusted generation precedence missing")
    require('"generation": String(token.diagnosticGeneration)' in receiver, "trusted generation metadata missing")
    require('"uid",' not in driver and '"uid"\n' not in driver, "blanket UID key suppression is forbidden")
    require(driver.count('"sessionkey"') == 1, "sessionkey classifier should appear exactly once")

    run("git", "diff", "--check")
    if shutil.which("swiftc"):
        run("swiftc", "-parse", str(ENTRY))
        for name in DONORS:
            run("swiftc", "-parse", str(TEST_ROOT / name))


def main() -> None:
    require(run("git", "rev-parse", f"{PARENT}:{ENTRY}", capture=True) == ENTRY_BLOB, "exact parent entrypoint blob moved")
    pre = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    require(sorted(pre) == sorted([str(WORKFLOW), str(SELF)]), f"unexpected helper pre-scope: {pre}")

    recover_red_contracts()
    compose_product()
    validate_source_contracts()

    run("git", "config", "user.name", "nembra-sol-integration-closer")
    run("git", "config", "user.email", "actions@users.noreply.github.com")
    run("git", "rm", str(WORKFLOW), str(SELF))
    final_paths = [ENTRY, *(TEST_ROOT / name for name in DONORS)]
    run("git", "add", *(str(path) for path in final_paths))
    run("git", "diff", "--cached", "--check")
    run("git", "commit", "-m", "fix(capture): converge foreground and event authority custody")

    effective = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    expected = sorted(str(path) for path in final_paths)
    require(sorted(effective) == expected, f"unexpected effective product scope: {effective}")
    run("git", "diff", "--check", PARENT, "HEAD")
    run("git", "push", "origin", f"HEAD:{BRANCH}")


if __name__ == "__main__":
    main()
