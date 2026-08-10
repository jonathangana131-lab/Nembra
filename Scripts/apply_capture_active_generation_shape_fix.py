from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, got {count}")
    s = s.replace(old, new, 1)


replace_once(
    '''        guard currentConnectionToken == nil else {
            failLocally(
                "A prior authenticated generation has not been terminally retired. Relaunch Capture before starting another attempt.",
                "active_generation_blocks_discovery_reset"
            )
            return
        }''',
    '''        guard currentConnectionToken == nil else {
            let token = currentConnectionToken!
            Task { @MainActor in
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "A prior authenticated generation unexpectedly still owned session authority when OFF1 was requested. It was terminally retired; restart from OFF1.",
                    kind: "active_generation_blocks_discovery_reset"
                )
            }
            return
        }''',
    "OFF1 active-generation terminal",
)

replace_once(
    '''            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "An authenticated generation unexpectedly still owned session authority at target confirmation. It was terminally retired; restart from OFF1.",
                    kind: "active_generation_blocks_target_confirmation"
                )
            }
            return''',
    '''            Task { @MainActor in
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "An authenticated generation unexpectedly still owned session authority at target confirmation. It was terminally retired; restart from OFF1.",
                    kind: "active_generation_blocks_target_confirmation"
                )
            }
            return''',
    "confirmation active-generation source contract",
)

path.write_text(s)
