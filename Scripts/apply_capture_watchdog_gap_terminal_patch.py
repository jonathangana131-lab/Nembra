from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()
old = '''                let gap = now - previousPollUptime
                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.", "observation_poll_gap_exceeded")
                    return
                }
'''
new = '''                let gap = now - previousPollUptime
                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.",
                        kind: "observation_poll_gap_exceeded"
                    )
                    return
                }
'''
if s.count(old) != 1:
    raise SystemExit(f"watchdog gap: expected one match, found {s.count(old)}")
path.write_text(s.replace(old, new, 1))
