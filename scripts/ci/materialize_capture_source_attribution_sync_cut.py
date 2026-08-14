#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one target, found {count}: {old[:160]!r}")
    p.write_text(text.replace(old, new, 1))


app_path = "NembraApp/App/NembraCaptureEntrypoint.swift"
app = Path(app_path)
text = app.read_text()
if text.count("sourceAuthorityFailure: @escaping () -> Void") != 2:
    raise SystemExit("expected protocol + SmartLife sourceAuthorityFailure signatures")
text = text.replace(
    "sourceAuthorityFailure: @escaping () -> Void",
    "sourceAuthorityFailure: @escaping @MainActor () -> Void",
)
if text.count("private var onSourceAuthorityFailure: (() -> Void)?") != 1:
    raise SystemExit("expected SmartLife sourceAuthorityFailure storage")
text = text.replace(
    "private var onSourceAuthorityFailure: (() -> Void)?",
    "private var onSourceAuthorityFailure: (@MainActor () -> Void)?",
    1,
)
app.write_text(text)

replace_once(
    app_path,
    '''                    sourceAuthorityFailure: { [weak self] in
                        Task { @MainActor in
                            guard let self else { return }
                            await self.invalidateSourceAuthority(
                                token: token,
                                message: "SmartLife application callback source no longer matched the selected scooter. The generation was retired without admitting that payload.",
                                kind: "sdk_application_callback_source_mismatch"
                            )
                        }
                    },''',
    '''                    sourceAuthorityFailure: { [weak self] in
                        guard let self,
                              self.currentConnectionToken == token else { return }

                        // SmartLifeDriver has already latched application forwarding closed.
                        // Close acceptance on the same MainActor turn before package retirement is
                        // scheduled so a ready watchdog continuation cannot win the scheduler race.
                        self.acceptanceCutIsClosed = true
                        self.watchdog?.cancel()
                        self.watchdog = nil
                        self.phase = .failed
                        self.message = "SmartLife application callback source no longer matched the selected scooter. The exact session is being retired; relaunch Capture before another attempt."

                        Task { @MainActor [weak self] in
                            await self?.invalidateSourceAuthority(
                                token: token,
                                message: "SmartLife application callback source no longer matched the selected scooter. The generation was retired without admitting that payload or claiming Bluetooth disconnected.",
                                kind: "sdk_application_callback_source_mismatch"
                            )
                        }
                    },'''
)

source_test = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSmartLifeApplicationSourceAttributionSourceTests.swift")
source = source_test.read_text()
source = source.replace(
    'protocolBody.contains("sourceAuthorityFailure: @escaping () -> Void")',
    'protocolBody.contains("sourceAuthorityFailure: @escaping @MainActor () -> Void")',
)
needle = '#expect(connectCall.contains("sourceAuthorityFailure:"))\n        #expect(connectCall.contains("invalidateSourceAuthority("))'
replacement = '#expect(connectCall.contains("sourceAuthorityFailure:"))\n        #expect(connectCall.contains("acceptanceCutIsClosed = true"))\n        #expect(connectCall.contains("watchdog?.cancel()"))\n        #expect(connectCall.contains("phase = .failed"))\n        #expect(connectCall.contains("invalidateSourceAuthority("))'
if source.count(needle) != 1:
    raise SystemExit("source-attribution connect-call oracle drifted")
source_test.write_text(source.replace(needle, replacement, 1))

# Remove all donor-only transport files so final blobs are suitable for a clean one-commit carrier.
for transient in [
    ".github/workflows/capture-source-attribution-donor-materializer.yml",
    "scripts/ci/materialize_capture_source_attribution_donor.py",
    ".github/workflows/capture-source-attribution-sync-cut-materializer.yml",
    "scripts/ci/materialize_capture_source_attribution_sync_cut.py",
]:
    path = Path(transient)
    if path.exists():
        path.unlink()

app_text = app.read_text()
assert app_text.count("sourceAuthorityFailure: @escaping @MainActor () -> Void") == 2
assert "self.acceptanceCutIsClosed = true" in app_text
assert "self.watchdog?.cancel()" in app_text
assert "guard let callbackDeviceID = device?.deviceModel.devId" in app_text
assert "sessionLedger.captureApplicationReceipt(" in app_text
