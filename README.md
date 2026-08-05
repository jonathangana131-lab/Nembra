# Nembra

Nembra is a native iPhone scooter platform focused first on a deeply supported **MAXSHOT V1S Pro** experience. It is intentionally not a Tuya skin and not a generic VESC tuner.

The repository is built around capability-based vehicle state, a production simulation backend, conservative Bluetooth protocol integration, crash-safe ride architecture, and a dedicated landscape cockpit.

## Current milestone

Milestone 1: product identity, verified research ledger, production domain model, simulator service, and the first portrait Home vertical slice.

See [`PROJECT_STATE.md`](PROJECT_STATE.md) before changing anything.

## Safety / truthfulness rule

Nembra never exposes unverified motor commands as real controls. MAXSHOT/Tuya write behavior must be proven before a real Bluetooth implementation can send it. The initial real-BLE layer is observation-first.

## Local validation available in this environment

```bash
cd Packages/NembraCore
swift test
```

The full iOS app requires Xcode 27 + the iOS 27 SDK on macOS. This repository was initially authored in a Linux ChatGPT execution environment, so the `.xcodeproj` is generated but cannot be honestly claimed as Xcode-built until the macOS continuation step is run.


## Simulator QA
Deterministic Home-state launch scenarios are documented in `docs/SIMULATION.md`. They exist for reproducible Simulator screenshots/UI tests without adding fake developer controls to the normal product interface.
## Xcode 27 Simulator QA

Nembra includes `.github/workflows/xcode27-simulator.yml`, which runs the real Xcode target on GitHub's `xcode-27` macOS runner, boots an iOS 27 Simulator, and uploads deterministic Home screenshots and Xcode logs. See `docs/GITHUB_XCODE27_CI.md`.
