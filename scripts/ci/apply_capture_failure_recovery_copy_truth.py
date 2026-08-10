#!/usr/bin/env python3
from pathlib import Path
import subprocess

BRANCH = "recovery/v14-capture-correlation-progress-truth-gpt56sol"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
WORKFLOW = Path(".github/workflows/apply-capture-failure-recovery-copy-truth.yml")
SELF = Path("scripts/ci/apply_capture_failure_recovery_copy_truth.py")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductRecoveryTruthSourceTests.swift")

source = APP.read_text()
old_condition = "                if test.failedAttemptCanRestartFromOFF1 && test.canRestartFromFreshOFF1 {\n"
new_condition = "                if failedRecoveryCanRestartInProcess {\n"
if source.count(old_condition) != 1:
    raise SystemExit(f"expected one failure-panel restart condition, found {source.count(old_condition)}")
source = source.replace(old_condition, new_condition, 1)

subtitle_old = '''        case .failed:
            return "No evidence was promoted past the blocker. Fix the condition and restart from scooter OFF."
'''
subtitle_new = '''        case .failed:
            return failedRecoveryCanRestartInProcess
                ? "No evidence was promoted past the blocker. Fix the condition and restart from scooter OFF."
                : "The prior session cannot restart safely in-process. Relaunch Capture before another scooter-OFF attempt."
'''
if source.count(subtitle_old) != 1:
    raise SystemExit(f"expected one unconditional failed hero subtitle, found {source.count(subtitle_old)}")
source = source.replace(subtitle_old, subtitle_new, 1)

anchor = '''    private var authorityReady: Bool {
'''
helper = '''    private var failedRecoveryCanRestartInProcess: Bool {
        test.failedAttemptCanRestartFromOFF1 && test.canRestartFromFreshOFF1
    }

'''
if source.count(anchor) != 1:
    raise SystemExit("authorityReady insertion anchor missing")
source = source.replace(anchor, helper + anchor, 1)
APP.write_text(source)

rendered = APP.read_text()
required = [
    "private var failedRecoveryCanRestartInProcess: Bool",
    "test.failedAttemptCanRestartFromOFF1 && test.canRestartFromFreshOFF1",
    "if failedRecoveryCanRestartInProcess",
    "return failedRecoveryCanRestartInProcess",
    "Relaunch Capture before another scooter-OFF attempt.",
]
for needle in required:
    if needle not in rendered:
        raise SystemExit(f"missing recovery-truth source contract: {needle}")
if not TEST.exists() or "failedRecoveryCanRestartInProcess" not in TEST.read_text():
    raise SystemExit("durable failure-recovery source contract is missing")

subprocess.run(["git", "diff", "--check"], check=True)
WORKFLOW.unlink()
SELF.unlink()
subprocess.run(["git", "add", str(APP), str(TEST), str(WORKFLOW), str(SELF)], check=True)
subprocess.run(["git", "diff", "--cached", "--check"], check=True)
subprocess.run(["git", "config", "user.name", "nembra-swarm-bot"], check=True)
subprocess.run(["git", "config", "user.email", "nembra-swarm-bot@users.noreply.github.com"], check=True)
subprocess.run(["git", "commit", "-m", "fix(capture): align failure guidance with restart authority"], check=True)
subprocess.run(["git", "push", "origin", f"HEAD:{BRANCH}"], check=True)
