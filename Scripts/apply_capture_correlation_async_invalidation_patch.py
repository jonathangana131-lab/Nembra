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
'''    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }

    var correlationWindowLabel: String {
''',
'''    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }
    var correlationSeriesIsInvalidated: Bool { correlationProgress?.isSeriesInvalidated == true }

    var correlationWindowLabel: String {
''',
"correlation terminal projection",
)

replace_once(
'''    private var accountIdentityLeaseSnapshot: TuyaSDKAccountIdentityLeaseGate.Snapshot {
''',
'''    /// Consumes an asynchronous terminal already committed by the package-owned correlation
    /// session (for example scan-readiness timeout or Bluetooth/scan loss). TimelineView supplies
    /// the existing bounded presentation clock; this method adds no second polling task and mints
    /// no Bluetooth, authentication, telemetry, or target-identity evidence.
    func consumeCorrelationAsyncInvalidationIfNeeded() {
        guard correlationSeriesIsInvalidated,
              phase == .baseline || phase == .scanning || phase == .powerOn else { return }

        let invalidatedWindow = correlationWindowLabel
        let completedWindows = correlationCompletedWindowCount
        correlationSession = nil
        correlationProvenance = nil
        targetCorrelationMethod = nil
        targetCorrelationWindowCount = nil
        targetCorrelationOperatorConfirmed = false
        pendingCorrelatedTargetID = nil
        selectedID = nil
        byID.removeAll()
        candidates.removeAll()
        phase = .failed
        message = "Bluetooth correlation ended before this window could be sealed. Restart the complete OFF1→ON1→OFF2→ON2 series; prior windows are not reusable."
        log("target_correlation_async_invalidated", [
            "window": invalidatedWindow,
            "completedWindows": String(completedWindows),
            "authority": "package-owned-series-terminal"
        ])
    }

    private var accountIdentityLeaseSnapshot: TuyaSDKAccountIdentityLeaseGate.Snapshot {
''',
"asynchronous correlation terminal consumer",
)

replace_once(
'''            .background(Color.black.ignoresSafeArea())
        }
        .navigationTitle("Secure Link")
''',
'''            .background(Color.black.ignoresSafeArea())
            .onChange(of: test.correlationSeriesIsInvalidated, initial: true) { _, invalidated in
                if invalidated {
                    test.consumeCorrelationAsyncInvalidationIfNeeded()
                }
            }
        }
        .navigationTitle("Secure Link")
''',
"existing TimelineView lifecycle consumer",
)

required = [
    "var correlationSeriesIsInvalidated: Bool { correlationProgress?.isSeriesInvalidated == true }",
    "func consumeCorrelationAsyncInvalidationIfNeeded()",
    'log("target_correlation_async_invalidated"',
    ".onChange(of: test.correlationSeriesIsInvalidated, initial: true)",
    "test.consumeCorrelationAsyncInvalidationIfNeeded()",
    "TimelineView(.periodic(from: .now, by: 0.5))",
]
for needle in required:
    if needle not in source:
        raise SystemExit(f"missing post-patch invariant: {needle}")

start = source.index("func consumeCorrelationAsyncInvalidationIfNeeded()")
end = source.index("private var accountIdentityLeaseSnapshot", start)
consumer = source[start:end]
for forbidden in [
    "markAuthenticated(for:",
    "recordApplicationUpdate",
    "endConnection(for:",
    "scanForPeripherals",
    "connect(",
    "Task.sleep",
]:
    if forbidden in consumer:
        raise SystemExit(f"terminal consumer manufactured unrelated authority: {forbidden}")

view_start = source.index("private struct SecureLinkView")
view_end = source.index("#Preview", view_start)
view = source[view_start:view_end]
for forbidden in ["correlationProgressTask", "Task.sleep(for: .milliseconds(100))"]:
    if forbidden in view:
        raise SystemExit(f"duplicate correlation polling clock introduced: {forbidden}")

path.write_text(source)
