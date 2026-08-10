from pathlib import Path

source_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = source_path.read_text()

old = '''                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
'''
new = '''                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()

                    // Both package mutation and snapshot refresh suspend this MainActor task. A
                    // foreground/view/account teardown can therefore retire the generation while
                    // this success callback is suspended. Never resurrect app-visible observing
                    // state or a watchdog after another lifecycle path already owns retirement.
                    guard currentConnectionToken == token else {
                        log("stale_auth_promotion_after_ledger_ignored", ["generation": String(token.diagnosticGeneration)])
                        return
                    }
                    guard phase == .authenticating else {
                        log("retired_auth_promotion_phase_ignored", ["generation": String(token.diagnosticGeneration)])
                        return
                    }
                    guard sdkAccountLoggedIn,
                          sdkDeviceMembershipVerified,
                          accountIdentityLeaseIsAuthorized else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Tuya account/device source authority changed while authenticated promotion was suspended.",
                            kind: "sdk_source_authority_lost_during_auth_promotion"
                        )
                        return
                    }

                    phase = .observing
'''
if source.count(old) != 1:
    raise SystemExit(f"authentication promotion seam drifted: {source.count(old)}")
source = source.replace(old, new, 1)
source_path.write_text(source)

receiver = source.split("    private func authenticated(token: TuyaReadOnlyConnectionToken) async", 1)[1].split(
    "    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async", 1
)[0]
promotion = receiver.index("try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)")
refresh = receiver.index("await refreshLedgerSnapshot()", promotion)
observing = receiver.index("phase = .observing", refresh)
fence = receiver[refresh:observing]
for token in ["currentConnectionToken == token", "phase == .authenticating", "accountIdentityLeaseIsAuthorized"]:
    if token not in fence:
        raise SystemExit(f"post-await fence missing {token}")
if "sdk_source_authority_lost_during_auth_promotion" not in fence:
    raise SystemExit("source-authority terminal missing from post-await fence")
if receiver.index("startWatchdog(token: token)", observing) <= observing:
    raise SystemExit("watchdog ordering drifted")
