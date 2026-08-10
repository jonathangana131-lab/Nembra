from pathlib import Path
import shutil
import subprocess

PRODUCT = "a7a28ca6e744d4bad8be08fd3553a2af8c609b15"
BRANCH = "repair/v14-capture-auth-promotion-reentrancy-a7-sol"
WORKFLOW = Path(".github/workflows/materialize-capture-auth-promotion-reentrancy-a7-sol.yml")
HELPER = Path(".github/materializers/capture_auth_promotion_reentrancy_a7_sol.py")
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticationPromotionReentrancySourceTests.swift")
RED = "369e8ec57de89070126eab0bf6057280a8e366da"


def run(*args: str, capture: bool = True) -> str:
    completed = subprocess.run(args, check=True, text=True, capture_output=capture)
    return completed.stdout.strip() if capture else ""


if run("git", "rev-parse", "HEAD^^") != PRODUCT:
    raise SystemExit("materializer ancestry mismatch")
changed = set(run("git", "diff", "--name-only", PRODUCT, "HEAD").splitlines())
if changed != {str(HELPER), str(WORKFLOW)}:
    raise SystemExit(f"unexpected scaffold scope: {sorted(changed)}")

subprocess.run(["git", "fetch", "--no-tags", "origin", RED], check=True)
red_test = run("git", "show", f"{RED}:{TEST}")
TEST.write_text(red_test + "\n", encoding="utf-8")

source = APP.read_text(encoding="utf-8")
old = '''                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
'''
new = '''                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()

                    // Both actor hops above can interleave foreground/view/account teardown. Never
                    // repaint a generation as observing after another terminal path retired its app authority.
                    guard currentConnectionToken == token else {
                        log("retired_authentication_promotion_ignored", [
                            "generation": String(token.diagnosticGeneration)
                        ])
                        return
                    }
                    guard phase == .authenticating else {
                        log("authentication_promotion_outside_active_phase_ignored", [
                            "generation": String(token.diagnosticGeneration),
                            "phase": phase.rawValue
                        ])
                        return
                    }
                    guard sdkAccountLoggedIn,
                          sdkDeviceMembershipVerified,
                          accountIdentityLeaseIsAuthorized else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Tuya account/device source authority changed while authenticated state was being promoted.",
                            kind: "sdk_source_authority_lost_during_auth_promotion"
                        )
                        return
                    }
                    phase = .observing
'''
if source.count(old) != 1:
    raise SystemExit(f"expected authenticated promotion anchor once, found {source.count(old)}")
APP.write_text(source.replace(old, new, 1), encoding="utf-8")

repaired = APP.read_text(encoding="utf-8")
auth = repaired[repaired.index("private func authenticated(token: TuyaReadOnlyConnectionToken) async"):repaired.index("private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async")]
promote = auth.index("try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)")
refresh = auth.index("await refreshLedgerSnapshot()", promote)
observing = auth.index("phase = .observing", refresh)
fence = auth[refresh:observing]
for token in ("currentConnectionToken == token", "phase == .authenticating", "accountIdentityLeaseIsAuthorized"):
    if token not in fence:
        raise SystemExit(f"missing post-await authority fence: {token}")
if "retired_authentication_promotion_ignored" not in fence:
    raise SystemExit("retired generation ignore path missing")
if "sdk_source_authority_lost_during_auth_promotion" not in fence:
    raise SystemExit("source-authority terminal missing")
if auth.index("startWatchdog(token: token)", observing) <= observing:
    raise SystemExit("watchdog ordering invalid")

view = repaired[repaired.index("func abandonCorrelationForViewExit()"):repaired.index("func appDidLoseForeground()")]
fg = repaired[repaired.index("func appDidLoseForeground()"):repaired.index("var privateConfig: Bool")]
for block in (view, fg):
    start = block.index("if phase == .correlated || phase == .selected")
    tail = block.index("return", start)
    completed = block[start:tail]
    for token in ("pendingCorrelatedTargetID = nil", "selectedID = nil", "targetCorrelationOperatorConfirmed = false"):
        if token not in completed:
            raise SystemExit(f"correlation retention drift: {token}")
    if "resetDiscoverySessionOnly()" in completed:
        raise SystemExit("completed correlation evidence would be erased")

bridge = Path("NembraApp/Features/Research/TuyaAccountBridge.swift").read_text(encoding="utf-8")
if '"specifications": Self.redactSecrets(selectedDeviceSpecifications ?? [:])' not in bridge:
    raise SystemExit("final metadata export custody drifted")
if '"localStrategy": Self.redactSecrets(selectedDeviceLocalStrategy ?? [:])' not in bridge:
    raise SystemExit("final metadata export custody drifted")

subprocess.run(["git", "diff", "--check"], check=True)
if shutil.which("swiftc"):
    subprocess.run(["swiftc", "-parse", str(APP)], check=True)
    subprocess.run(["swiftc", "-parse", str(TEST)], check=True)

WORKFLOW.unlink()
HELPER.unlink()
subprocess.run(["git", "config", "user.name", "nembra-v14-sol"], check=True)
subprocess.run(["git", "config", "user.email", "actions@users.noreply.github.com"], check=True)
subprocess.run(["git", "add", str(APP), str(TEST), str(WORKFLOW), str(HELPER)], check=True)
subprocess.run(["git", "diff", "--cached", "--check"], check=True)
subprocess.run(["git", "commit", "-m", "fix(capture): fence authenticated promotion after actor hops"], check=True)
final_paths = set(run("git", "diff", "--name-only", PRODUCT, "HEAD").splitlines())
if final_paths != {str(APP), str(TEST)}:
    raise SystemExit(f"unexpected final scope: {sorted(final_paths)}")
subprocess.run(["git", "push", "origin", f"HEAD:{BRANCH}"], check=True)
