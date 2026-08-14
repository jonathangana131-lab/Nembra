#!/usr/bin/env python3
"""Capture fail-closed standalone Nembra Capture presentation evidence on iPhone 12/iOS 27 Simulator."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import platform
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
APP_PATH = Path(os.environ.get("APP_PATH", "/tmp/NembraCaptureProvenanceDerived/Build/Products/Debug-iphonesimulator/Nembra Capture.app"))
ARTIFACTS = Path(os.environ.get("ARTIFACTS_DIR", os.path.join(os.environ.get("RUNNER_TEMP", "/tmp"), "NembraCaptureStandaloneVisualEvidence")))
BUNDLE_ID = "com.jonathangana131.nembra.capturelearn"
PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"
DEVICE_NAME = "iPhone 12"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-12"
MAX_ATTEMPTS = 40
RETRY_SECONDS = 0.25


def run(*args: str, capture: bool = False, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=check, text=True, capture_output=capture)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_guard():
    path = ROOT / "scripts/ci/capture_visual_png_content_guard.py"
    spec = importlib.util.spec_from_file_location("capture_visual_png_content_guard", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load rendered-content guard")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, path


def exact_runtime() -> str:
    payload = json.loads(run("xcrun", "simctl", "list", "runtimes", "-j", capture=True).stdout)
    choices = [
        item for item in payload["runtimes"]
        if item.get("isAvailable", True)
        and str(item.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")
    ]
    if not choices:
        raise RuntimeError("no iOS 27 Simulator runtime available")
    choices.sort(key=lambda item: tuple(int(x) for x in re.findall(r"\d+", str(item.get("version", "0")))), reverse=True)
    return str(choices[0]["identifier"])


def exact_device_type() -> str:
    payload = json.loads(run("xcrun", "simctl", "list", "devicetypes", "-j", capture=True).stdout)
    for item in payload["devicetypes"]:
        if item.get("name") == DEVICE_NAME:
            identifier = str(item["identifier"])
            if identifier != DEVICE_TYPE:
                raise RuntimeError(f"unexpected iPhone 12 device type: {identifier}")
            return identifier
    raise RuntimeError("iPhone 12 Simulator device type unavailable")


def launch(udid: str) -> int:
    out = run("xcrun", "simctl", "launch", udid, BUNDLE_ID, capture=True).stdout.strip()
    match = re.search(r":\s*(\d+)\s*$", out)
    if not match:
        raise RuntimeError(f"could not parse launch pid: {out}")
    return int(match.group(1))


def process_alive(pid: int) -> bool:
    return subprocess.run(["/bin/kill", "-0", str(pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def capture_ready(guard, udid: str, pid: int, output: Path, label: str, log_path: Path) -> None:
    pending = output.with_suffix(".pending.png")
    for attempt in range(1, MAX_ATTEMPTS + 1):
        if not process_alive(pid):
            raise RuntimeError(f"{label}: app exited before rendered evidence was ready")
        shot = subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(pending)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if shot.returncode == 0:
            try:
                result = guard.inspect_rendered_content(pending)
            except Exception as exc:
                result = {"ready": False, "error": str(exc)}
            with log_path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps({"label": label, "attempt": attempt, **result}, sort_keys=True) + "\n")
            if result.get("ready") is True:
                pending.replace(output)
                return
        if attempt < MAX_ATTEMPTS:
            time.sleep(RETRY_SECONDS)
    raise RuntimeError(f"{label}: no non-trivial rendered screenshot within bounded attempts")


def main() -> int:
    if platform.system() != "Darwin" or shutil.which("xcrun") is None:
        raise RuntimeError("visual evidence requires macOS/CoreSimulator")
    if not APP_PATH.is_dir():
        raise RuntimeError(f"missing standalone app: {APP_PATH}")
    for name in os.environ:
        if name.startswith("SIMCTL_CHILD_") or name.startswith("NEMBRA_SIMULATION_"):
            raise RuntimeError(f"synthetic authority environment forbidden: {name}")
    info_path = APP_PATH / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    source_sha = str(info.get("NembraCaptureSourceCommitSHA", "")).lower()
    build_id = str(info.get("NembraCaptureBuildIdentifier", ""))
    dependency = str(info.get("NembraCaptureTuyaDependencyLockSHA256", "")).lower()
    procedure = str(info.get("NembraCaptureProcedureIdentifier", ""))
    if info.get("CFBundleIdentifier") != BUNDLE_ID or not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise RuntimeError("standalone build identity is malformed")
    if dependency or procedure != PROCEDURE or build_id != f"capture-v14-{source_sha[:12]}":
        raise RuntimeError("public visual build carries non-public or mismatched authority")
    checkout_sha = run("git", "rev-parse", "HEAD", capture=True).stdout.strip().lower()
    if source_sha != checkout_sha:
        raise RuntimeError("built app is not stamped from exact checkout")
    identity = (ROOT / "NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")
    if f'static let requiredFieldProcedureIdentifier = "{PROCEDURE}"' not in identity:
        raise RuntimeError("canonical procedure source contract missing")
    guard, guard_path = load_guard()
    if ARTIFACTS.exists() or ARTIFACTS.is_symlink():
        raise RuntimeError(f"refusing prior evidence directory: {ARTIFACTS}")
    (ARTIFACTS / "screenshots").mkdir(parents=True)
    (ARTIFACTS / "logs").mkdir()
    runtime = exact_runtime()
    device_type = exact_device_type()
    sim_name = f"Nembra Capture Visual {os.environ.get('GITHUB_RUN_ID', 'local')}-{os.environ.get('GITHUB_RUN_ATTEMPT', '0')}"
    udid = run("xcrun", "simctl", "create", sim_name, device_type, runtime, capture=True).stdout.strip()
    try:
        run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b")
        run("xcrun", "simctl", "install", udid, str(APP_PATH))
        subprocess.run(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "82", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run("xcrun", "simctl", "ui", udid, "appearance", "dark")
        standard = ARTIFACTS / "screenshots/standalone-unprovisioned-dark-iphone12.png"
        pid = launch(udid)
        capture_ready(guard, udid, pid, standard, "standard", ARTIFACTS / "logs/screenshot-readiness.jsonl")
        run("xcrun", "simctl", "ui", udid, "content_size", "accessibility-extra-extra-extra-large")
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ax5 = ARTIFACTS / "screenshots/standalone-unprovisioned-dark-iphone12-ax5.png"
        pid = launch(udid)
        capture_ready(guard, udid, pid, ax5, "accessibility-xxxl", ARTIFACTS / "logs/screenshot-readiness.jsonl")
        record = {
            "schemaVersion": 7,
            "authority": "standalone-capture-simulator-presentation-only",
            "buildIdentifier": build_id,
            "sourceCommitSHA": source_sha,
            "tuyaDependencyLockSHA256": "",
            "expectedFieldBuildAuthority": False,
            "procedureIdentifier": procedure,
            "baselineDevice": DEVICE_NAME,
            "baselineOS": "iOS 27",
            "simulatorRuntime": runtime,
            "simulatorDeviceType": device_type,
            "syntheticAuthorityEnvironmentRejected": True,
            "visualAcceptanceRequiresHumanReview": True,
            "screenshotRenderedContentReadinessVerified": True,
            "screenshotRenderedContentGuard": "capture_visual_png_content_guard.py/v1",
            "screenshotRenderedContentGuardSHA256": sha256(guard_path),
            "physicalAuthorityCreated": False,
            "protocolAuthorityCreated": False,
            "screenshots": [
                {"state": "unprovisioned-dark-standard", "relativePath": str(standard.relative_to(ARTIFACTS)), "sha256": sha256(standard)},
                {"state": "unprovisioned-dark-accessibility-xxxl", "relativePath": str(ax5.relative_to(ARTIFACTS)), "sha256": sha256(ax5)},
            ],
            "infoPlistSHA256": sha256(info_path),
        }
        (ARTIFACTS / "NembraCaptureStandaloneVisualEvidence.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    finally:
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["xcrun", "simctl", "shutdown", udid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["xcrun", "simctl", "delete", udid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())