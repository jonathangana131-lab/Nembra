# ES80 CoreBluetooth Passive Capture Adapter

Status: V11 feature-cell software adapter, foreground research acquisition, and offline evidence analysis. No physical 2025 AOVOPRO ES80 advertisement identity, GATT layout, Tuya DP mapping, telemetry scaling/cadence, or application command semantic is verified by this document.

Dependency: the versioned passive evidence model in `NembraCore` (`PassiveBluetoothCapture.swift`, schema v2).

## Architecture and truth boundary

`NembraCore` stays platform-neutral. Apple CoreBluetooth types live in `Packages/NembraBluetoothCapture`, which projects platform observations into immutable `PassiveBluetoothCaptureEvent` evidence.

The adapter must never silently convert:

- a Bluetooth local name or operator `VehicleIdentity` label into physical ES80 identity proof;
- broad-scan candidate advertisements into selected-target capture evidence;
- a candidate service UUID into protocol proof;
- GATT `.write` / `.writeWithoutResponse` properties into command authorization;
- notification/subscription success into scooter command acknowledgement;
- raw value bytes into Tuya packets or decoded fields before framing/meaning is verified;
- stock-app values or time proximity into DP semantics;
- missing evidence after an acquisition error into proven absence.

No application characteristic-value write API exists in this package.

## Candidate catalog versus selected target

The first explicit foreground scan is intentionally broad because the physical ES80 service identity is not yet verified. Discoveries therefore populate an **in-memory candidate catalog only**.

A durable target-labeled capture session does not exist until the operator explicitly chooses one observed peripheral by selecting and connecting it. At target selection:

- a new capture session is created for that target (or the existing session is retained when reconnecting the same target);
- at most that target's latest already-observed advertisement is seeded into the durable timeline;
- unrelated nearby candidates never enter the target artifact;
- stock-app markers, analysis, and JSON export are unavailable before a target session exists;
- choosing a different target starts a different durable session rather than mixing devices.

The selected CoreBluetooth peripheral identifier is attribution evidence for the research session. It is not promoted to a permanent hardware identity and is not proof that the peripheral is physically an ES80.

## Connection-attempt and callback attribution

CoreBluetooth callbacks are asynchronous and cancelled attempts may still deliver terminal callbacks. The adapter therefore maintains a pure target/attempt state machine with monotonically increasing attempt generations.

Rules:

- only callbacks from the currently active selected peripheral may mutate active acquisition state;
- explicit cancel/timeout retires that attempt and quarantines the same peripheral until CoreBluetooth delivers either a failed-connect or disconnect terminal callback;
- a different target may begin while the retired target drains;
- late callbacks from retired target A cannot clear, contaminate, or enter active target B;
- switching targets cannot redirect already-queued evidence: each queued event captures the exact recorder/session generation that existed at callback entry;
- central-manager unavailability retires/preserves same-peripheral quarantine rather than treating a non-`poweredOn` state as proof that old terminal callbacks already drained; the real terminal callback releases that UUID-only quarantine. If CoreBluetooth never supplies that callback, relaunch is the fail-closed recovery instead of admitting an ambiguous same-identifier retry.

The pure state machine is unit-tested without fabricating CoreBluetooth objects.

## Structured connection evidence

Connection lifecycle is captured as parent schema-v2 `.connection` evidence rather than being reduced to free-form interruption strings:

- `.connected`;
- `.failedToConnect`, including stable error domain/code when supplied;
- `.disconnected`, including stable error domain/code and CoreBluetooth platform disconnect timestamp / `isReconnecting` only when the platform supplies them.

Nembra's record receipt uptime/date remain separate from platform event metadata. Structured disconnects carry `event.breaksByteContinuity == true`.

Connection evidence alone never establishes a GATT service/characteristic path.

## Passive GATT acquisition

The passive phase permits only evidence-gathering operations supported by observed characteristic properties:

- discover descriptors for every discovered characteristic;
- read only characteristics advertising `.read`;
- subscribe only to characteristics advertising `.notify` or `.indicate`;
- do not perform application characteristic-value writes.

For a characteristic that supports both read and subscription, the controller performs the initial read first and requests subscription after the read callback. This avoids conflating an explicitly requested read response with a subscribed update.

CoreBluetooth notification configuration may update the GATT Client Characteristic Configuration descriptor internally. That is transport subscription state, not an application scooter command.

## Read and subscription provenance

CoreBluetooth delivers characteristic values through one callback that does not itself say “this was the read you requested.” The adapter therefore tracks outstanding operations by selected peripheral + service UUID + characteristic UUID.

A callback is classified as `.readResponse` only when an outstanding read for that exact path is consumed. Otherwise, if CoreBluetooth reports the characteristic is notifying, the value is classified as `.subscriptionUpdate`. A callback with neither tracked-read provenance nor notifying state is not guessed into a read; capture fails closed as incomplete.

Subscription-state callbacks are recorded as schema-v2 `.subscription` evidence with:

- peripheral/service/characteristic identifiers;
- `requestedEnabled` only when the adapter can prove which tracked request the callback answers;
- the resulting `isNotifying` state;
- stable platform error domain/code when supplied.

A failed subscription callback is preserved as structured evidence first, then the capture fails closed because subsequent missing values must not be presented as a complete observation.

## Fail-closed acquisition completeness

A service, included-service, characteristic, descriptor, read/value, or subscription acquisition failure can make the observed topology/value stream incomplete. The controller therefore treats such failures as capture-fatal for the current target session:

- scanning/acquisition is stopped;
- the controller exposes `captureFailed` and a diagnostic;
- snapshot/export rejects the failed capture;
- missing callbacks after the error are never interpreted as proof that a service/value does not exist.

A future product requirement for exportable partial captures would require an explicit versioned completeness/error model. It must not be inferred from diagnostics or absent events.

## Ordering and continuity

`PassiveCoreBluetoothCaptureRecorder` assigns strict increasing sequence numbers and records `DispatchTime.now().uptimeNanoseconds` as the monotonic receipt clock. That uptime is system-boot-relative, not a wall clock. `Date` is correlation metadata only and never repairs ordering.

Equal monotonic timestamps are allowed; sequence number is the strict tiebreaker. Backward uptime is rejected by the parent capture model.

Offline analyzers use the parent `event.breaksByteContinuity` contract:

- generic interruption events split continuity;
- structured disconnect events split continuity;
- correlation windows never cross those boundaries;
- callback-rate statistics never average an interval across those boundaries.

## Transport fingerprint analysis

`PassiveBluetoothTransportFingerprint` compares observed identifiers against publicly researched candidate families already documented in the repository, currently including modern `FD50` and legacy `A201` / `1910` families.

The report remains deliberately non-authoritative:

- advertisement/service evidence can produce service-level candidate strength when explicitly scoped;
- discovered characteristic/descriptor/value evidence may contribute exact GATT paths;
- schema-v2 subscription evidence may contribute only the exact service/characteristic path it names;
- connection-only evidence cannot create GATT topology;
- multiple families may remain candidates simultaneously;
- no match is a valid result.

Even the strongest candidate means “resembles the researched transport family,” not “the ES80 protocol is verified.”

## Stock-app correlation

A stock-app marker is a human-observed reference such as battery percentage, voltage, current, or power recorded at a known point in the selected target's timeline. It remains correlation evidence only.

The marker's receipt uptime/date identify when Nembra accepted the operator's **Record marker** action. They are not proof of when the stock app refreshed, when its displayed value changed, or when the scooter produced a corresponding transport value. Timing proximity remains correlation evidence rather than decoded field truth.

Nembra records traffic delivered to Nembra's own CoreBluetooth session. It is not a raw-air BLE sniffer and does not claim to intercept another app's private exchange. If simultaneous legitimate observation is not possible, use truthful before/after or repeated controlled sessions and document the limitation.

## Raw packet boundary

Each CoreBluetooth value callback is stored as the bytes actually delivered. The raw capture does not assume:

- one callback equals one Tuya message;
- adjacent callbacks should be concatenated;
- encryption/framing boundaries;
- field identity, scale, units, or signedness.

Any reassembly/decryption/field hypothesis belongs in a derived layer and must remain traceable to immutable raw evidence.

## Research UI boundary

`ES80PassiveCaptureResearchView` is reusable research UI and is not production scooter-control wiring.

It shows:

- central and connection state;
- the currently selected research target, including terminal-callback cancellation quarantine rather than an immediately misleading same-target reconnect action;
- broad discovered candidates;
- target-gated stock-app markers;
- target-gated evidence analysis;
- target-gated versioned JSON export;
- fail-closed capture diagnostics.

Changing target clears stale analysis/export presentation and unsubmitted marker value/note drafted under the previous target so evidence from A is not presented or submitted as B. Reconnecting the same target preserves that draft because the durable target session did not change.

Analysis/export use immutable evidence cuts. User evidence-changing controls are paused while an artifact snapshot is being prepared, and a prepared JSON document remains frozen until the exporter closes. Later CoreBluetooth callbacks remain later live evidence; they are not retroactively folded into the frozen artifact. A displayed analysis summary is likewise a snapshot and must be refreshed to include later accepted evidence.

## Export and secrets

Capture JSON uses the parent versioned `PassiveBluetoothCaptureJSON` envelope. Do not export:

- Tuya local/auth/session keys;
- account tokens;
- unrelated device credentials.

Secret storage/export policy, if ever required for a legitimate future decoder, is a separate design problem.

## Current feature-cell scope

Implemented in the V11 cell:

- target-scoped advertisement, connection, service, included-service, characteristic, descriptor, subscription, value, marker, and continuity evidence;
- selected-target / attempt-generation / read-subscription provenance state;
- fail-closed incomplete acquisition;
- strict ordered recorder and versioned JSON export;
- interruption/disconnect-aware correlation and value-stream statistics;
- conservative non-authoritative transport fingerprinting;
- deterministic pure tests for attempt quarantine, stale target isolation, provenance, v2 continuity, and fingerprint rules.

Not implemented/claimed:

- production app wiring;
- background reconnect;
- cross-app BLE sniffing;
- Tuya pairing/decryption;
- DP decoding;
- any application characteristic-value write or motorized command path;
- physical ES80 validation.

## Acceptance boundary

The package is locally acceptable only when:

1. the coherent `Packages/NembraBluetoothCapture` head compiles and all focused SwiftPM tests pass on the Xcode 27/macOS runner;
2. independent review confirms target attribution, completeness, provenance, and no-write truth boundaries;
3. the feature cell integration branch contains the reviewed parent schema v2 and the child package without unrelated product work;
4. any package-specific CI workflow is reviewed separately as control-plane code rather than assumed from historical #22;
5. the final release train proves combined source/build compatibility under Xcode 27 / iPhone 12 / iOS 27 where applicable.

Physical hardware verification remains a later evidence gate; Simulator/package tests cannot close it.
