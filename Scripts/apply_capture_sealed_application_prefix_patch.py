from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact anchor, found {count}")
    source = source.replace(old, new, 1)


replace_once(
    "    private var events: [Event] = []\n",
    "    private var events: [Event] = []\n    private var sealedAcceptedEventPrefix: [Event]?\n",
    "sealed prefix storage",
)

replace_once(
    """                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.currentConnectionToken = nil\n                        await self.refreshLedgerSnapshot()\n""",
    """                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        // The package mutation above seals the authoritative generation. Freeze the\n                        // app-exportable event prefix synchronously before any later suspension can\n                        // admit queued stale-callback diagnostics into the live event log.\n                        self.sealedAcceptedEventPrefix = self.events\n                        self.exportData = nil\n                        self.currentConnectionToken = nil\n                        await self.refreshLedgerSnapshot()\n""",
    "synchronous accepted-prefix freeze",
)

replace_once(
    "            events: events\n",
    "            events: sealedAcceptedEventPrefix ?? events\n",
    "accepted export event source",
)

replace_once(
    """        exportData = nil\n        // Active authenticated generations must be terminally retired by their\n""",
    """        exportData = nil\n        sealedAcceptedEventPrefix = nil\n        // Active authenticated generations must be terminally retired by their\n""",
    "fresh-life prefix reset",
)

required = [
    "private var sealedAcceptedEventPrefix: [Event]?",
    "self.sealedAcceptedEventPrefix = self.events",
    "events: sealedAcceptedEventPrefix ?? events",
    "sealedAcceptedEventPrefix = nil",
]
for needle in required:
    if needle not in source:
        raise SystemExit(f"missing post-patch invariant: {needle}")

seal_start = source.index("try await sessionLedger.sealAcceptedObservation(for: token)")
seal_end = source.index("} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed", seal_start)
seal = source[seal_start:seal_end]
freeze = seal.index("sealedAcceptedEventPrefix = self.events")
next_await = seal.find("await ", len("try await sessionLedger.sealAcceptedObservation(for: token)"))
if next_await >= 0 and freeze > next_await:
    raise SystemExit("accepted prefix is not frozen before the next suspension point")

path.write_text(source)
