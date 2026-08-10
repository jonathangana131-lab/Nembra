from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticationPromotionTransportTruthSourceTests.swift")

PATCH = '''                    guard let promotionDriver = self.driver else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Official Tuya driver authority disappeared while authentication promotion was suspended.",
                            kind: "sdk_driver_authority_lost_during_auth_promotion"
                        )
                        return
                    }
                    let promotionLocalBLEOnline = promotionDriver.isLocallyConnected(uuid: tuyaUUID)
                    sdkLocalBLEOnline = promotionLocalBLEOnline
                    guard promotionLocalBLEOnline else {
                        await recordObservedTransportLoss(token: token)
                        return
                    }

'''


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    anchor = '''                    phase = .observing
                    message = "Authenticated generation \\(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…"
'''
    if source.count(anchor) != 1:
        raise SystemExit(f"observing anchor count={source.count(anchor)}")
    if "guard let promotionDriver = self.driver else" in source:
        raise SystemExit("transport fence already present")
    APP.write_text(source.replace(anchor, PATCH + anchor, 1), encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    a = source.index("private func authenticated(token: TuyaReadOnlyConnectionToken) async")
    b = source.index("private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async", a)
    block = source[a:b]
    refresh = block.index("await refreshLedgerSnapshot()")
    source_fence = block.index("accountIdentityLeaseIsAuthorized else", refresh)
    current_driver = block.index("guard let promotionDriver = self.driver else", source_fence)
    driver_terminal = block.index("sdk_driver_authority_lost_during_auth_promotion", current_driver)
    live_read = block.index("promotionDriver.isLocallyConnected(uuid: tuyaUUID)", driver_terminal)
    mirror = block.index("sdkLocalBLEOnline = promotionLocalBLEOnline", live_read)
    offline = block.index("guard promotionLocalBLEOnline else", mirror)
    terminal = block.index("await recordObservedTransportLoss(token: token)", offline)
    observing = block.index("phase = .observing", terminal)
    watchdog = block.index("startWatchdog(token: token)", observing)
    if not (refresh < source_fence < current_driver < driver_terminal < live_read < mirror < offline < terminal < observing < watchdog):
        raise SystemExit("post-await live-transport ordering is invalid")
    if not TEST.exists():
        raise SystemExit("transport regression missing")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "apply": apply()
    elif mode == "verify": verify()
    else: raise SystemExit(mode)
