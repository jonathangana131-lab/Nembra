# ES80 CoreBluetooth Passive Capture Adapter

Status: software adapter foundation. No physical 2025 AOVOPRO ES80 advertisement, GATT, Tuya DP, or command semantic is verified by this document.

Dependency: the platform-neutral evidence model in PR #11 / `NembraCore`.

## Architecture boundary

`NembraCore` remains platform-neutral. Apple CoreBluetooth types live in the separate `Packages/NembraBluetoothCapture` package, which projects platform observations into immutable `PassiveBluetoothCaptureEvent` evidence.

The adapter layer must never silently convert:

- local name into vehicle identity;
- candidate service UUID into protocol proof;
- GATT write capability into command authorization;
- notification bytes into a Tuya packet before framing is verified;
- stock-app values into decoded DPs;
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

## Passive characteristic acquisition

The passive phase permits only evidence-gathering operations supported by observed GATT properties:

- discover descriptors for every discovered characteristic;
- read a characteristic only when it advertises `.read`;
- subscribe only when it advertises `.notify` or `.indicate`;
- do not write an application characteristic value.

Apple documents `setNotifyValue` as the way a central configures characteristic notifications/indications, including the Client Characteristic Configuration descriptor behavior. That subscription configuration is transport state rather than a scooter application command, but it is still limited to characteristics that explicitly advertise notify/indicate capability.

Official Apple references:

- https://developer.apple.com/documentation/corebluetooth/cbcharacteristic/properties
- https://developer.apple.com/documentation/corebluetooth/cbdescriptor/value

## Notification versus indication truth

CoreBluetooth reports changed characteristic values through the same `didUpdateValueFor` delegate callback and does not provide enough delivery metadata there to truthfully label each callback as GATT notification versus indication merely from the callback itself.

PR #11 therefore includes `subscriptionUpdate` as an intentionally ambiguous origin. The adapter must use that classification for subscribed callbacks unless stronger evidence exists; it must not guess.

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
- dedicated Xcode 27 package CI.

Not implemented/claimed yet:

- production app wiring;
- physical scan/connect UI;
- background reconnect;
- Tuya pairing/decryption;
- DP decoding;
- any motorized-hardware write;
- physical ES80 validation.

## Acceptance boundary

This package can be accepted as a software foundation when:

1. its exact-head package tests pass on the Xcode 27 runner;
2. it is reconciled with the final accepted PR #11 evidence model;
3. its diff remains isolated from active app/location/UI workers;
4. no application write API or inferred ES80 protocol mapping appears in the adapter.

Physical hardware verification remains a later evidence gate, not something Simulator/package tests can prove.
