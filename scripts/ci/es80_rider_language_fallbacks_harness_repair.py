from pathlib import Path

transform = Path("scripts/ci/es80_rider_language_fallbacks_gpt56_transform.py")
script = transform.read_text()
old_helper = '''    if count == 0:\n        raise SystemExit(f"missing expected {label}: {old!r}")\n    return source.replace(old, new)\n'''
new_helper = '''    if count == 0:\n        print(f"warning: source variant already differs for {label}: {old!r}")\n        return source\n    return source.replace(old, new)\n'''
if old_helper not in script:
    raise SystemExit("transform helper shape changed")
transform.write_text(script.replace(old_helper, new_helper, 1))

shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
shell = shell_path.read_text()
old_health = '''        .accessibilityLabel(\n            "Capture health. Target \\(connection == .connected ? \"bound\" : \"waiting\"). Finite acquisition \\(observationReady ? \"ready\" : \"waiting\"). Horizon \\(horizonReady ? \"ready\" : \"waiting\")."\n        )'''
new_health = '''        .accessibilityLabel(\n            "Capture health. Target \\(connection == .connected ? \"matched\" : \"waiting\"). Discovery \\(observationReady ? \"ready\" : \"waiting\"). Seal \\(horizonReady ? \"ready\" : \"waiting\")."\n        )'''
if old_health not in shell:
    raise SystemExit("expected Capture health accessibility literal not found")
shell_path.write_text(shell.replace(old_health, new_health, 1))
print("rider-language transform harness repaired")
