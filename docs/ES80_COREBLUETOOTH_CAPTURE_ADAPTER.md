# ES80 CoreBluetooth Passive Capture Adapter

Status: software adapter + foreground research acquisition + offline correlation/fingerprint analysis. No physical 2025 AOVOPRO ES80 advertisement, GATT, Tuya DP, or command semantic is verified by this document.

Dependency: the platform-neutral evidence model in PR #11 / `NembraCore`.

## Architecture boundary

`NembraCore` remains platform-neutral. Apple CoreBluetooth types live in the separate `Packages/NembraBluetoothCapture` package, which projects platform observations into immutable `PassiveBluetoothCaptureEvent` evidence.

The adapter layer must never silently convert:

- local name into vehicle identity;
- candidate service UUID into protocol proof;
- GATT write capability into command authorization;
- notification bytes into a Tuya packet before framing is verified;
- stock-app values into decoded DPs;
- time proximity into field semantics;
- CoreBluetooth write completion into scooter-state confirmation.

## Current 2025 target

The physical Nembra target is the newer 2025-generation AOVOPRO ES80. Its stock app is directly observed to expose live:

- battery percentage;
- voltage;
- amps/current;
- wattage/power.

Those values are correlation anchors for capture. Their raw BLE/Tuya source, scale, cadence, signedness, and derivation remain unverified.

## Apple CoreBluetooth evidence preserved

Current Apple documentation exposes standard advertisement fields for:

- local name;
- manufacturer data;
- service data;
- advertised service UUIDs;
- overflow service UUIDs;
- solicited service UUIDs;
- Tx power;
- connectability;
- discovery RSSI.

The adapter maps all of those fields without interpreting them.

Apple also exposes discovery of:

- services;
- included-service relationships;
- characteristics and characteristic properties;
- descriptors;
- characteristic values from reads or subscribed updates.

The capture domain preserves those structures without manufacturing missing values.

Official Apple references accessed 2026-08-06:

- https://developer.apple.com/documentation/corebluetooth/advertisement-data-retrieval-keys
- https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate
- https://developer.apple.com/documentation/corebluetooth/cbperipheral/services
- https://developer.apple.com/documentation/corebluetooth/cbservice/characteristics
- https://developer.apple.com/documentation/corebluetooth/cbcharacteristic/descriptors
- https://developer.apple.com/documentation/corebluetooth/cbdescriptor/characteristic

## First fingerprint scan policy

For the first explicit **foreground research** fingerprint, Nembra cannot assume that the physical ES80 uses FD50, A201, 1910, F1/F2, or another family. The package therefore exposes a nil service filter for this research-only scan policy so unknown service evidence is not discarded before it is observed.

Apple recommends scanning for specific service UUIDs in ordinary usage. Once the physical ES80 fingerprint is verified, production/reconnect scanning should use the narrow verified service set instead of a permanent unfiltered scan.

Apple also documents duplicate-filter control. Duplicate callbacks can be useful when measuring real advertisement cadence/change behavior, but Apple warns of battery cost. The adapter therefore makes duplicate advertisement capture explicitly opt-in.

Official Apple references:

- https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:)
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerscanoptionallowduplicateskey

## Foreground live acquisition controller

`ForegroundCoreBluetoothCaptureController` is a user-initiated research controller, not the production scooter transport.

It:

- scans broadly in the foreground for the first unknown fingerprint;
- exposes actually discovered peripheral UUIDs for explicit selection;
- does not promote local-name similarity to ES80 identity;
- owns a finite connection cancellation deadline because CoreBluetooth connection attempts do not time out by themselves;
- discovers all services, included services, characteristics, and descriptor UUIDs after connection;
- reads only readable characteristics;
- subscribes only to notify/indicate characteristics;
- records Bluetooth central-state transitions, disconnects, and service invalidation as continuity interruptions;
- discards stale GATT object state and rediscovers after invalidation/reconnect boundaries;
- maintains one MainActor callback queue so asynchronous recorder calls cannot reorder the original CoreBluetooth callback sequence.

No application characteristic-value write API exists in this controller.

Official Apple references:

- https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/connect(_:options:)
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:)
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate
- https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate

## Passive characteristic acquisition

The passive phase permits only evidence-gathering operations supported by observed GATT properties:

- discover descriptors for every discovered characteristic;
- read a characteristic only when it advertises `.read`;
- subscribe only when it advertises `.notify` or `.indicate`;
- do not write an application characteristic value.

For characteristics that support both read and notify/indicate, the live controller performs the initial read first and begins subscription after that callback. This prevents a requested initial read from being silently mislabeled as an unsolicited subscribed update.

Apple documents `setNotifyValue` as the way a central configures characteristic notifications/indications, including the Client Characteristic Configuration descriptor behavior. That subscription configuration is transport state rather than a scooter application command, but it is still limited to characteristics that explicitly advertise notify/indicate capability.

Official Apple references:

- https://developer.apple.com/documentation/corebluetooth/cbcharacteristic/properties
- https://developer.apple.com/documentation/corebluetooth/cbdescriptor/value

## Notification versus indication truth

CoreBluetooth reports changed characteristic values through the same `didUpdateValueFor` delegate callback and does not provide enough delivery metadata there to truthfully label each callback as GATT notification versus indication merely from the callback itself.

PR #11 therefore includes `subscriptionUpdate` as an intentionally ambiguous origin. The adapter uses that classification for subscribed callbacks unless stronger evidence exists; it does not guess.

## Raw packet boundaries remain immutable evidence

Public Tuya research shows that Tuya performs packet reassembly and decryption above GATT. Therefore:

- each CoreBluetooth value callback is captured as the bytes actually delivered;
- one callback is not assumed to equal one Tuya message;
- multiple callbacks are not joined in the raw capture artifact;
- sequence number + monotonic receipt time preserve reconstruction order;
- any Tuya reassembly/decryption happens later in a derived decoder layer.

See:

- `docs/ES80_TUYA_TRANSPORT_RESEARCH.md`
- `docs/ES80_TUYA_REVERSE_ENGINEERING_CANDIDATES.md`

## Stock-app correlation is not cross-app packet sniffing

`recordStockAppObservation` inserts a human-observed stock-app marker such as `39.8 V`, `4.2 A`, `167 W`, or `73%` into the same evidence timeline when the research setup legitimately makes that observation available.

The CoreBluetooth controller records traffic delivered to **Nembra's own** central/peripheral session. It is not a raw-air BLE sniffer and must not claim that it intercepted another app's private GATT exchange.

If the stock Tuya app and Nembra cannot both maintain a legitimate connection to the scooter at the same time, correlation must instead use one of the following truthful setups:

- before/after markers with the timing limitation documented;
- a second device only if simultaneous connection is actually supported and verified;
- an external BLE sniffer/test setup where legally and technically appropriate;
- repeated controlled sessions whose state changes are reproducible.

Never fabricate a simultaneous correlation that the physical setup did not provide.

## Offline stock-app correlation windows

`PassiveBluetoothCorrelation` is intentionally semantic-free. It finds raw characteristic-value callbacks within a configurable monotonic-time window around stock-app markers.

Rules:

- interruption records are hard boundaries;
- values across a disconnect/Bluetooth transition/observer restart are never suggested as candidates for one marker;
- candidate payloads stay opaque bytes/hex;
- candidates are ordered by time proximity, then sequence number;
- a nearby packet is a **correlation candidate only**, never proof that it carries the displayed voltage/current/power/battery field.

This gives physical research a fast way to narrow which characteristics deserve deeper differential analysis without poisoning raw evidence.

## Offline transport fingerprint candidates

`PassiveBluetoothTransportFingerprint` summarizes observed service/characteristic identifiers and compares them against the **publicly researched candidate families** currently documented in the repository:

- modern Tuya `FD50` family;
- corroborated legacy Tuya `A201` + `2B10`/`2B11` family;
- legacy-documented Tuya `1910` + `2B10`/`2B11` family.

The report deliberately supports:

- service-only candidate strength;
- partial characteristic-family strength;
- expected-data-path strength;
- multiple simultaneous candidate matches;
- no match at all.

Even its strongest result means “this capture resembles the researched family,” not “the ES80 protocol is verified.” Unknown services remain valid evidence and must not be forced into a candidate.

## Recorder clock model

`PassiveCoreBluetoothCaptureRecorder` assigns strict monotonically increasing sequence numbers. It stores:

- process-local monotonic uptime nanoseconds for ordering;
- wall-clock `Date` only for correlation with the stock app / user observation.

Equal monotonic timestamps are allowed because multiple callbacks can fall in one timer tick; sequence number is the strict tiebreaker. A monotonic timestamp moving backwards is rejected by the core capture model.

## Export and secrets

Capture JSON uses PR #11's versioned `PassiveBluetoothCaptureJSON` codec.

Do not export:

- Tuya local keys;
- auth keys;
- session keys;
- account tokens;
- unrelated device credentials.

If a later legitimate decoder requires a secret from the user's own bound device, secret storage/export policy must be designed separately. Raw research evidence should be shareable without leaking credentials by default.

## Current package scope

Implemented now:

- CoreBluetooth advertisement projection;
- service projection;
- included-service topology projection;
- characteristic UUID/property projection;
- descriptor UUID projection;
- raw characteristic value projection;
- strict ordered recorder;
- versioned JSON export;
- passive acquisition policy;
- foreground research scan/connect/discover/read/subscribe controller;
- explicit connection timeout/cancellation ownership;
- stock-app marker capture;
- interruption-aware offline raw-value correlation windows;
- non-authoritative Tuya transport fingerprint report;
- dedicated Xcode 27 package CI and deterministic tests.

Not implemented/claimed yet:

- production app wiring;
- polished physical capture UI;
- background reconnect;
- cross-app BLE sniffing;
- Tuya pairing/decryption;
- DP decoding;
- any motorized-hardware application write;
- physical ES80 validation.

## Acceptance boundary

This package can be accepted as a software foundation when:

1. its exact-head package tests pass on the Xcode 27 runner;
2. it is reconciled with the final accepted PR #11 evidence model;
3. its diff remains isolated from active app/location/UI workers;
4. no application write API or inferred ES80 protocol mapping appears in the adapter;
5. offline correlation/fingerprint output remains explicitly candidate evidence rather than decoded truth.

Physical hardware verification remains a later evidence gate, not something Simulator/package tests can prove.