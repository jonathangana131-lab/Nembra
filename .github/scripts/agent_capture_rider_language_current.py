from pathlib import Path

path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = path.read_text(encoding="utf-8")

begin_marker = "    private var passiveSafetyPanel"
end_marker = "    private var captureDetailsSheet"
try:
    begin = text.index(begin_marker)
    end = text.index(end_marker, begin)
except ValueError as error:
    raise SystemExit(f"Capture rider surface anchor missing: {error}") from error

surface = text[begin:end]

# Prefer whole-copy replacements where the current primary state is engineering-facing.
whole_replacements = [
    (
        'Text("One sealed evidence life")',
        'Text("Read-only capture")',
    ),
    (
        'Text("Nembra carries the same package-owned Experiment One authority from repeated Bluetooth correlation into passive capture and immutable Horizon sealing. It performs no application characteristic-value writes and never turns a display name, RSSI, or service hint into target authority.")',
        'Text("Nembra keeps this entire capture read-only. It follows the same scooter signal from the four-step OFF / ON check through observation and sealing, without changing scooter settings or guessing identity from a name or signal strength.")',
    ),
    (
        'message: "The package-owned physical execution gate is closed. No OFF / ON window, connection, capture, or seal action can advance through this coordinator.",',
        'message: "The field safety lock is closed. No OFF / ON step, connection, capture, or seal action can begin until this exact build is authorized.",',
    ),
    (
        'message: "Nembra is connecting only to the package-owned correlated target. No application characteristic-value writes are permitted by this workflow.",',
        'message: "Nembra is connecting only to the same signal confirmed by the four-step check. This capture stays read-only and does not change scooter settings.",',
    ),
    (
        'message: "Nembra is passively discovering services, characteristics, descriptors, reads, and notifications for the exact run-owned target session. Ready is not shown until finite acquisition is mechanically complete.",',
        'message: "Nembra is checking which information the selected signal exposes for passive reading. Observation starts only after this read-only discovery step finishes.",',
    ),
    (
        'message: "The package-owned Ready epoch and required monotonic observation duration are both accepted. Finishing now requests one immutable Horizon from this same authority life.",',
        'message: "Read-only discovery is complete and the required observation time has been recorded. Seal now to freeze this capture exactly once.",',
    ),
    (
        'message: "Nembra is draining the accepted cutoff, committing Horizon, checking final authority, and materializing the immutable JSON artifact. Do not leave the app while this finishes.",',
        'message: "Nembra is finishing queued read-only observations, locking the capture boundary, checking integrity, and sealing the capture file. Keep Nembra open until this finishes.",',
    ),
    (
        'Text("Nembra is recording the bounded CoreBluetooth advertisement catalog for this exact window. Keep the phone nearby and the app foregrounded; do not open the stock scooter app during this series.")',
        'Text("Nembra is recording the Bluetooth signals visible during this window. Keep the phone nearby and Nembra foregrounded; do not open the stock scooter app during this series.")',
    ),
]

for old, new in whole_replacements:
    count = surface.count(old)
    if count != 1:
        raise SystemExit(f"Expected one exact rider-copy anchor, found {count}: {old}")
    surface = surface.replace(old, new, 1)

phrase_replacements = [
    ("The producer's evidence clock has not started yet.", "The capture timing window has not started yet."),
    (
        "The package producer accepts the window only from its own monotonic receipt boundary; tapping early cannot create evidence.",
        "The capture accepts this window only after the required observation time is recorded; tapping early cannot create evidence.",
    ),
    ("selectable full Bluetooth identifier", "Bluetooth device signal"),
    ("full CoreBluetooth identifier", "Bluetooth device identifier"),
    ("fresh post-admission scan", "fresh confirmation scan"),
    ("fresh scan epoch created after the sealed admission", "fresh confirmation scan"),
    ("Waiting for accepted Horizon authority", "Waiting to finish observation"),
    ("waiting for accepted Horizon authority", "waiting to finish observation"),
    ("Finite acquisition is Ready", "Read-only discovery is complete"),
    ("accepted monotonic observation interval", "required observation interval"),
    ("finite acquisition", "read-only discovery"),
    ('healthItem("FINITE"', 'healthItem("DISCOVERY"'),
    ('healthItem("HORIZON"', 'healthItem("SEAL"'),
    ("Finite acquisition ", "Read-only discovery "),
    ("HORIZON READY", "READY TO SEAL"),
    ("Evidence failed closed", "Capture stopped safely"),
    (
        "package-owned outer, SoftwareExport, and immutable Capture integrity checks",
        "final Share and nested capture integrity checks",
    ),
]

for old, new in phrase_replacements:
    if old in surface:
        surface = surface.replace(old, new)

banned = [
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
for phrase in banned:
    if phrase in surface:
        raise SystemExit(f"Primary Capture copy still exposes engineering phrase: {phrase}")

required = [
    "PASSIVE / READ ONLY",
    "Scooter OFF",
    "Scooter ON",
    "Share Capture",
    "View Details",
    "es80.capture.finish",
    "es80.capture.share",
    "es80.capture.view-details",
]
for phrase in required:
    if phrase not in surface:
        raise SystemExit(f"Rider-language transformation lost required product contract: {phrase}")

text = text[:begin] + surface + text[end:]
path.write_text(text, encoding="utf-8")
