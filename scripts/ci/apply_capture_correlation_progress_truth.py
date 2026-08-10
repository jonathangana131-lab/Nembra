#!/usr/bin/env python3
from pathlib import Path
import subprocess

BRANCH = "recovery/v14-capture-correlation-progress-truth-gpt56sol"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
WORKFLOW = Path(".github/workflows/apply-capture-correlation-progress-truth.yml")
SELF = Path("scripts/ci/apply_capture_correlation_progress_truth.py")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelationProgressPresentationTruthSourceTests.swift")

source = APP.read_text()
old = '                    Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")\n'
new = '                    Text("\\(correlationDisplayedWindowOrdinal)/4")\n'
if source.count(old) != 1:
    raise SystemExit(f"expected one correlation ordinal Text anchor, found {source.count(old)}")
source = source.replace(old, new, 1)
anchor = '    private var currentStageIndex: Int {\n'
property_text = '''    private var correlationDisplayedWindowOrdinal: Int {
        test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)
    }

'''
if source.count(anchor) != 1:
    raise SystemExit("currentStageIndex insertion anchor missing")
source = source.replace(anchor, property_text + anchor, 1)
APP.write_text(source)

# Construction checks only. Apple/Xcode acceptance belongs to the clean product head.
rendered = APP.read_text()
if rendered.count('Text("\\(correlationDisplayedWindowOrdinal)/4")') != 1:
    raise SystemExit("phase-aware correlation ordinal is not wired exactly once")
if rendered.count('private var correlationDisplayedWindowOrdinal: Int') != 1:
    raise SystemExit("phase-aware correlation ordinal property is not unique")
if 'test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)' not in rendered:
    raise SystemExit("correlated phase must present the completed fourth window")
if 'Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")' in rendered:
    raise SystemExit("raw completed-window expression is still rendered directly")
if not TEST.exists() or 'correlationDisplayedWindowOrdinal' not in TEST.read_text():
    raise SystemExit("durable correlation-progress source contract is missing")

subprocess.run(["git", "diff", "--check"], check=True)
WORKFLOW.unlink()
SELF.unlink()
subprocess.run(["git", "add", str(APP), str(TEST), str(WORKFLOW), str(SELF)], check=True)
subprocess.run(["git", "diff", "--cached", "--check"], check=True)
subprocess.run(["git", "config", "user.name", "nembra-swarm-bot"], check=True)
subprocess.run(["git", "config", "user.email", "nembra-swarm-bot@users.noreply.github.com"], check=True)
subprocess.run(["git", "commit", "-m", "fix(capture): show completed correlation as four of four"], check=True)
subprocess.run(["git", "push", "origin", f"HEAD:{BRANCH}"], check=True)
