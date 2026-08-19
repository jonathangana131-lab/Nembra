# Nembra 1.0 production foundation

Status: active implementation contract, 2026-08-18

## Visual-selection boundary

The user's selected portrait production package is preserved byte-for-byte in
`docs/design-reference/nembra-1.0-gold-glass/`. Its Home option 2, refined
Rides option 1, Vehicle option 2, and native-quiet Settings option 1 are the
sole portrait composition targets. The previous white/card-heavy Home remains
functional regression history only and has no layout authority. All four
screens use the selected graphite/white/warm-gold system and native Liquid
Glass for functional navigation/control chrome.

The original Orbit, Vector, and Apex Dashboard boards are rejected and have no
implementation authority. The user selected the **Horizon / Road Intelligence
concept and information architecture** on 2026-08-18. Nembra Vision and Halo
are not selected and must not be merged into Horizon without a later explicit
user revision.

The V2 Option 2 board is rejected as a production visual execution. Its
geometry, typography, thin placeholder roads, debug labels, generic metric
strip, and styling must not be implemented or frozen. It is historical concept
evidence only.

The complete **Horizon Cockpit V3** package is preserved byte-for-byte in
`docs/design-reference/horizon-v3/` as rejected historical exploration. On
2026-08-18 the user explicitly rejected its styling, layout geometry, map art,
typography, and visual components as prototype-quality. It is superseded and
has no production visual authority. `V3_COCKPIT_REJECTED.md` records this
decision beside the original assets; the originals remain only for design
history and may not be rasterized into the shipped app.

The supporting production system remains shared and evidence-driven:

- source-authoritative speed, battery/range, ride, navigation, and discovery data;
- explicit Dashboard entry/exit/orientation and state preservation;
- automatic ride capture and its readiness/recovery truth;
- durable current-ride and local-day evidence;
- versioned road-network matching and coverage;
- accessibility, QA, performance, and release evidence.

Dashboard visual composition is frozen until a later user-approved target
arrives. Work may continue only on selection-independent production
architecture: landscape scene authority and portrait restoration, explicit
Drive/Navigation/Explore state, authoritative or unavailable metric contracts,
automatic ride and local-day continuity, versioned road-network overlays,
MapKit adapter boundaries, accessibility semantics, and performance/QA
harnesses. No active launcher, cockpit screen, road-world renderer, typography,
or V3-derived visual component may ship from this package. These foundations
do not authorize fake telemetry, display-derived evidence, main-thread map
matching, or an old prototype Dashboard fallback.

## Ownership boundaries

The 60 FPS cockpit is a presentation island. It may read immutable snapshots and
perform bounded render interpolation. It may not decode BLE, write databases,
run map matching, query a road graph, recompute aggregates, or turn rendered
values into evidence.

Long-lived services exist independently of SwiftUI views:

1. accessory authorization and one Core Bluetooth central owner;
2. accepted-sample journal and ride state machine;
3. ride-scoped Core Location owner and raw route recorder;
4. completed-history and day-segment ledgers;
5. asynchronous road matcher and coverage store;
6. navigation coordinator and provider adapters;
7. narrow presentation stores/snapshots.

Capture remains a disposable physical-research utility. It does not become the
production Bluetooth owner, and its unverified protocol observations do not
become production telemetry semantics.

## Automatic capture: supported promise

After one-time setup and consent, Nembra attempts the strongest public-API path
to reconnect to the known scooter and record a qualifying ride without opening
the UI. This is conditional best effort, not an always-running guarantee.

Apple's current public rules require:

- AccessorySetupKit setup for Bluetooth restoration relaunch on iOS 26+;
- a stable restoration identifier on one long-lived `CBCentralManager`;
- a pending specific scan, connection, or subscription for restoration;
- a foreground setup step with exact supported accessory descriptors;
- minimal work during background wake windows;
- a foreground-created/recreated Core Location service/background session while
  a qualifying ride needs route capture.

The app must never claim it can restore after a user force-quit. It must also
surface Bluetooth-off, accessory authorization removal, restart-before-first-
unlock, permission, background-service, and storage limitations.

Primary platform references:

- https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules
- https://developer.apple.com/documentation/accessorysetupkit
- https://developer.apple.com/documentation/corebluetooth/cbconnectperipheraloptionenableautoreconnect
- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background

Do not add AccessorySetupKit discovery identifiers or production background
modes until Capture or another accepted physical source proves the exact ES80
advertising name/service/company descriptors and a real-device run proves the
owner lifecycle. AccessorySetupKit can crash when discovery descriptors are not
declared consistently in the app's information property list.

### Readiness outcomes

The domain must distinguish at least:

- Ready;
- Location limited (ride telemetry may continue; route/Explore is partial);
- Bluetooth disabled or unauthorized;
- accessory not set up, awaiting authorization, or authorization removed;
- exact accessory descriptor evidence unavailable;
- background Bluetooth/location capability not configured or unavailable;
- app must be reopened after user force-quit;
- device restarted and awaits first unlock;
- automatic capture intentionally disabled;
- local journal/history storage unavailable.

A healthy Home has no permanent warning. Onboarding and Settings show the full
status; Home shows a quiet action only when intervention is required.

### Ride lifecycle and journals

The existing `RideEngine` remains the ride-evidence authority. A surrounding
transport/restoration owner projects:

`armed -> connecting/restoring -> connectedIdle -> candidateRide -> activeRide
-> temporaryGap/candidateEnd -> closed`, with `needsReview` for corrupt,
conflicting, or non-monotonic evidence.

Candidate observations are written to a separate idempotent atomic journal
before promotion. This does not weaken the existing confirmed-ride two-slot
checkpoint. A candidate interrupted before confirmation remains evidence but
cannot become a ride without fresh qualifying evidence.

## Today versus Current ride

`Today` is not the scooter's power-session trip value. It is derived from
durable accepted day-aligned segments across every legitimate ride assigned to
the frozen local-day identity captured with the evidence. `Current ride` is a
separate session projection.

Rules:

- stable `(sessionID, segmentSequence)` identities make replay idempotent;
- identical replay is a no-op; conflicting replay fails closed;
- a segment may not cross its frozen local-day interval;
- a ride crossing midnight or a time-zone change closes one segment and opens
  another at an accepted checkpoint;
- without trustworthy boundary evidence, Nembra records a partial/unavailable
  interval rather than proportionally inventing distance;
- accepted local-day attribution is not retroactively moved when the user later
  changes time zones;
- DST days retain their true 23- or 25-hour intervals;
- known subtotals remain visibly partial; unavailable/conflicting evidence never
  contributes a number.

## Explore: road-network evidence

MapKit remains the basemap/presentation provider. Its rendered roads and route
polylines are not an enumerable, stable road-coverage graph. Explore therefore
requires a separately selected and licensed versioned road-network provider.

The provider contract must expose stable dataset/region/version provenance,
segment identity, canonical geometry, length, direction, classification, access
metadata, city/district membership, license, and visible attribution.

The matching pipeline preserves raw accepted route points, then produces an
immutable match run keyed by ride route digest, dataset version, matcher version,
and policy version. Claims retain confidence, ambiguity, unmatched spans, source
point ranges, and partial covered intervals. Overlapping intervals merge
idempotently; raw evidence remains available for offline reprocessing.

Default completion is direction-agnostic and measured by verified covered length
over the policy's eligible rideable network length. Segment count is not the
denominator. Divided roads, service roads, private/illegal roads, paths, stairs,
highways, ferries, bridges, and tunnels require explicit eligibility policy.

Never mark coverage from a planned route, rendered interpolation, a GPS jump, a
parallel road chosen only by proximity, low-confidence evidence, or location
that is not independently tied to a qualifying ride.

OpenStreetMap-derived data is not selected by this document. Selecting it first
requires an ODbL, attribution, database-distribution, update, and offline-cache
review: https://www.openstreetmap.org/copyright

## Evidence gates

Simulator fixtures prove deterministic state/presentation only. Release claims
require exact-head Xcode 27, iPhone 12/iOS 27, real-device background lifecycle,
real ES80 reconnect, permission changes, restart/first-unlock, force-quit truth,
storage interruption, route gaps, midnight/time-zone/DST, and urban map-matching
traces. Release performance evidence must cover sustained hitches/CPU, thermal,
battery, memory, database growth, map overlay scale, and idle animation shutdown.

## Selected Horizon production visual target

The selected Dashboard/Cockpit visual target is now Horizon V4 at
`docs/design-reference/horizon-v4-final/`. Its production contract is
`NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md` in that directory.

All Horizon V2 and V3 cockpit images are rejected historical evidence. They must
not be used as implementation foundations. The V4 handoff controls visual
hierarchy, safe-area geometry, Drive/Navigation/Explore transformation, motion,
and acceptance criteria while this foundation remains authoritative for product
truth, protocol evidence, automatic-capture limits, persistence, and road-network
evidence.
