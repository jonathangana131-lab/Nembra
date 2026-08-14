#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one target, found {count}: {old[:180]!r}")
    target.write_text(text.replace(old, new, 1))


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
                        // Own the app acceptance cut on this same MainActor callback turn before
                        // exact-token package retirement is scheduled. A ready watchdog continuation
                        // can therefore no longer seal while source authority is merely queued to retire.
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
source = source.replace(
    'driverBody.contains("private var onSourceAuthorityFailure: (() -> Void)?")',
    'driverBody.contains("private var onSourceAuthorityFailure: (@MainActor () -> Void)?")',
)
needle = '''        #expect(connectCall.contains("sourceAuthorityFailure:"))
        #expect(connectCall.contains("invalidateSourceAuthority("))'''
replacement = '''        #expect(connectCall.contains("sourceAuthorityFailure:"))
        let synchronousCut = try applicationSourceAttributionRequiredRange(
            "acceptanceCutIsClosed = true",
            in: connectCall
        )
        let watchdogCancel = try applicationSourceAttributionRequiredRange(
            "watchdog?.cancel()",
            in: connectCall
        )
        let failedPhase = try applicationSourceAttributionRequiredRange(
            "phase = .failed",
            in: connectCall
        )
        let retirementTask = try applicationSourceAttributionRequiredRange(
            "Task { @MainActor [weak self] in",
            in: connectCall
        )
        let retirement = try applicationSourceAttributionRequiredRange(
            "invalidateSourceAuthority(",
            in: connectCall
        )
        #expect(synchronousCut.lowerBound < watchdogCancel.lowerBound)
        #expect(watchdogCancel.lowerBound < failedPhase.lowerBound)
        #expect(failedPhase.lowerBound < retirementTask.lowerBound)
        #expect(retirementTask.lowerBound < retirement.lowerBound)'''
if source.count(needle) != 1:
    raise SystemExit("source-attribution connect oracle drifted")
source_test.write_text(source.replace(needle, replacement, 1))

# The driver itself must close forwarding before invoking the synchronous failure channel.
source = source_test.read_text()
needle2 = '''        #expect(failureFence.contains("onApplicationUpdate = nil"))
        #expect(failureFence.contains("onSourceAuthorityFailure?()"))'''
replacement2 = '''        let forwardingCut = try applicationSourceAttributionRequiredRange(
            "onApplicationUpdate = nil",
            in: failureFence
        )
        let failureCallback = try applicationSourceAttributionRequiredRange(
            "onSourceAuthorityFailure?()",
            in: failureFence
        )
        #expect(forwardingCut.lowerBound < failureCallback.lowerBound)'''
if source.count(needle2) != 1:
    raise SystemExit("source-attribution driver failure oracle drifted")
source_test.write_text(source.replace(needle2, replacement2, 1))

app_text = app.read_text()
assert app_text.count("sourceAuthorityFailure: @escaping @MainActor () -> Void") == 2
assert app_text.count("private var onSourceAuthorityFailure: (@MainActor () -> Void)?") == 1
assert "self.acceptanceCutIsClosed = true" in app_text
assert "self.watchdog?.cancel()" in app_text
assert "guard let callbackDeviceID = device?.deviceModel.devId" in app_text

Path(".github/workflows/capture-source-mismatch-sync-cut-materializer.yml").unlink()
Path(__file__).unlink()
