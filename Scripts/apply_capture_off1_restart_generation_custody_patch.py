from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()
old = '''        guard currentConnectionToken == nil else {
            failLocally(
                "A prior authenticated generation has not been terminally retired. Relaunch Capture before starting another attempt.",
                "active_generation_blocks_discovery_reset"
            )
            return
        }
'''
new = '''        guard currentConnectionToken == nil else {
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "A prior package-owned generation existed when OFF1 restart was requested. It was retired fail-closed; start the correlation series again from OFF1.",
                        kind: "active_generation_blocks_discovery_reset"
                    )
                }
            }
            return
        }
'''
if s.count(old) != 1:
    raise SystemExit(f"OFF1 active-generation branch: expected one match, found {s.count(old)}")
s = s.replace(old, new, 1)
path.write_text(s)
