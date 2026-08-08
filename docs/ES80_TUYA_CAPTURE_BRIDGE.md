# ES80 Passive Capture -> Tuya Candidate Bridge

Status: **SOFTWARE RESEARCH TOOLING ONLY — NOT PHYSICAL ES80 PROTOCOL VERIFICATION**

No physical AOVOPRO ES80 Tuya framing, DP, telemetry field, scaling, signedness, cadence, encryption key, command, or acknowledgement is verified by this bridge.

## Purpose

Nembra keeps two research layers deliberately separate:

1. passive CoreBluetooth capture that preserves raw GATT/value evidence, exact capture order, target identity, and explicit continuity evidence; and
2. the bounded offline analyzer for a corroborated public Tuya BLE framing family.

`PassiveBluetoothTuyaCandidateBridge` closes only the mechanical gap between those layers. It projects one explicitly selected peripheral from an immutable capture into deterministic GATT + value-origin candidate transcripts without asking the operator to copy hex, choose a promising characteristic, renumber callbacks, invent clocks, or reconstruct provenance manually.

A structurally completed framing candidate remains only a public-family hypothesis. It does not become physical ES80 truth.

## Explicit target presence

The bridge requires one nonblank exact peripheral identifier and verifies that identifier exists in **target-attributable immutable evidence** before projection.

Target-attributable presence includes exact-peripheral:

- connection evidence;
- service discovery;
- included-service discovery;
- characteristic discovery;
- descriptor discovery;
- subscription evidence; or
- raw value evidence.

Advertisement-only evidence is deliberately excluded. A broad-scan advertisement can place a peripheral in a candidate catalog, but it does not prove that Nembra selected/acquired that target for this capture-analysis authority.

This keeps two cases distinct:

- **requested target absent/stale** -> projection error;
- **requested target observed but no eligible raw value streams** -> valid empty transcript set.

The bridge never turns “unknown target” into an ordinary-looking zero-evidence result.

## Exact receipt chronology

Each immutable passive-capture record already carries:

- `sequenceNumber`: strict order inside one capture session;
- `receivedAtUptimeNanoseconds`: boot-relative monotonic receipt-clock metadata; and
- `receivedAtDate`: wall-clock correlation metadata.

The bridge maps those facts mechanically into the candidate analyzer:

- original `record.sequenceNumber` -> `receiptSequenceNumber`;
- exact `session.id.uuidString` -> `receiptSequenceScope`;
- original `receivedAtUptimeNanoseconds` -> analyzer uptime metadata;
- original `receivedAtDate` remains source/correlation metadata only.

The bridge does **not** renumber after filtering by target, characteristic, or value origin. If a selected stream contains source sequences `[1, 5]`, the analyzer receives `[1, 5]`.

The capture-session UUID is the sequence scope because that immutable session owns the sequence counter. Peripheral ID, model name, display name, GATT UUID, filename, or wall-clock time are never substituted as authority.

Sequence must increase strictly, uptime must not move backward, and scope must remain exact. Wall-clock `Date` never repairs or overrides callback order.

These are software-provenance facts. They do not authenticate the physical scooter or prove radio-level independence.

## Stream identity and provenance

For the requested target the bridge:

- consumes immutable records in original capture order;
- includes only raw `.value` observations from that exact peripheral;
- preserves exact service and characteristic strings;
- separates every `PassiveBluetoothValueOrigin`, so read responses are never silently spliced with notification/indication/subscription updates;
- preserves session ID, `VehicleIdentity`, session start date, and selected peripheral on every detached transcript;
- preserves exact capture record index, global sequence number, uptime, wall-clock date, and candidate bytes on each source fragment;
- keeps independent stream order deterministic by first observation in the capture.

Public provenance/output structs are read-only views with module-internal construction. External callers may inspect producer-issued evidence but cannot mint a bridge report by arbitrarily pairing analyzer outcomes with unrelated capture provenance.

This is a compile-time software evidence boundary, not cryptographic attestation.

## Target-scoped continuity

`PassiveBluetoothCaptureEvent.breaksByteContinuity` is intentionally a **capture-level** fact: every structured disconnect and every global interruption marks a raw gap somewhere in the capture. The bridge has a narrower job because it projects one explicitly selected peripheral.

For a selected target transcript, continuity generation advances only when:

- a structured `.connection(.disconnected)` belongs to that exact selected peripheral; or
- a global `.interruption` occurs.

A disconnect for another peripheral remains real evidence for that other peripheral, but it must **not** manufacture a discontinuity in the selected target stream. After target filtering, bytes from `target-A` do not become separated merely because `noise-B` disconnected between their callbacks.

This distinction is permanent and adversarially tested:

- unrelated peripheral disconnect -> selected-target continuity stays unchanged;
- selected-target disconnect -> continuity advances;
- global interruption -> continuity advances.

Interleaved callbacks that are neither selected-target disconnects nor global interruptions remain filterable by target/GATT/origin without inventing byte gaps.

An empty selected-target raw value cannot be represented truthfully by the candidate observation type, so projection fails with exact record/sequence/GATT/origin provenance rather than silently dropping it. Continuity-generation overflow also fails closed rather than wrapping.

The bridge does not infer hidden packet loss, device reboot semantics, reconnect success, subscription continuity, or bytes that were never observed.

## Analyzer output

`PassiveBluetoothTuyaCandidateBridge.analyze(...)` runs the bounded `TuyaCandidateTranscriptAnalyzer` independently for every exact GATT + origin transcript.

Analyzer observation indices are stream-local, while every source fragment retains its original global capture record index and sequence. A caller can therefore map completed, rejected, restarted, boundary-truncated, and end-truncated candidate outcomes back to immutable source evidence.

`completed` means only that captured bytes satisfy the selected bounded public-family framing hypothesis. It does **not** mean:

- the physical ES80 is verified to use that Tuya family;
- ciphertext is authenticated or decrypted;
- a logical packet is physically verified;
- any DP is battery, voltage, current, power, speed, mode, lock, light, throttle, regen, trip, or odometer;
- any command is authorized or acknowledged.

A rejection remains useful falsifying evidence. The bridge does not shift offsets, delete bytes, rewrite timing, merge origins, or retry alternate interpretations until one succeeds.

## Acceptance requirements

Before this bridge can be treated as accepted research infrastructure on the flagship composition:

1. focused `NembraCore` / `NembraBluetoothCapture` tests must pass with the target-scoped continuity regressions;
2. the package-wide no-application-`writeValue(...)` safety boundary must remain intact;
3. exact scoped receipt chronology, target-presence rules, GATT/origin separation, empty-payload failure, and source-fragment provenance must remain unchanged;
4. the final composed Capture head must earn the required exact-head Xcode 27 package/app/UI/provenance gate;
5. retained runtime artifacts/screenshots must be inspected separately from test green;
6. physical Experiment One remains blocked until the final signed-device authority/runbook GO gate is independently satisfied.

Queued, running, skipped, cancelled, stale, ancestor, resolver-only, or dependency-obsolete checks are not acceptance.

## Intended physical workflow

Only after the full Capture product and physical authorization ladder closes should the first physical experiment proceed:

1. identify/correlate the real scooter through the accepted OFF / ON workflow while stationary;
2. perform the accepted passive acquisition with no characteristic-value writes;
3. retain the exact immutable capture artifact and required provenance;
4. let Nembra tooling project exact selected-target value streams automatically;
5. compare repeated structural/correlation evidence without manual hex editing;
6. promote a field only after repeatable physical evidence establishes source, framing, DP identity/type, scale, signedness, units, cadence, continuity, and provenance.

Until that ladder closes, **Experiment One remains DO NOT RUN / NO-GO**.

## Safety boundary

This bridge adds no `writeValue`, command path, encryption/decryption key handling, device authentication, production `ScooterService`, Dashboard telemetry wiring, or vehicle-control acknowledgement.

Its role is narrow: move trustworthy raw passive-capture evidence into reproducible bounded offline analysis while preserving selected-target identity, capture identity, exact scoped receipt chronology, GATT/value-origin provenance, and target-scoped continuity without inventing physical ES80 semantics.
