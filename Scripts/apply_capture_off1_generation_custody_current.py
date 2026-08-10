from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()

old = '''        guard currentConnectionToken == nil else {
            failLocally(
                "A prior authenticated generation has not been terminally retired. Relaunch Capture before starting another attempt.",
                "active_generation_blocks_discovery_reset"
            )
            return
        }'''
new = '''        guard currentConnectionToken == nil else {
            let token = currentConnectionToken!
            Task { @MainActor in
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "A prior authenticated generation unexpectedly still owned session authority when OFF1 was requested. It was terminally retired; restart from OFF1.",
                    kind: "active_generation_blocks_discovery_reset"
                )
            }
            return
        }'''

count = s.count(old)
if count != 1:
    raise SystemExit(f"OFF1 custody anchor expected once, got {count}")
s = s.replace(old, new, 1)
path.write_text(s)
