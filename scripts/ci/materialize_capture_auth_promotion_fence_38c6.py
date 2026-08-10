from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"

OLD = """                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
"""

NEW = """                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()

                    // Both ledger actor hops above can interleave view/foreground/account retirement.
                    // Never resurrect presentation or watchdog authority after the exact attempt moved on.
                    guard currentConnectionToken == token else {
                        log(\"stale_auth_promotion_ignored\", [\"generation\": String(token.diagnosticGeneration)])
                        return
                    }
                    guard phase == .authenticating else {
                        log(\"retired_auth_promotion_phase_ignored\", [\"generation\": String(token.diagnosticGeneration)])
                        return
                    }
                    guard sdkAccountLoggedIn,
                          sdkDeviceMembershipVerified,
                          accountIdentityLeaseIsAuthorized else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: \"Tuya account/device source authority changed while authenticated-session promotion was suspended.\",
                            kind: \"sdk_source_authority_lost_after_auth_promotion\"
                        )
                        return
                    }

                    phase = .observing
"""


def authenticated_section(source: str) -> str:
    start = source.index("    private func authenticated(token: TuyaReadOnlyConnectionToken) async")
    end = source.index("    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async", start)
    return source[start:end]


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    section = authenticated_section(source)
    if section.count(OLD) != 1:
        raise SystemExit(f"auth promotion replacement target count changed: {section.count(OLD)}")
    section = section.replace(OLD, NEW, 1)
    start = source.index("    private func authenticated(token: TuyaReadOnlyConnectionToken) async")
    end = source.index("    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async", start)
    ENTRYPOINT.write_text(source[:start] + section + source[end:], encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    section = authenticated_section(source)
    mark = section.index("try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)")
    refresh = section.index("await refreshLedgerSnapshot()", mark)
    observing = section.index("phase = .observing", refresh)
    watchdog = section.index("startWatchdog(token: token)", observing)
    fence = section[refresh:observing]

    required = (
        "guard currentConnectionToken == token else",
        "guard phase == .authenticating else",
        "guard sdkAccountLoggedIn,",
        "sdkDeviceMembershipVerified,",
        "accountIdentityLeaseIsAuthorized else",
        "await invalidateSourceAuthority(",
        "sdk_source_authority_lost_after_auth_promotion",
    )
    for token in required:
        if token not in fence:
            raise SystemExit(f"post-await auth promotion fence missing: {token}")

    order = [fence.index(token) for token in (
        "guard currentConnectionToken == token else",
        "guard phase == .authenticating else",
        "guard sdkAccountLoggedIn,",
        "await invalidateSourceAuthority(",
    )]
    if order != sorted(order):
        raise SystemExit("post-await auth promotion fence order changed")
    if not (mark < refresh < observing < watchdog):
        raise SystemExit("auth promotion/watchdog ordering changed")

    # Do not accidentally gain protocol/control authority in this lifecycle repair.
    for forbidden in ("writeValue", "publishDps", "queryDps", "disconnectBLE", "endConnection("):
        if forbidden in fence:
            raise SystemExit(f"post-await fence gained forbidden transport/protocol authority: {forbidden}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
