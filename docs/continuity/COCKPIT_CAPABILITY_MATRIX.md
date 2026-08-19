# Cockpit data capability and truth matrix

Status: repository-grounded audit at integration base
`cf817a8b1c1f74640055af317671497a202e4f74`. This document describes what
the cockpit may truthfully present today. It is not physical AOVOPRO ES80
protocol authority.

The separate Capture/BLE workstream owns hardware discovery, raw evidence,
confidence-rated mappings, fixtures, and verified decoders. Cockpit consumes
only typed contracts published by that lane. Until then, production physical
fields remain unavailable or explicitly retained/stale; Simulator QA stays
visibly synthetic and isolated from production storage.

## Capability matrix

| Capability | Existing accepted authority | Product wiring at this base | Missing or failure modes | Cockpit fabrication boundary |
| --- | --- | --- | --- | --- |
| Production ES80 transport | `ScooterService` is the app seam. | Ordinary launch injects `UnverifiedScooterService`, which reports unsupported/disconnected, finishes raw speed, and rejects commands. | No verified peripheral identity, services/characteristics, notification custody, reconnect/restoration owner, or semantic decoder. | Profile capability flags describe intended product capability, not observed telemetry. Never render them as current scooter state. |
| Speed truth | `SpeedTelemetrySample`, `SpeedEvidenceLiveTruth`, continuity tokens, connection generations, and `SpeedEvidenceAvailability` distinguish live, retained, and unavailable evidence. | Dashboard reads `VehicleStore.speedEvidenceAvailability`; production display interpolation is disabled. Simulator QA alone receives an explicit interpolation policy. | No verified ES80 speed source, GPS-speed adapter, Core Motion estimator, fusion owner, measured hardware cadence, or evidence-derived impossible-value policy. | Never use cached `VehicleState.speedKilometersPerHour`, marketing top speed, render cadence, or Simulator schedule as physical speed. |
| Speed rendering | `SpeedDisplayInterpolator` may animate between accepted absolute samples without publishing or persisting the midpoint. | The high-frequency Dashboard island can show fluid display motion and removes its timeline after settling. VoiceOver reads the accepted measurement. | Physical latency, filtering, decimals, transition timing, and 60/120 Hz tuning need hosted runtime and hardware evidence. | Render refresh is not sensor refresh. Never call an interpolated frame a new telemetry sample. |
| Propulsion power | `PropulsionPowerSample`, currentness/identity fencing, `ObservedPowerEnvelopeLearner`, accepted peak evidence, and `PropulsionGaugeScaleOrigin`. Verified constructors are package-sealed. | The app accepts power only from the exact `SimulatedScooterService`; current QA scale is an explicit 650 W Simulator scale. `VehicleProfile.aovoproES80.supportsPowerWatts` is false. | No verified physical watts/current/voltage source, sign semantics, cadence, observed envelope, or production adapter. | No fantasy signed kW scale, regen, throttle position, motor-rating scale, or `current x voltage` unless both inputs and synchronization become verified contracts. |
| Battery SOC | `BatteryObservationAuthority` separates measured, estimated, and display-only; retained evidence preserves its original authority/time. | Production battery authority is nil. Simulator battery is `.displayOnly` and cannot train physical range. | Raw ES80 SOC field, scale, resolution, cadence, and meaning remain unverified. | Stock-app percentage is only a correlation anchor. Simulator display-only SOC is never measured physical truth. |
| Cockpit battery interaction | `BatteryPrimaryReadoutState` and `BatteryPrimaryReadoutPresentation` toggle percentage/range while fill remains SOC; `HorizonCockpitStore` persists the preference. | Toggle/state foundations exist, but the rejected Dashboard duplicates a detached range readout. | Native engineered one-value instrument, final motion/contrast/VoiceOver, and hosted visual evidence. | Exactly one centered value: percentage by default or accepted range after tap. Never show both, never let range alter fill. |
| Learned range/efficiency | Accepted SOC chronology, continuity-aware windows, plausibility gates, confidence, low-SOC conservatism, and persistent model foundations exist in NembraCore. | No runtime owner or app injection; `adaptiveRangeEstimate` is nil, so Dashboard truthfully reports unavailable. | Verified live measured SOC, accepted complete-distance windows, vehicle/mode identity, policy selection, atomic persistence adapter, and currentness-restoring runtime. | Never calculate advertised range times SOC or inject the study's `8.4 mi`. Only a current accepted live estimate may become the primary value. |
| Odometer/trip | `RideEngine` can consume monotonic odometer advance and rejects regression; ride history preserves accepted start/end readings. | Dashboard exposes odometer only in Simulator QA. Production remains unavailable. | Field mapping, units/resolution, wrap/reset/continuity policy, and distance reconciliation. | Historical user notes and stock-app displays are references, not `VehicleState` authority. |
| Ride detection | `RideEngine` is a policy-injected state machine: motion may start a candidate but cannot confirm; accepted speed, screened GPS distance, or odometer advance may confirm/sustain. | Enabled only for Simulator QA with deliberately short QA timing. Production `RideApplicationStore` receives no detection configuration and motion is currently false. | Production evidence sources, field-derived thresholds, Core Motion adapter, lifecycle/energy validation. | Never reuse QA timing or say production auto-recording is armed while its configuration is absent. |
| Ride recovery/dedupe | Atomic checkpoint coordinator, idempotent history commit/readback, FIFO app transactions, disconnect continuity, and partial-duration recovery are implemented/tested. | Active only where Simulator configuration provides the stores and policy. | Production detector/transport enablement and real interruption/relaunch evidence. | Recovery never reconstructs unobserved time or movement. |
| Automatic/background capture | Readiness domain distinguishes ASK authorization, peripheral identity, Bluetooth authorization/radio, restoration, background service, location, first unlock, force-quit, and storage. | Current provider intentionally reports absent ES80 descriptor/known peripheral/restoration owner and unknown/unavailable background service. The preference toggle requests intent only. | Accessory descriptor, known-peripheral custody, root `CBCentralManager`, restoration delegate, reconnect, background location lifecycle, candidate journal integration, and device matrix. | Never announce armed/automatic in production today. iOS remains best-effort and cannot relaunch after user force-quit. |
| Candidate crash journal | Dual-slot, generation-fenced, replay-safe `AtomicAutomaticRideCandidateJournal`. | Package/tests only. | Runtime candidate lifecycle integration and recovery UX. | Do not imply unconfirmed candidates survive today. |
| GPS route capture | Core Location source, quality screen, route coordinator, chunked recorder, explicit gaps, session distance sink, and route persistence are implemented/tested. | Not instantiated in production `AppRuntime`; Simulator route fixtures use the production-shaped path separately. | Production authorization/lifecycle owner, evidence-backed policy, ride attachment, background/energy/outdoor validation. | Simulator coordinates and software screening do not prove physical route evidence. |
| Today/duration | Daily segment accumulator/store/projection supports idempotence, DST/time-zone identity, current-ride separation, atomic persistence, and partial/unavailable/conflicting qualifiers. | Product can read durable Today; ordinary production creates no new segments because ride detection is disabled. | Production writer activation, accepted distance reconciliation, day/time-zone lifecycle refresh, real recovery QA. | Today is never scooter session trip. Do not turn partial/unavailable evidence into a clean total. |
| Navigation | Request-fenced route/planning/guidance/reroute/geometry domains and Horizon overlay contracts exist. | Current Navigate action opens portrait search/preview and hands off to Apple Maps; no route is calculated or guided inside Cockpit. | Cockpit MapKit directions adapter, live location session, route selection, maneuver/ETA projection, reroute/loss states, privacy policy, and reflow renderer. | Search results are not scooter-safe routes. MapKit route geometry cannot certify legality or safety. |
| Explore | Versioned road-provider/region/graph identity, license review, eligibility, matcher identity, confidence/ambiguity, independent ride verification, accepted intervals, reprocessing, and coverage aggregation exist in `RoadExplorationDomain`. | Domain only; presentation says unverified. | Licensed/versioned graph, matcher, durable ledger, accepted route binding, overlay provider, and scale/performance evidence. | Never derive city coverage from raw GPS distance or visible MapKit roads. Gold requires accepted map-matched evidence. |

## Current Simulator QA fences

- `SimulatedScooterService` is the only positive current speed/power source in
  the app at this base.
- `VehicleStore.hasSimulatorPowerEvidenceSource` requires that exact actor; a
  protocol-conforming proxy cannot silently mint power authority.
- Simulator persistence uses the simulation scope/namespace; production uses a
  separate directory.
- Simulator battery is `.displayOnly`, odometer is Simulator-only, and the
  cockpit exposes a stable `QA ONLY` accessibility disclosure.
- The explicit render-stress fixture emits broad synthetic updates on a
  detached clock. It does not advance distance/battery and is never BLE cadence
  evidence.

## Drive implementation consequences

The first production Drive slice must be designed around projections rather
than optimistic values:

1. `live`: accepted value plus source/currentness semantics; animation may be
   display-only and bounded.
2. `retained`: last accepted value plus original authority and age; no live
   motion or live status.
3. `unavailable`: a stable typographic unavailable state that preserves layout
   without inserting zero or a marketing default.
4. `Simulator QA`: explicit synthetic disclosure and Simulator-origin scale;
   fixtures never imply physical support.

The Capture/BLE lane may later publish typed physical adapters. Integration is
allowed only when the contract states identity, unit, scale, chronology,
currentness/gaps, signedness, invalid-value policy, and evidence confidence.
UI code must not parse raw packets or guess those properties.

## Highest-value architecture gaps

- production telemetry adapter after Capture publishes verified contracts;
- package-owned accepted adaptive-range runtime and atomic app persistence;
- production ride/location lifecycle wiring with honest iOS background limits;
- in-cockpit MapKit navigation session and privacy policy;
- licensed road graph, scalable matcher/ledger, and geometry provider for
  Explore.

These are integration/evidence gaps, not permission to bypass the existing
validation domains.
