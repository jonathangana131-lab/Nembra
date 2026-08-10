from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()
old = '''        guard currentConnectionToken == nil else {
            pendingCorrelatedTargetID = nil
            failLocally("An authenticated generation already owns session authority. Relaunch Capture before confirming another target.", "active_generation_blocks_target_confirmation")
            return
        }
'''
new = '''        guard currentConnectionToken == nil else {
            pendingCorrelatedTargetID = nil
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "An impossible active session generation existed during target confirmation. It was retired fail-closed; restart from OFF1.",
                        kind: "active_generation_blocks_target_confirmation"
                    )
                }
            }
            return
        }
'''
if s.count(old) != 1:
    raise SystemExit(f"confirmation generation fence: expected one match, found {s.count(old)}")
path.write_text(s.replace(old, new, 1))
