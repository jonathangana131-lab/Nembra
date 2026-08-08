# ES80 Passive Capture -> Tuya Candidate Bridge

Status: **SOFTWARE RESEARCH TOOLING ONLY — NOT PHYSICAL ES80 PROTOCOL VERIFICATION**

No physical AOVOPRO ES80 Tuya framing, DP, telemetry field, scaling, signedness, cadence, encryption key, command, or acknowledgement is verified by this bridge.

## Purpose

Nembra keeps two ES80 research layers deliberately separate:

1. passive CoreBluetooth capture that preserves raw GATT/value evidence, exact capture order, target identity, and explicit continuity gaps; and
2. the bounded offline analyzer for a corroborated public Tuya BLE framing family.

`PassiveBluetoothTuyaCandidateBridge` closes only the mechanical gap between those layers. It projects an immutable selected-target capture into deterministic GATT+origin candidate transcripts without asking the operator to copy hex, pick a promising characteristic, renumber callbacks, invent clocks, or reconstruct continuity manually.

A structurally completed framing candidate remains only a public-family hypothesis. This bridge does not promote it to ES80 truth.

## Current dependency shape

This recovery is a dependent child of the accepted current-main passive-runtime composition at #383 product `4b3c4c17ab6e8fec5162f00720f710281b1070bf`.

That parent already carries the accepted analyzer chronology semantics that are also present on current main:

- transcript-wide receipt chronology;
- packet-zero restart after chronology admission;
- scoped immutable receipt sequence authority.

The bridge therefore does **not** replay or modify analyzer source. Its intended product delta is only:

- bridge source;
- bridge regressions; and
- this bridge contract.

#383 still requires a normal non-destructive re-anchor onto the newest main after unrelated ride-stat presentation work advanced main. This child must follow the accepted refreshed passive parent before merge and rerun exact-final-head acceptance. A green dependent child is not permission to revive stale #260/#305 feature ancestry.

The separately accepted ready-to-horizon composition remains a later runtime integration dependency. This bridge does not claim that a live capture has already been horizon-sealed correctly merely because an immutable test/session can be analyzed offline.

## Explicit target presence

The bridge requires one nonblank exact peripheral identifier and then verifies that identifier exists in **target-attributable immutable evidence** before projection.

Target-attributable presence includes exact-peripheral:

- connection evidence;
- service discovery;
- included-service discovery;
- characteristic discovery;
- descriptor discovery;
- subscription evidence; or
- raw value evidence.

Advertisement-only evidence is deliberately excluded. A broad-scan advertisement can place a peripheral in a candidate catalog, but it does not prove that Nembra selected/acquired that target for this capture-analysis authority.

This creates an important fail-closed distinction:

- **requested target absent/stale** -> projection error;
- **requested target observed but no eligible raw value streams** -> valid empty transcript set.

The bridge never turns “unknown target” into an ordinary-looking zero-evidence result.

## Exact receipt chronology

Each immutable passive-capture record already carries:

- `sequenceNumber`: strict order inside one capture session;
- `receivedAtUptimeNanoseconds`: boot-relative monotonic receipt clock metadata; and
- `receivedAtDate`: wall-clock correlation metadata.

The bridge maps those facts mechanically into the accepted analyzer authority model:

- original `record.sequenceNumber` -> `receiptSequenceNumber`;
- exact `session.id.uuidString` -> `receiptSequenceScope`;
- original `receivedAtUptimeNanoseconds` -> analyzer uptime metadata;
- original `receivedAtDate` stays source/correlation metadata only.

The bridge does **not** renumber after filtering by target, characteristic, or value origin. If the selected stream contains source sequences `[1, 5]`, the analyzer receives `[1, 5]`, not `[0, 1]` or `[1, 2]`.

The capture-session UUID is the scope because that immutable session owns the record sequence counter. Peripheral ID, model name, display name, GATT UUID, filename, or wall-clock time are never substituted as sequence scope.

Under the accepted receipt-backed analyzer contract:

- sequence must increase strictly;
- uptime must be nondecreasing and may legitimately tie across different callbacks;
- scope must stay exact;
- bare sequence, bare scope, blank scope, replayed/equal sequence, backward uptime, or authority-mode changes fail closed.

Therefore two real callbacks with equal uptime ticks can remain ordered by capture sequence without inventing nanoseconds. Wall-clock `Date` never repairs or overrides callback order.

The sequence/scope pair is software provenance. It does not authenticate the physical scooter or prove radio-level independence.

## Stream identity and provenance

For the requested target the bridge:

- consumes immutable records in original capture order;
- includes only raw `.value` observations from that exact peripheral;
- preserves exact service and characteristic strings;
- separates every `PassiveBluetoothValueOrigin`, so read responses are never silently spliced with notification/indication/subscription updates;
- preserves session ID, `VehicleIdentity`, session start date, and selected peripheral on every detached transcript;
- preserves exact capture record index, global sequence number, uptime, wall-clock date, and raw candidate bytes on each source fragment;
- keeps independent stream order deterministic by first observation in the capture.

The public provenance/output structs are read-only views with module-internal construction. External callers may inspect producer-issued evidence but cannot mint a bridge report by arbitrarily pairing analyzer outcomes with unrelated capture provenance.

This is a compile-time software evidence boundary, not cryptographic attestation.

## Continuity

Candidate continuity starts at generation zero for one projection and advances only on gaps already explicit in the capture domain:

- a structured disconnect for the exact selected peripheral; or
- a global capture interruption.

A disconnect from another peripheral does not split the selected target. Interleaved callbacks from another GATT stream are filtered from that stream without being converted into fake byte gaps.

An empty selected-target raw value cannot be represented truthfully by the candidate observation type, so projection fails with exact record/sequence/GATT/origin provenance rather than silently dropping it. Continuity-generation overflow also fails closed rather than wrapping.

The bridge does not infer hidden packet loss, device reboot semantics, reconnect success, subscription continuity, or bytes that were never observed.

## Analyzer output

`PassiveBluetoothTuyaCandidateBridge.analyze(...)` runs the bounded `TuyaCandidateTranscriptAnalyzer` independently for every exact GATT+origin transcript.

Analyzer observation indices are stream-local, while every source fragment retains its original global capture record index and sequence. A caller can therefore map completed, rejected, restarted, boundary-truncated, and end-truncated candidate outcomes back to the immutable source without filename conventions or manually copied hex.

`completed` means only that captured bytes satisfy the selected bounded public-family framing hypothesis. It does **not** mean:

- the physical ES80 is verified to use that Tuya family;
- ciphertext is authenticated or decrypted;
- a logical packet is physically verified;
- any DP is battery, voltage, current, power, speed, mode, lock, light, throttle, regen, trip, or odometer;
- any command is authorized or acknowledged.

A rejection remains useful falsifying evidence. The bridge does not shift offsets, delete bytes, rewrite timing, merge origins, or retry alternate interpretations until one succeeds.

## Acceptance requirements

Before this bridge is production research infrastructure:

1. its exact three-path dependent product must pass focused/full package tests, the package-wide no-application-`writeValue(...)` guard, and a generic iOS Simulator package build on Xcode 27;
2. the accepted #383 passive parent must be refreshed onto then-current main and re-gated on that exact final head;
3. this child must follow that refreshed parent without replaying stale analyzer/runtime ancestry and rerun any acceptance invalidated by the moved base;
4. the later ready/horizon live queue-cutoff and immutable-artifact composition must remain explicit before physical experiment authorization;
5. the offline report/CLI should consume this accepted bridge descendant mechanically rather than maintain a second bridge or flatten sequence/scope/target-presence evidence.

Queued, running, skipped, stale, ancestor, or dependency-obsolete checks are not acceptance.

## Intended physical workflow

Only after the passive runtime, finite observation boundary, product-facing capture shell, bridge, immutable artifact/sidecar, and offline report path are jointly accepted should the first physical experiment proceed:

1. select the real ES80 in Nembra Research Capture while stationary;
2. perform a short passive acquisition with no characteristic-value writes;
3. retain the exact immutable artifact and required correlation/provenance metadata;
4. let Nembra tooling project exact selected-target value streams automatically;
5. compare repeated structural/correlation evidence without manual hex editing;
6. promote a field only after repeatable physical evidence establishes source, framing, DP identity/type, scale, signedness, units, cadence, continuity, and provenance.

Until that full ladder closes, **Experiment One remains DO NOT RUN**.

## Safety boundary

This bridge adds no `writeValue`, command path, encryption/decryption key handling, device authentication, production `ScooterService`, Dashboard telemetry wiring, or vehicle-control acknowledgement.

Its role is narrower: move trustworthy raw passive-capture evidence into reproducible bounded offline analysis while preserving target presence, capture identity, exact scoped receipt chronology, transport provenance, and known gaps.
