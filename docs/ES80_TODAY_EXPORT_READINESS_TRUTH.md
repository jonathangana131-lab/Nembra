# ES80 TODAY Export Readiness Truth — V14

Status: **CONTROL-PLANE CLARIFICATION ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

Purpose: clarify the `storage/export readiness is healthy` wording in `docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md` without moving the frozen Capture application candidate or inventing a pre-scan filesystem authority that Nembra does not use.

Authority order remains:
1. `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`;
2. `docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md`;
3. this clarification.

## Current product mechanism

The accepted Capture product does not pre-stage the eventual Share artifact into an app-owned pathname before Bluetooth discovery.

After immutable seal, Nembra:
- asks the package coordinator for the finalized Share artifact for the current application/setup;
- independently inspects the returned JSON bytes with `PassiveBluetoothExperimentOneFinalShareIntegrity.inspect`;
- retains the exact verified `Data` in memory together with its filename and integrity report;
- exposes those same bytes through a `CoreTransferable.DataRepresentation` / `ShareLink` transfer;
- never reopens a mutable pathname after integrity verification.

The system may materialize those bytes for a user-selected Share destination later. Nembra does not control that external destination before the Share action is invoked.

## Pre-scan interpretation

For TODAY Experiment One, **do not** add or require a fake pre-scan disk-write/free-space probe and do not treat such a probe as proof that a later external Share destination will succeed.

Before the first Bluetooth scan, the legitimate gates are the ones Nembra can actually establish at that time: exact installed Research Field Build identity, package-owned research admission, Bluetooth availability/permission, foreground integrity, fresh charger-disconnected declaration, stationary setup, intended target availability, no application characteristic-write/command path, and explicit operator action.

The existing runbook phrase `storage/export readiness is healthy` must therefore be read narrowly as: **nothing in the accepted app/runtime state is already known to make the normal exact-byte Share path impossible.** It is not a separate filesystem certificate and it must not mint evidence about a future external Share destination.

## When export readiness is actually earned

Export readiness becomes authoritative only after the capture has been sealed and the exact finalized Share bytes exist.

The normal-path gate is:
1. immutable accepted-H artifact exists;
2. package finalized Share artifact is produced for the current application/setup;
3. final Share JSON passes `PassiveBluetoothExperimentOneFinalShareIntegrity.inspect`;
4. the exact verified bytes remain retained as the transfer authority;
5. the UI reports `CAPTURE COMPLETE — Ready for analysis` and exposes `SHARE CAPTURE`;
6. the resulting raw Share artifact is preserved unchanged and independently hashed/analyzed.

If final Share preparation/integrity fails, the sealed Capture remains legitimate but the attempt is **not export-ready**. The UI must surface the retry/failure state rather than relabeling the seal as failed or pretending analysis readiness.

A system Share destination can still fail later for reasons outside Nembra's pre-scan authority (for example, destination/provider availability). That is an operational Share failure, not evidence that a pre-scan filesystem probe should have authorized or rejected Bluetooth capture.

## TODAY blocker rule

Under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`, export work may move the frozen application head before the first physical artifact only when a demonstrated normal trusted-app path can make the generated Capture bytes wrong, incomplete, silently mutable, or impossible to export/analyze.

Absent such evidence, do not reset exact-head Xcode acceptance merely to add speculative storage checks.

This clarification changes no application bytes, package authority, recipe, signer, runbook GO state, Bluetooth behavior, or physical truth. **FIRST REAL ES80 CAPTURE REMAINS NO-GO / DO NOT RUN until every existing Final GO gate closes.**
