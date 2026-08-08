from pathlib import Path

path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = path.read_text(encoding="utf-8")

replacements = [
    (
        'Text("Nembra keeps one continuous read-only capture from Scooter OFF / Scooter ON matching through the final seal. It never sends application characteristic-value writes, and names, signal strength, or service hints never decide which signal belongs to this run.")',
        'Text("Nembra keeps one continuous read-only capture from Scooter OFF / Scooter ON matching through the final seal. It never changes scooter settings or sends controls, and names, signal strength, or service hints never decide which signal belongs to this run.")',
    ),
    ('eyebrow: "FIELD AUTHORITY",', 'eyebrow: "CAPTURE LOCKED",'),
    (
        '.accessibilityHint("Nembra is recording this bounded Bluetooth observation window.")',
        '.accessibilityHint("Nembra is recording Bluetooth signals for this observation window.")',
    ),
    (
        '.accessibilityHint("The package producer, not this timer, decides whether the window has enough evidence.")',
        '.accessibilityHint("This countdown is guidance only. Nembra records the window only after the required observation is accepted.")',
    ),
    (
        'message: "No selectable full Bluetooth identifier was absent in both OFF windows and repeated in both ON windows. Nembra will not guess from name, signal strength, service hints, or short IDs.",',
        'message: "No Bluetooth signal stayed absent in both OFF windows and repeated in both ON windows. Nembra will not guess from name, signal strength, service hints, or short IDs.",',
    ),
    (
        'message: "More than one selectable full Bluetooth identifier repeated the OFF / ON pattern. Nembra refuses to break the tie with display name, RSSI, services, or a short identifier.",',
        'message: "More than one Bluetooth signal repeated the OFF / ON pattern. Nembra refuses to break the tie with display name, signal strength, services, or a short identifier.",',
    ),
    (
        'message: "Nembra is connecting only to the signal confirmed by the OFF / ON sequence. This workflow remains read only and does not send application characteristic-value writes.",',
        'message: "Nembra is connecting only to the signal confirmed by the OFF / ON sequence. This workflow remains read only and does not change scooter settings or send controls.",',
    ),
    (
        '.accessibilityHint("Available only after the package accepts the required monotonic observation duration.")',
        '.accessibilityHint("Available only after the required observation time has been recorded.")',
    ),
    ('eyebrow: "HORIZON READY",', 'eyebrow: "READY TO SEAL",'),
    ('healthItem("FINITE", value: observationReady ? "READY" : "WAIT")', 'healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")'),
    ('healthItem("HORIZON", value: horizonReady ? "READY" : "HOLD")', 'healthItem("SEAL", value: horizonReady ? "READY" : "HOLD")'),
    (
        '"Capture health. Target \\(connection == .connected ? \"bound\" : \"waiting\"). Finite acquisition \\(observationReady ? \"ready\" : \"waiting\"). Horizon \\(horizonReady ? \"ready\" : \"waiting\")."',
        '"Capture health. Target \\(connection == .connected ? \"bound\" : \"waiting\"). Read-only discovery \\(observationReady ? \"ready\" : \"waiting\"). Seal \\(horizonReady ? \"ready\" : \"waiting\")."',
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one current rider-copy anchor, found {count}: {old}")
    text = text.replace(old, new, 1)

begin = text.index("    private var passiveSafetyPanel")
end = text.index("    private var captureDetailsSheet", begin)
rider_surface = text[begin:end]

banned = [
    "One sealed evidence life",
    "package-owned Experiment One authority",
    "package-owned physical execution gate",
    "producer's evidence clock",
    "producer accepts the window only from its own monotonic receipt boundary",
    "full CoreBluetooth identifier",
    "selectable full Bluetooth identifier",
    "post-admission scan",
    "fresh scan epoch created after the sealed admission",
    "package-owned correlated target",
    "finite acquisition",
    "Finite acquisition",
    "accepted Horizon authority",
    "accepted monotonic observation interval",
    "package-owned Ready epoch",
    "committing Horizon",
    "immutable JSON artifact",
    "Evidence failed closed",
    "bounded CoreBluetooth advertisement catalog",
    "package-owned outer, SoftwareExport, and immutable Capture integrity checks",
    "application characteristic-value writes",
    "package producer",
    "HORIZON READY",
    'healthItem("FINITE"',
    'healthItem("HORIZON"',
    'eyebrow: "FIELD AUTHORITY"',
]
for phrase in banned:
    if phrase in rider_surface:
        raise SystemExit(f"Primary Capture copy still exposes engineering vocabulary: {phrase}")

for phrase in [
    "Scooter OFF",
    "Scooter ON",
    "Share Capture",
    "View Details",
    "DISCOVERY",
    "SEAL",
    "es80.capture.finish",
    "es80.capture.share",
    "es80.capture.view-details",
]:
    if phrase not in rider_surface:
        raise SystemExit(f"Rider surface lost required product contract: {phrase}")

if "PASSIVE / READ ONLY" not in text:
    raise SystemExit("Persistent read-only badge is missing")
if "private var captureDetailsSheet" not in text or "CoreBluetooth" not in text[end:]:
    raise SystemExit("Engineering truth no longer remains under Capture Details")

path.write_text(text, encoding="utf-8")
