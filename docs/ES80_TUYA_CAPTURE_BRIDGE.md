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

The capture-session UUID is the sequence scope because that validated session owns the sequence counter. Peripheral ID, model name, display name, GATT UUID, filename, or wall-clock time are never substituted as authority.

Sequence must increase strictly, uptime must not move backward, and scope must remain exact. Wall-clock `Date` never repairs or overrides callback order.

These are software-provenance facts. `PassiveBluetoothCaptureSession` is publicly constructible, so valid session metadata is not recorder custody, hardware attestation, physical target authentication, or protocol truth.

## Stream identity and provenance

For the requested target the bridge:

- consumes immutable records in original capture order;
- includes only raw `.value` observations from that exact peripheral;
- preserves exact service and characteristic strings;
- separates every `PassiveBluetoothValueOrigin`, so read responses are never silently spliced with notification/indication/subscription updates;
- preserves session ID, `VehicleIdentity`, session start date, and selected peripheral on every detached transcript;
- preserves exact capture record index, global sequence number, uptime, wall-clock date, and candidate bytes on each source fragment;
- keeps independent stream order deterministic by first observation in the capture.

Public provenance/output structs are read-only views with module-internal construction. External callers cannot directly assemble mutually inconsistent bridge output structs, but they can construct a valid capture session and ask the bridge to derive those views. This is therefore a compile-time software-provenance boundary, not cryptographic attestation or proof of how the session was acquired.

## Continuity authority

`PassiveBluetoothCaptureEvent.breaksByteContinuity` is the authoritative capture-domain fact for whether raw value evidence on opposite sides of an observed event may remain in one byte-continuity segment. Today Core declares every structured disconnect and every global interruption to be such a break.

Candidate continuity starts at generation zero for one projection and advances whenever `record.event.breaksByteContinuity == true`. The bridge consumes that Core property directly instead of maintaining a narrower duplicated list.

Target attribution remains separate from continuity truth. A disconnect carrying another peripheral identifier is **not** relabeled as a physical ES80 or selected-target disconnect, but once NembraCore has issued that observed event as a raw-byte continuity break, downstream framing preserves the gap rather than making selected-target bytes on opposite sides eligible to splice.

This cross-layer contract is adversarially tested:

- unrelated peripheral structured disconnect -> candidate continuity advances because Core issued a capture-level raw-byte gap;
- selected-target structured disconnect -> continuity advances;
- global interruption -> continuity advances.

Interleaved callbacks that are not Core-declared continuity breaks remain filterable by target/GATT/origin without inventing fake byte gaps. Directly consuming the Core property also prevents a future addition to the authoritative break vocabulary from silently drifting from a narrower bridge-specific case list.

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

1. focused `NembraCore` / `NembraBluetoothCapture` tests must pass with the Core-authoritative continuity regressions;
2. the package-wide no-application-`writeValue(...)` safety boundary must remain intact;
3. exact scoped receipt chronology, target-presence rules, GATT/origin separation, empty-payload failure, source-fragment provenance, and every Core-declared continuity break must remain unchanged;
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

Its role is narrow: move trustworthy raw passive-capture evidence into reproducible bounded offline analysis while preserving selected-target attribution, capture identity, exact scoped receipt chronology, GATT/value-origin provenance, and every known capture-domain continuity gap without inventing physical ES80 semantics.
