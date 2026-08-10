# Nembra Capture V14 — Final Composed Software Acceptance Subject

Status: **SOFTWARE ACCEPTANCE CANDIDATE / PHYSICAL NO-GO**

Flagship parent at cut: `integration/v14-capture-final-stationary-convergence-sol@d30b1521fb67aa4eecc49d8f134c2a69739fbd91`

This branch exists only to give the already-composed Capture product a durable exact-head Xcode 27 acceptance subject. This document adds no Bluetooth, Tuya, evidence, telemetry, command, or UI behavior.

## Required exact-head acceptance

The unchanged acceptance head must receive terminal success from `Xcode 27 Simulator QA`, including pristine input/project checks, NembraCore and NembraBluetoothCapture package tests, real app/unit/UI iOS 27 Simulator execution, retained exact build evidence, attestations, screenshots, and logs.

Queued, skipped, cancelled, failed, ancestor, donor, package-only, resolver-only, or construction-workflow results are non-evidence.

## Promotion rule

If this exact head is terminal green and the flagship has not advanced, the flagship may fast-forward to this exact SHA. If the flagship advances first, this run becomes ancestor evidence only and must not authorize the later composition.

This software gate does not authorize a scooter experiment. Private intended-device provisioning/signing/runtime authority remains separate, and the first physical authenticated session remains stationary and read-only.

**PHYSICAL STATUS: NO-GO / DO NOT SCAN / DO NOT RUN.**
