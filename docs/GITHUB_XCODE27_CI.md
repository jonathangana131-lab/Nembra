# GitHub Xcode 27 Simulator QA

Nembra includes a GitHub Actions workflow at `.github/workflows/xcode27-simulator.yml` that targets GitHub's `xcode-27` preview runner.

## Why this exists

The primary ChatGPT execution host may not be macOS. This workflow provides a repeatable Apple-hosted build/Simulator gate instead of pretending a Linux syntax check is an iOS build.

The workflow:

1. runs the platform-independent `NembraCore` test suite;
2. selects an installed iOS 27 Simulator runtime;
3. prefers the iPhone 12 device type as Nembra's baseline, with a documented fallback only if that device type is absent from the runner image;
4. runs the `Nembra` Xcode scheme's unit tests with code signing disabled for Simulator;
5. installs the actual built `Nembra.app`;
6. launches deterministic `NEMBRA_SIMULATION_SCENARIO` states;
7. verifies each launched Nembra process is still alive before capture;
8. captures real `xcrun simctl io ... screenshot` PNGs and checks that each file exists;
9. uploads screenshots, launch/system logs, Xcode test logs, Xcode version, runtime, and Simulator metadata as one workflow artifact.

## Captured Home states

- cold-disconnected
- reconnecting
- connected-stopped
- riding
- low-battery
- bluetooth-off
- permission-denied
- scooter-unavailable
- unsupported-configuration
- connected-stopped in dark appearance
- reconnecting in dark appearance

These are real app screenshots once the workflow runs. They are not generated mockups.

## Product truthfulness

The workflow never enables simulation for an ordinary production launch. Simulation is explicitly injected into the child Simulator process only for deterministic QA. The default app bootstrap remains hardware-gated through `UnverifiedScooterService` until the real MAXSHOT protocol identity is verified.

## Current GitHub runner fact

GitHub announced the `xcode-27` runner image as a public preview on July 16, 2026 (official changelog: https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview/). That image uses Xcode 27 beta and includes the iOS 27 SDK/runtime. Because it is preview infrastructure, workflow logs and environment metadata are retained with screenshots so image changes are visible during QA.


## Validation status

This workflow is **prepared but not yet executed** because the current harness cannot create the intended private GitHub repository or push this checkout. Until an actual `xcode-27` run succeeds, PROJECT_STATE must continue to say that iOS/Xcode/Simulator validation is pending.
