#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess

BRANCH = "integration/v14-capture-authority-provenance-convergence-sol"
PARENT = "7282a3ecb02a55c40f31e56ae6117a773a4e484f"
ENTRY = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
ENTRY_BLOB = "f3201e22828a1fdccbbc8235796e96344220b05d"
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegrityCurrentSourceTests.swift")
TEST_BLOB = "13e0ffadaf6348b39b680e980e404447d45f9545"
WORKFLOW = Path(".github/workflows/materialize-v14-capture-foreground-reactivation-fence-sol.yml")
SELF = Path("scripts/ci/materialize_v14_capture_foreground_reactivation_fence_sol.py")


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    require(source.count(old) == 1, f"{label}: expected exactly one match, found {source.count(old)}")
    return source.replace(old, new, 1)


def main() -> None:
    require(run("git", "rev-parse", f"{PARENT}:{ENTRY}", capture=True) == ENTRY_BLOB, "entrypoint parent blob moved")
    require(run("git", "rev-parse", f"{PARENT}:{TEST}", capture=True) == TEST_BLOB, "foreground test parent blob moved")
    pre = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    require(sorted(pre) == sorted([str(WORKFLOW), str(SELF)]), f"unexpected helper pre-scope: {pre}")

    source = ENTRY.read_text(encoding="utf-8")
    source = replace_once(
        source,
        '''    func activateMembershipRequestsForView() {
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
''',
        '''    func activateMembershipRequestsForView() {
        // A foreground-return callback must never reopen view authority while an exact authenticated
        // generation is still terminally retiring. Pre-handoff interrupted discovery can reopen only
        // after its scanner/target authority is fully gone; post-Tuya-handoff failures remain relaunch-only.
        guard currentConnectionToken == nil,
              localBLESettlementToken == nil,
              driver == nil,
              processCorrelationLease == nil,
              correlationSession == nil else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
''',
        "safe foreground reactivation",
    )
    ENTRY.write_text(source, encoding="utf-8")

    test = TEST.read_text(encoding="utf-8")
    anchor = '''        #expect(controller.contains("func appDidLoseForeground()"))
    }
'''
    extra = '''        #expect(controller.contains("func appDidLoseForeground()"))

        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))
        for fence in [
            "currentConnectionToken == nil",
            "localBLESettlementToken == nil",
            "driver == nil",
            "processCorrelationLease == nil",
            "correlationSession == nil"
        ] {
            #expect(activation.contains(fence), "foreground return must not reopen membership during retained authority: \\(fence)")
        }
        let fence = try requiredOffset(containing: "guard currentConnectionToken == nil", in: activation)
        let reopen = try requiredOffset(containing: "foregroundIntegrityLossHandled = false", in: activation)
        #expect(fence < reopen)
    }
'''
    test = replace_once(test, anchor, extra, "foreground reactivation regression")
    helper_anchor = '''    private func entrypointSource() throws -> String {
'''
    helper = '''    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \\(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private func entrypointSource() throws -> String {
'''
    test = replace_once(test, helper_anchor, helper, "requiredOffset helper")
    TEST.write_text(test, encoding="utf-8")

    patched = ENTRY.read_text(encoding="utf-8")
    activation = patched[patched.index("func activateMembershipRequestsForView()"):patched.index("func abandonCorrelationForViewExit()")]
    for required in (
        "currentConnectionToken == nil",
        "localBLESettlementToken == nil",
        "driver == nil",
        "processCorrelationLease == nil",
        "correlationSession == nil",
        "foregroundIntegrityLossHandled = false",
        "acceptsViewScopedMembershipRequests = true",
    ):
        require(required in activation, f"reactivation fence missing {required}")
    require(activation.index("guard currentConnectionToken == nil") < activation.index("foregroundIntegrityLossHandled = false"), "episode flag resets before authority fence")
    run("git", "diff", "--check")
    if shutil.which("swiftc"):
        run("swiftc", "-parse", str(ENTRY))
        run("swiftc", "-parse", str(TEST))

    run("git", "config", "user.name", "nembra-sol-integration-closer")
    run("git", "config", "user.email", "actions@users.noreply.github.com")
    run("git", "rm", str(WORKFLOW), str(SELF))
    run("git", "add", str(ENTRY), str(TEST))
    run("git", "diff", "--cached", "--check")
    run("git", "commit", "-m", "fix(capture): fence foreground authority reactivation")
    effective = run("git", "diff", "--name-only", f"{PARENT}...HEAD", capture=True).splitlines()
    require(sorted(effective) == sorted([str(ENTRY), str(TEST)]), f"unexpected effective race-fix scope: {effective}")
    run("git", "push", "origin", f"HEAD:{BRANCH}")


if __name__ == "__main__":
    main()
