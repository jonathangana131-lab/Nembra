# Ride History Duration Archive Attachment — V14

## Purpose

This layer persists completed-ride monotonic duration fields without allowing durable bytes to manufacture fresh runtime evidence authority.

`CompletedRideDurationEvidence` is the authoritative process/lifecycle-bound value. It is intentionally not Codable. `CompletedRideDurationEvidenceArchive` is the structurally validated Codable representation and is intentionally non-authoritative.

The history attachment preserves that split and separately preserves the exact immutable completed-ride subject used when authoritative duration was created.

## Commit direction

The only authoritative ingestion path is one-way:

`CompletedRideDurationEvidence -> persistenceArchive -> RideHistoryDurationRecord -> RideHistoryDurationStore`

Before commit, `RideHistoryDurationCommitCoordinator` requires the exact base `RideHistoryRecord` and validates the authoritative duration against the full immutable `CompletedRideEvidence` snapshot, not just session UUID and continuity. After commit it requires exact durable archive read-back.

No wall-clock subtraction participates in duration production or persistence.

## Exact completed-ride subject

Session UUID plus `RideSessionContinuity` is not enough to prove that two records describe the same completed ride snapshot. A conflicting history record can reuse both while differing in dates, odometer endpoints, GPS distance, or other immutable completed-ride fields.

Authoritative duration therefore retains the exact `CompletedRideEvidence` subject that produced it. Its one-way persistence archive carries that subject as provenance, and `RideHistoryDurationAttachment` requires exact equality with the independently loaded `RideHistoryRecord.evidence` before associating the two records.

Older or caller-authored archives may omit that exact subject and still decode as structurally valid, non-authoritative archival data. They cannot pass the exact-history attachment boundary merely because their UUID and continuity match.

## Read direction

A stored record reads back as `RideHistoryDurationRecord` containing only `CompletedRideDurationEvidenceArchive`.

`RideHistoryDurationAttachment` may associate that archive with the exact base completed ride only when the archive carries the same immutable completed-ride subject. This association is persisted-history truth only. It is not a restored `CompletedRideDurationEvidence` and cannot be passed to consumers that require authoritative duration evidence.

There is deliberately no archive-to-authority initializer or coordinator restore method in this layer.

## Why this boundary exists

A Codable authoritative duration type lets arbitrary decoded JSON select a real ride UUID/continuity and supply invented monotonic nanoseconds. Structural validation alone cannot prove those nanoseconds were observed by Nembra's accepted lifecycle owner.

Using a separate archive type means imported or caller-authored bytes can remain useful for history, diagnostics, migration, and future trusted restore work without automatically becoming production measurement authority. Exact completed-ride provenance prevents those bytes from being attached to a different immutable ride snapshot by UUID alone.

## Future trusted restore

If Nembra later needs persisted duration to regain authoritative status for Statistics or another product surface, that promotion must be designed at the actual trusted ride-store/restore boundary. It must not be added here as a convenience decoder or UUID-only bridge.

Until then:
- persisted archives are non-authoritative;
- exact history association additionally requires the immutable completed-ride subject;
- unbound legacy/imported archives remain archival data rather than silently attaching to a ride;
- history can display/archive them only with truthful provenance language;
- Statistics or other authoritative consumers must not accept them as observed duration evidence.

## Truth boundary

SOFTWARE HISTORY/PERSISTENCE ONLY.

This layer establishes no AOVOPRO ES80 timing semantics, BLE cadence, physical background-execution guarantee, wall-clock accuracy, or physical-device result. Unknown duration remains unavailable; observed zero remains distinct from unavailable; recovered rides cannot claim complete process-local coverage.
