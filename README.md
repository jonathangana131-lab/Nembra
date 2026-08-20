# Nembra

Nembra is a native iPhone scooter platform focused first on a deeply supported **AOVOPRO ES80** experience. It is intentionally not a Tuya skin and not a generic VESC tuner.

The repository is built around capability-based vehicle state, a production simulation backend, conservative Bluetooth protocol integration, crash-safe ride architecture, a premium portrait product shell, and a dedicated landscape Drive/cockpit experience.

## Current target

The active target is a coherent, production-quality **Nembra 1.0**. Development uses current `main` as the integration trunk and root [`AGENTS.md`](AGENTS.md) as the execution authority.

Broad `Go` / `continue` / `finish Nembra` prompts mean autonomous real GitHub development for the available turn. Nembra must not globally stall because Codex usage is exhausted, one chat lacks Xcode, or hosted CI is unavailable. Ordinary source-complete development follows the development-main fast path in `AGENTS.md`; final release, physical BLE/Tuya truth, signing/key custody, device evidence, and visual/accessibility/performance acceptance remain strict.

See [`PROJECT_STATE.md`](PROJECT_STATE.md) and [`docs/AUTONOMY_STATUS.md`](docs/AUTONOMY_STATUS.md) for the current integration and milestone state, then refresh live GitHub before acting.

## Nembra Capture

Nembra Capture is a read-only-first evidence utility used to establish real ES80 Bluetooth truth without guessing protocol semantics. It is not a second flagship product and it does not authorize scooter writes merely because capture code exists.

`CAPTURE_USER_INPUT_READY` in `docs/AUTONOMY_STATUS.md` stays false until the software-side stationary read-only capture carrier/procedure is accepted and the next real blocker is specifically a fresh user-owned iPhone/scooter/account session.

## Safety / truthfulness rule

Nembra never exposes unverified motor commands as real controls. ES80/Tuya write behavior must be proven before a real Bluetooth implementation can send it. Physical telemetry names, units, scales, signedness, cadence, identity, and provenance remain unknown until repeatable physical evidence verifies them.

Simulator/research values are not physical scooter truth. Never commit private keys, credentials, account/device identifiers, raw sensitive capture data, or private signed artifacts.

## Local validation

Core package validation is available with:

```bash
cd Packages/NembraCore
swift test
```

The full iOS app targets Xcode 27 + iOS 27. Trusted exact-source Xcode/iPhone evidence may come from any capable environment that actually runs the candidate (local/Codex Mac, owner Mac, or hosted macOS runner); GitHub Actions is useful supplemental execution, not privileged ordinary-development authority.

Deterministic Simulator scenarios are documented in `docs/SIMULATION.md`. Existing Xcode 27 hosted workflows remain useful when available; see `docs/GITHUB_XCODE27_CI.md`.
