from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
app = app_path.read_text()

if "func consumeCorrelationAsyncInvalidation()" in app:
    raise SystemExit("consumer already present; refusing duplicate edit")

lifecycle_marker = "\n    private func startCurrentCorrelationWindow() {"
if app.count(lifecycle_marker) != 1:
    raise SystemExit(f"lifecycle insertion marker count was {app.count(lifecycle_marker)}")

consumer = r'''

    func consumeCorrelationAsyncInvalidation() {
        guard (phase == .baseline || phase == .scanning),
              correlationProgress?.isSeriesInvalidated == true else { return }

        let invalidatedWindow = correlationWindowLabel
        // The package has already terminally invalidated and retired this observation-series
        // authority. Releasing only the app reference creates no receipt, candidate authority,
        // timestamp, BLE fact, or physical claim. A new attempt must restart from OFF1.
        correlationSession = nil
        failLocally(
            "\(invalidatedWindow) Bluetooth correlation was invalidated by the package before it could be sealed. Restart from OFF1 and repeat the complete OFF1→ON1→OFF2→ON2 series.",
            "target_correlation_async_invalidated"
        )
    }
'''
app = app.replace(lifecycle_marker, consumer + lifecycle_marker, 1)

view_start = app.find("private struct SecureLinkView")
if view_start < 0:
    raise SystemExit("SecureLinkView boundary missing")
view_tail = app[view_start:]
view_old = '            .background(Color.black.ignoresSafeArea())\n        }\n        .navigationTitle("Secure Link")'
if view_tail.count(view_old) != 1:
    raise SystemExit(f"SecureLinkView hook marker count was {view_tail.count(view_old)}")
view_new = '            .background(Color.black.ignoresSafeArea())\n            .onChange(of: test.correlationProgress?.isSeriesInvalidated) { _, invalidated in\n                if invalidated == true { test.consumeCorrelationAsyncInvalidation() }\n            }\n        }\n        .navigationTitle("Secure Link")'
view_tail = view_tail.replace(view_old, view_new, 1)
app = app[:view_start] + view_tail

required = [
    "func consumeCorrelationAsyncInvalidation()",
    "correlationProgress?.isSeriesInvalidated == true",
    '"target_correlation_async_invalidated"',
    "Restart from OFF1",
    ".onChange(of: test.correlationProgress?.isSeriesInvalidated)",
    "test.consumeCorrelationAsyncInvalidation()",
]
for token in required:
    if token not in app:
        raise SystemExit(f"missing repaired contract token: {token}")

consumer_start = app.index("func consumeCorrelationAsyncInvalidation()")
consumer_end = app.index("\n    private func startCurrentCorrelationWindow()", consumer_start)
consumer_text = app[consumer_start:consumer_end]
for forbidden in [
    "selectedID =",
    "pendingCorrelatedTargetID =",
    "targetCorrelationOperatorConfirmed = true",
    "beginOfficialConnection",
]:
    if forbidden in consumer_text:
        raise SystemExit(f"consumer unexpectedly promotes/changes authority: {forbidden}")

view_start = app.index("private struct SecureLinkView")
view_end = app.index("private struct SecureTransfer", view_start)
view_text = app[view_start:view_end]
for forbidden in ["milliseconds(100)", "correlationProgressTask"]:
    if forbidden in view_text:
        raise SystemExit(f"view contains forbidden second-clock token: {forbidden}")

app_path.write_text(app)
