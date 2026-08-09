# Capture Xcode 27 runner runtime truth — V14

Date: 2026-08-09
Protocol: V14
Feature: Nembra Capture / ES80 physical truth
Physical status: NO-GO / DO NOT RUN EXPERIMENT ONE

## Current runtime authority

The live GitHub Actions runner selected by `runs-on: xcode-27` is currently GitHub-hosted, not a persistent self-hosted Mac.

Validation-only PR #1705 ran a one-step diagnostic on the `xcode-27` class without checking out or executing repository code first. Exact run `31310460185`, job `93237385081`, completed successfully and reported:

- `RUNNER_ENVIRONMENT=github-hosted`;
- Runner Image Provisioner: `Hosted Compute Agent`;
- runner image: `xcode-27-arm64`;
- macOS 26.5.2;
- runner group/name metadata in the GitHub-hosted Actions class.

The diagnostic was fail-closed: it succeeded only for `github-hosted`, exited with a dedicated failure for `self-hosted`, and rejected unknown values. The validation branch was closed unmerged after collecting the runtime evidence.

## Consequence for Capture trust review

Older repository prose that describes `xcode-27` as a persistent self-hosted runner is stale with respect to the current runtime environment. It must not be used by itself to claim that a process can survive from one Actions job into the next on the same persistent host.

This specifically disproved validation-only PR #1700's persistent-self-hosted prevalidation premise for the current runner class. The separate-job boundary introduced by merged Capture trust hardening therefore receives the GitHub-hosted fresh-job VM contract at the currently observed runtime subject.

This does **not** prove every other trust boundary. In particular, candidate-controlled code that executes *inside the same authority-producing Xcode job* remains a distinct custody problem. Scheme actions, Xcode build hooks, custom tool settings, test-harness mutation, retained provenance, exact-head binding, and Final GO authority must each remain mechanically fenced and independently accepted.

## Infrastructure drift rule

Runner class is an external runtime property, not a permanent source-code fact. Any future authority decision that materially depends on job isolation must use fresh runtime evidence or an explicit fail-closed workflow assertion. If `RUNNER_ENVIRONMENT` ever reports `self-hosted` or an unknown value, the current fresh-host assumption is invalid and the trusted Capture authority chain must stop until custody is re-established.

## Relationship to historical scheduler documentation

`docs/CI_EXACT_HEAD_SCHEDULER.md` contains older scheduler-era references to a "self-hosted runner." Preserve those statements only as historical context for the infrastructure that document originally described; they are not current runtime authority for V14's live `xcode-27` runner.

When that scheduler document is next edited for product use, its current-runtime wording should point here instead of asserting a persistent self-hosted host.

## Truth boundary

This record establishes only the observed GitHub Actions runner environment for the exact diagnostic above. It does not establish physical AOVOPRO ES80 identity, Bluetooth/GATT/Tuya semantics, telemetry meaning, signed-field installation, intended-device membership, or Final GO.

Simulator or runner-environment evidence is software/infrastructure evidence only.

**FIRST REAL ES80 CAPTURE / EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
