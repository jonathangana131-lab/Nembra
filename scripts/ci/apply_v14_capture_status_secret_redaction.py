from pathlib import Path

path = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
text = path.read_text(encoding="utf-8")
replacements = [
    (
        "        selectedDeviceStatus = statusMap\n",
        "        selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]\n",
    ),
    (
        '            "status": selectedDeviceStatus ?? [:],\n',
        '            "status": Self.redactSecrets(selectedDeviceStatus ?? [:]),\n',
    ),
]
for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one status secret-custody match, found {count}: {old!r}")
    text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
