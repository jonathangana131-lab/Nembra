from pathlib import Path

path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = path.read_text()

replacements = [
    ('Text("One sealed evidence life")', 'Text("One passive capture, start to finish")'),
    ('Text("Nembra carries the same package-owned Experiment One authority from repeated Bluetooth correlation into passive capture and immutable Horizon sealing. It performs no application characteristic-value writes and never turns a display name, RSSI, or service hint into target authority.")', 'Text("Nembra keeps one continuous passive capture from the four OFF / ON checks through the final seal. It sends no application-level scooter commands and never guesses the target from its name, signal strength, or service hints.")'),
    ('message: "The package-owned physical execution gate is closed. No OFF / ON window, connection, capture, or seal action can advance through this coordinator."', 'message: "Capture is locked for this build. Nembra cannot start the OFF / ON sequence, connect, record, or seal until this exact build is cleared for the field procedure."'),
    ('message: "Nembra is waiting for this exact window to report Bluetooth powered-on and active scanning. The producer\'s evidence clock has not started yet."', 'message: "Nembra is waiting for Bluetooth to be ready and actively scanning for this window. Timing starts only after Capture marks the window active."'),
    ('guidanceFootnote("This countdown is display guidance only. The package producer accepts the window only from its own monotonic receipt boundary; tapping early cannot create evidence.")', 'guidanceFootnote("This countdown is guidance only. Nembra decides when enough observation has been recorded; tapping early cannot create a valid window.")'),
    ('message: "One full CoreBluetooth identifier was selectable in both ON windows and absent from both OFF catalogs under this exact package-owned observation series. Treat it only as a correlated Bluetooth target."', 'message: "One Bluetooth signal appeared in both ON windows and stayed absent from both OFF windows. Nembra treats it only as the correlated target for this capture, not as permanent scooter identification."'),
    ('message: "A fresh post-admission scan is looking for the exact full identifier that passed both OFF / ON cycles. Keep the scooter in the ON state from the final window."', 'message: "Nembra is looking again for the same Bluetooth signal that passed both OFF / ON cycles. Keep the scooter ON from the final window."'),
    ('message: "The same full CoreBluetooth identifier reappeared in the fresh scan epoch created after the sealed admission. This remains local correlation evidence, not permanent hardware authentication."', 'message: "The same Bluetooth signal reappeared in a fresh scan. That is enough to continue this capture, but it is not permanent hardware identification."'),
    ('message: "Nembra is connecting only to the package-owned correlated target. No application characteristic-value writes are permitted by this workflow."', 'message: "Nembra is opening only the correlated Bluetooth target from this run. Capture remains passive and sends no application-level scooter commands."'),
    ('eyebrow: "PASSIVE ACQUISITION"', 'eyebrow: "PASSIVE DISCOVERY"'),
    ('message: "Nembra is passively discovering services, characteristics, descriptors, reads, and notifications for the exact run-owned target session. Ready is not shown until finite acquisition is mechanically complete."', 'message: "Nembra is passively learning what this Bluetooth target exposes. Capture will not show Ready until discovery is complete."'),
    ('title: remaining == 0 ? "Waiting for accepted Horizon authority" : "Hold observation — \\(remaining)s"', 'title: remaining == 0 ? "Waiting for capture readiness" : "Hold observation — \\(remaining)s"'),
    ('message: "Finite acquisition is Ready. Keep Nembra foregrounded and the scooter stationary while the accepted monotonic observation interval matures. The displayed timer is guidance only."', 'message: "Passive discovery is complete. Keep Nembra foregrounded and the scooter stationary while the required observation period finishes. The displayed timer is guidance only."'),
    ('"Display guidance complete; waiting for accepted Horizon authority"', '"Display guidance complete; waiting for capture readiness"'),
    ('"Unavailable; waiting for accepted Horizon authority"', '"Unavailable; waiting for capture readiness"'),
    ('accessibilityHint("Available only after the package accepts the required monotonic observation duration.")', 'accessibilityHint("Available only after Nembra confirms the required observation period.")'),
    ('eyebrow: "HORIZON READY"', 'eyebrow: "READY TO SEAL"'),
    ('message: "The package-owned Ready epoch and required monotonic observation duration are both accepted. Finishing now requests one immutable Horizon from this same authority life."', 'message: "Discovery and the required observation period are complete. Sealing now freezes this capture exactly once."'),
    ('title: "Freezing immutable evidence"', 'title: "Sealing capture"'),
    ('message: "Nembra is draining the accepted cutoff, committing Horizon, checking final authority, and materializing the immutable JSON artifact. Do not leave the app while this finishes."', 'message: "Nembra is finishing the accepted observation boundary, checking the sealed result, and preparing the final capture. Keep the app open until this finishes."'),
    ('title: "Evidence failed closed"', 'title: "This capture cannot continue"'),
    ('Text("Nembra is recording the bounded CoreBluetooth advertisement catalog for this exact window. Keep the phone nearby and the app foregrounded; do not open the stock scooter app during this series.")', 'Text("Nembra is watching nearby Bluetooth signals for this window. Keep the phone nearby and Nembra foregrounded, and do not open the stock scooter app during the four-window sequence.")'),
    ('healthItem("FINITE", value: observationReady ? "READY" : "WAIT")', 'healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")'),
    ('healthItem("HORIZON", value: horizonReady ? "READY" : "HOLD")', 'healthItem("SEAL", value: horizonReady ? "READY" : "HOLD")'),
    ('"Capture health. Target \\(connection == .connected ? \"bound\" : \"waiting\"). Finite acquisition \\(observationReady ? \"ready\" : \"waiting\"). Horizon \\(horizonReady ? \"ready\" : \"waiting\")."', '"Capture health. Target \\(connection == .connected ? \"bound\" : \"waiting\"). Passive discovery \\(observationReady ? \"ready\" : \"waiting\"). Seal \\(horizonReady ? \"ready\" : \"waiting\")."'),
    ('Text("The exact \\(report.finalShareByteCount.formatted())-byte final Share artifact passed the package-owned outer, SoftwareExport, and immutable Capture integrity checks. No protocol field meaning is claimed yet.")', 'Text("The final Share package passed every required integrity check and is ready to export. Nembra has not assigned meaning to any scooter data fields yet.")'),
    ('Text("\\(artifact.captureJSON.count.formatted()) immutable capture bytes are sealed from this Experiment One authority. Analysis readiness is not earned until the package verifies the exact final Share bytes and their nested evidence.")', 'Text("Capture is sealed. Nembra still needs to verify the final Share package before marking it ready for analysis.")'),
    ('return .failed("Nembra left the active foreground after Experiment One began. This evidence life cannot regain capture authority; start a fresh Experiment One.")', 'return .failed("Nembra left the foreground after Capture began, so this run can no longer be trusted. Start a fresh Experiment One.")'),
    ('return .failed(coordinator.lastDiagnostic ?? "The passive target connection ended before an accepted observation could be sealed. Start a fresh Experiment One rather than replaying consumed authority.")', 'return .failed(coordinator.lastDiagnostic ?? "The passive Bluetooth connection ended before Capture could be sealed. Start a fresh Experiment One.")'),
    ('return .bluetoothUnavailable("The package-owned CoreBluetooth controller is unavailable for this coordinator.")', 'return .bluetoothUnavailable("Bluetooth capture is unavailable in this build.")'),
    ('return .correlationFailed("The four windows did not preserve one valid package-issued observation authority and required OFF 1, ON 1, OFF 2, ON 2 ordering.")', 'return .correlationFailed("The four observation windows did not preserve the required OFF 1, ON 1, OFF 2, ON 2 sequence. Restart from OFF 1.")'),
    ('return .correlationFailed("The package-owned Experiment One workflow has no active correlation progress and no final result.")', 'return .correlationFailed("Capture cannot find an active OFF / ON observation sequence. Start a fresh Experiment One.")'),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one rider-copy anchor, found {count}: {old[:120]}")
    text = text.replace(old, new, 1)

start = text.index("private var passiveSafetyPanel")
end = text.index("private var captureDetailsSheet", start)
rider = text[start:end]
forbidden = [
    "One sealed evidence life",
    "package-owned Experiment One authority",
    "package-owned physical execution gate",
    "producer's evidence clock",
    "producer accepts the window only from its own monotonic receipt boundary",
    "full CoreBluetooth identifier",
    "post-admission scan",
    "fresh scan epoch created after the sealed admission",
    "package-owned correlated target",
    "finite acquisition",
    "accepted Horizon authority",
    "accepted monotonic observation interval",
    "package-owned Ready epoch",
    "committing Horizon",
    "immutable JSON artifact",
    "Evidence failed closed",
    "bounded CoreBluetooth advertisement catalog",
    "package-owned outer, SoftwareExport, and immutable Capture integrity checks",
]
for phrase in forbidden:
    if phrase in rider:
        raise SystemExit(f"engineering phrase remains in primary rider surface: {phrase}")

for phrase in ("PASSIVE / READ ONLY", "Scooter OFF", "Scooter ON", "Share Capture", "View Details"):
    if phrase not in rider:
        raise SystemExit(f"required rider-facing phrase disappeared: {phrase}")

details = text[text.index("private var captureDetailsSheet"):]
for phrase in ("Truth boundary", "CoreBluetooth", "Software Export SHA-256", "Runtime executable SHA-256", "does not authenticate the physical ES80"):
    if phrase not in details:
        raise SystemExit(f"technical truth disappeared from Details: {phrase}")

for token in (
    "guard status.physicalProcedurePermitted else",
    "declaredStationarySetup = nil",
    "PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)",
    "finalShareIntegrityReport != nil",
    "es80.capture.begin-window",
    "es80.capture.confirm-setup",
    "es80.capture.complete-window",
    "es80.capture.restart-correlation",
    "es80.capture.confirm-correlated-target",
    "es80.capture.restart-rediscovery",
    "es80.capture.connect-prepared-target",
    "es80.capture.finish",
    "es80.capture.share",
    "es80.capture.prepare-share",
    "es80.capture.share-unavailable",
    "es80.capture.view-details",
    "es80.capture.restart-experiment",
    "es80.capture.experiment-progress",
    "es80.capture.single-authority",
    "es80.capture.complete",
    "es80.capture-shell",
):
    if token not in text:
        raise SystemExit(f"truth/action contract disappeared: {token}")

path.write_text(text)
