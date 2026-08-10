from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()

marker = "\n    private func startCurrentCorrelationWindow() {"
if source.count(marker) != 1:
    raise SystemExit(f"expected one lifecycle insertion point, found {source.count(marker)}")

consumer = r'''

    func consumeCorrelationAsyncInvalidation() {
        guard (phase == .baseline || phase == .scanning),
              let session = correlationSession,
              session.progress?.isSeriesInvalidated == true else { return }

        let invalidatedWindow = correlationWindowLabel
        // The package has already terminally invalidated this observation-series authority.
        // Releasing the app reference and moving presentation to failed creates no new BLE
        // receipt, candidate authority, timestamp, transport fact, or physical claim.
        correlationSession = nil
        failLocally(
            "\(invalidatedWindow) correlation was invalidated before it could be sealed. Restart from OFF1 and repeat the complete OFF1→ON1→OFF2→ON2 series.",
            "target_correlation_async_invalidated"
        )
    }
'''
source = source.replace(marker, consumer + marker, 1)

view_old = '            .background(Color.black.ignoresSafeArea())\n        }\n        .navigationTitle("Secure Link")'
view_new = '            .background(Color.black.ignoresSafeArea())\n            .onChange(of: test.correlationProgress?.isSeriesInvalidated) { _, invalidated in\n                if invalidated == true { test.consumeCorrelationAsyncInvalidation() }\n            }\n        }\n        .navigationTitle("Secure Link")'
if source.count(view_old) != 1:
    raise SystemExit(f"expected one SecureLink TimelineView insertion point, found {source.count(view_old)}")
source = source.replace(view_old, view_new, 1)

required = [
    "func consumeCorrelationAsyncInvalidation()",
    "session.progress?.isSeriesInvalidated == true",
    '"target_correlation_async_invalidated"',
    "Restart from OFF1",
    ".onChange(of: test.correlationProgress?.isSeriesInvalidated)",
    "test.consumeCorrelationAsyncInvalidation()",
]
for token in required:
    if token not in source:
        raise SystemExit(f"missing required production contract token: {token}")

path.write_text(source)
