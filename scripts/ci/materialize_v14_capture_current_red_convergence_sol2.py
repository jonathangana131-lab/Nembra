#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess

BRANCH = "integration/v14-capture-current-red-convergence-sol2"
PARENT = "1c40853f6991b4d09206df1d25ecff021458b7eb"
ENTRY = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
ENTRY_BLOB = "c58be3f6bc0cf33a9f6d0d950b7d011ff8aa1d25"
WORKFLOW = Path(".github/workflows/materialize-v14-capture-current-red-convergence-sol2.yml")
SELF = Path("scripts/ci/materialize_v14_capture_current_red_convergence_sol2.py")
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
    r = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None)
    return r.stdout.strip() if capture else ""


def require(value: bool, message: str) -> None:
    if not value:
        raise SystemExit(message)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    require(count == 1, f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


def recover_tests() -> None:
    TEST_ROOT.mkdir(parents=True, exist_ok=True)
    for filename, (branch, sha) in DONORS.items():
        ref = f"refs/remotes/origin/{branch}"
        run("git", "fetch", "origin", f"refs/heads/{branch}:{ref}")
        require(run("git", "rev-parse", ref, capture=True) == sha, f"donor moved: {branch}")
        repo_path = f"Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/{filename}"
        (TEST_ROOT / filename).write_text(run("git", "show", f"{sha}:{repo_path}", capture=True) + "\n", encoding="utf-8")


def patch_product() -> None:
    s = ENTRY.read_text(encoding="utf-8")

    # Foreground return may reopen pre-handoff membership only after every mutable radio/session
    # authority is gone. Official Tuya handoff permanently blocks in-process OFF1 recovery.
    s = replace_once(
        s,
        '''    func activateMembershipRequestsForView() {
        // A fast inactive -> active transition must not reset the duplicate-retirement fence
        // while the exact authenticated generation from foreground loss is still terminalizing.
        guard currentConnectionToken == nil else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
''',
        '''    func activateMembershipRequestsForView() {
        // A fast inactive -> active transition must not reset the duplicate-retirement fence
        // while mutable correlation/authentication authority is still retiring. Once official
        // Tuya BLE ownership has been attempted, recovery remains relaunch-only for this process.
        guard currentConnectionToken == nil,
              localBLESettlementToken == nil,
              driver == nil,
              processCorrelationLease == nil,
              correlationSession == nil,
              OfficialTuyaFactory.packageCorrelationMayStart else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
''',
        "foreground reactivation fence",
    )

    # Revoke positive copy with the view-lifetime proof before rotating the membership generation.
    s = replace_once(
        s,
        '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
''',
        '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again for the current Secure Link view lifetime."
        membershipRequestID = UUID()
''',
        "view-exit membership status",
    )

    # #2417 is stronger than the just-merged #2418: sealed acceptance is immutable, package
    # correlation/confirmed-target authority cannot cross inactive, and all proof/status authority
    # closes synchronously before transport inspection.
    s = replace_once(
        s,
        '''    func appDidLoseForeground() {
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
''',
        '''    func appDidLoseForeground() {
        // A sealed accepted artifact is immutable/shareable history; foreground loss cannot rewrite it.
        guard phase != .accepted else { return }
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
''',
        "accepted foreground guard",
    )
    s = replace_once(
        s,
        '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
''',
        '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again for the current Secure Link view lifetime."
        membershipRequestID = UUID()
        membershipBusy = false
''',
        "foreground membership status",
    )
    s = replace_once(
        s,
        '''        if processCorrelationLease != nil || correlationSession != nil {
            // Existing helper stops package transport before releasing this controller's lease.
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
''',
        '''        if processCorrelationLease != nil || correlationSession != nil {
            // Existing helper stops package transport before releasing this controller's lease.
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
''',
        "foreground target-authority reset",
    )

    # Application evidence is untrusted content. Exact verified account UID is never exported,
    # and Nembra-owned generation provenance wins a reserved-key collision.
    s = replace_once(
        s,
        '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
''',
        '''            guard let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
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
''',
        "accepted application event custody",
    )

    # Keep exactly one session-key classifier entry after the previous secret-promise convergence.
    s = replace_once(
        s,
        '        "accesstoken",\n        "refreshtoken",\n        "sessionkey",\n        "authkey",\n',
        '        "accesstoken",\n        "refreshtoken",\n        "authkey",\n',
        "duplicate session-key classifier",
    )
    ENTRY.write_text(s, encoding="utf-8")


def validate() -> None:
    s = ENTRY.read_text(encoding="utf-8")
    controller = s[s.index("private final class SecureLinkController"):s.index("@MainActor\nprivate protocol OfficialTuyaDriver")]
    activate = controller[controller.index("func activateMembershipRequestsForView()"):controller.index("func abandonCorrelationForViewExit()")]
    view_exit = controller[controller.index("func abandonCorrelationForViewExit()"):controller.index("func appDidLoseForeground()")]
    foreground = controller[controller.index("func appDidLoseForeground()"):controller.index("var privateConfig: Bool")]
    receiver = controller[controller.index("private func receivedApplicationUpdate("):controller.index("private func startWatchdog")]
    driver = s[s.index("@MainActor\nprivate final class SmartLifeDriver"):s.index("#endif\n\nprivate enum AppleAccountAuthorizationError")]

    for fence in (
        "currentConnectionToken == nil", "localBLESettlementToken == nil", "driver == nil",
        "processCorrelationLease == nil", "correlationSession == nil", "OfficialTuyaFactory.packageCorrelationMayStart",
    ):
        require(fence in activate, f"reactivation fence missing {fence}")
    require(activate.index("guard currentConnectionToken == nil") < activate.index("foregroundIntegrityLossHandled = false"), "episode flag resets before reactivation guard")

    clear = view_exit.index("sdkDeviceMembershipVerified = false")
    status = view_exit.index("membershipStatus =")
    rotate = view_exit.index("membershipRequestID = UUID()")
    require(clear < status < rotate, "view-exit membership status ordering invalid")
    require("membership verified and leased" not in view_exit.lower(), "stale positive membership copy remains")

    require("guard phase != .accepted else { return }" in foreground, "sealed-acceptance guard missing")
    require("phase == .correlated || phase == .selected" in foreground, "correlated/selected foreground fence missing")
    require("resetDiscoverySessionOnly()" in foreground, "target reset missing")
    require("foreground_integrity_lost_after_target_correlation" in foreground, "target-reset diagnostic missing")
    require("Task { @MainActor [self] in" in foreground, "terminal task lifetime weakened")
    for forbidden in ("recordObservedTransportLoss", "endConnection", "disconnectBLE", "releasePackageCorrelationLease()"):
        require(forbidden not in foreground, f"foreground path invents authority: {forbidden}")

    require("<redacted-account-uid>" in receiver, "account UID marker missing")
    require('log("tuya_application_update", update.merging([' not in receiver, "raw application dictionary still enters event custody")
    require(']) { _, trusted in trusted })' in receiver, "trusted metadata precedence missing")
    require('"generation": String(token.diagnosticGeneration)' in receiver, "trusted generation provenance missing")
    require('"uid",' not in driver and '"uid"\n' not in driver, "blanket UID key suppression forbidden")
    require(driver.count('"sessionkey"') == 1, "sessionkey classifier is not singular")

    run("git", "diff", "--check")
    if shutil.which("swiftc"):
        run("swiftc", "-parse", str(ENTRY))
        for name in DONORS:
            run("swiftc", "-parse", str(TEST_ROOT / name))


def main() -> None:
    require(run("git", "rev-parse", f"{PARENT}:{ENTRY}", capture=True) == ENTRY_BLOB, "exact product Entrypoint blob moved")
    pre = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    require(sorted(pre) == sorted([str(WORKFLOW), str(SELF)]), f"unexpected helper pre-scope: {pre}")
    recover_tests()
    patch_product()
    validate()

    run("git", "config", "user.name", "nembra-sol-integration-closer")
    run("git", "config", "user.email", "actions@users.noreply.github.com")
    run("git", "rm", str(WORKFLOW), str(SELF))
    final = [ENTRY, *(TEST_ROOT / name for name in DONORS)]
    run("git", "add", *(str(p) for p in final))
    run("git", "diff", "--cached", "--check")
    run("git", "commit", "-m", "fix(capture): close current foreground and event custody reds")
    effective = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    require(sorted(effective) == sorted(str(p) for p in final), f"unexpected effective scope: {effective}")
    run("git", "diff", "--check", PARENT, "HEAD")
    run("git", "push", "origin", f"HEAD:{BRANCH}")


if __name__ == "__main__":
    main()
