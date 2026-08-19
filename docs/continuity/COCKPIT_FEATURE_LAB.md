# Nembra truthful feature lab

Status: capability backlog grounded in repository state at
`cf817a8b1c1f74640055af317671497a202e4f74`. A feature listed here is not a
hardware capability claim. Each candidate must retain its input, confidence,
failure, privacy, and energy contract through implementation.

## Classification

- **Accepted existing slice**: current product behavior has an evidence-backed
  implementation and may be refined without changing its truth claim.
- **Experimental**: architecture is viable, but the product lacks one or more
  evidence, lifecycle, privacy, policy, or runtime acceptance gates.
- **Blocked**: a specific external contract/provider/hardware input is absent.
- **Rejected**: current evidence cannot support the claim safely.

## Capability matrix

| Candidate | Required inputs and confidence | Status | Failure modes, privacy, and energy cost |
| --- | --- | --- | --- |
| In-cockpit navigation | User-selected destination, MapKit route, quality-screened location, separately gated route/step/continuity/reroute confidence. | **Experimental.** Strong NembraCore planning/guidance foundations; app currently searches and hands off to Apple Maps. No `MKDirections` cockpit adapter/session. | Server/throttle/offline errors, denied/reduced GPS, no field-derived thresholds. High location privacy; medium/high active GPS/map energy. Cycling directions do not prove scooter legality. |
| Explore road coverage | Immutable accepted route bytes, independently verified ride, licensed/versioned road graph, matcher/policy identity, confidence/ambiguity result. | **Experimental and externally blocked.** Domain is fail-closed; dataset, matcher, persistence, spatial index, and renderer are absent. | Gaps, ambiguity, graph revisions, licensing. Very high route privacy; medium batch-match/render energy. A city percentage must remain a verified lower bound. |
| Automatic ride tracking | Verified BLE speed/currentness, optional authoritative odometer, screened GPS deltas, chronology, motion evidence, and explicit gaps. | **Experimental and hardware-gated.** Engine, journal, ledger, recovery, and readiness semantics exist; production detector/transport/location owners remain disabled. | iOS restoration/background limits, no verified ES80 identity, no production location policy. High route privacy; BLE moderate and navigation-grade GPS high energy. |
| Route replay | Persisted validated segmented geometry with gap/coverage metadata. | **Accepted existing slice.** Static completed-ride MapKit replay exists and preserves gaps. | Store unavailable/corrupt, points-only/partial route. Very high location privacy; modest render energy. No animated timeline replay. |
| Ride evidence export | Accepted ride record plus explicit route state and validated segmented geometry. | **Best first package-only feature-lab slice after Drive.** Current Settings JSON omits route geometry. | Explicit share can expose sensitive location/history. Export must be user-initiated, deterministic, gap-preserving, and low energy. |
| Daily/weekly analytics | Durable daily segments with availability-qualified distance/duration. | **Accepted base; expanded analytics experimental.** Daily/weekly/cumulative/streak presentation exists. | Partial/unavailable evidence, time-zone/calendar changes, store conflict. Local privacy medium; low energy. |
| Learned range/efficiency | Verified SOC anchors, continuity, complete accepted distance, scooter/mode identity, plausibility policy. | **Experimental and blocked.** Strong accepted model/persistence domains exist; no production runtime owner supplies a live estimate. | Physical identity/currentness absent; first baseline deliberately defers. Sensitive local usage profile; low incremental energy. Never advertised-range times SOC. |
| Parking memory | Last quality-screened point near a confirmed ride end, accuracy, time, and route coverage. | **Experimental candidate.** Not implemented. | Must say “phone last observed near ride end,” never “scooter is here.” Gaps/reduced accuracy/phone separation invalidate confidence. Very high privacy; near-zero incremental energy only when derived from active ride capture. |
| Maintenance reminders | Authoritative odometer or accepted distance plus user-owned service baseline/date. | **Experimental reminder; diagnostic claims rejected.** | Physical odometer unavailable; GPS history may be partial. Low privacy/energy. Wording is distance/time reminder, never fault prediction. |
| Live Activity/widgets | Genuine active-ride identity/state, qualified duration/distance, current connection/battery plus stale date. | **Experimental after production ride ownership.** No widget extension or ActivityKit target. | Lock-screen privacy, activity limits, stale updates. Event-driven energy low/moderate. A Live Activity cannot serve as a background-execution loophole. |
| Battery health percentage | Verified voltage/current/temperature/capacity and charge/discharge history. | **Rejected now.** | Required physical inputs absent; weather, rider, tires, terrain, and mode confound inference. Any percentage would be false precision. |
| Theft/motion detection | Scooter-mounted motion evidence or verified accessory event plus reliable background delivery. | **Rejected now.** Phone motion cannot prove scooter motion. | High false positives, background gaps, energy/privacy cost. Future “connection lost / last observed” may be informational only. |
| Crash/fall detection | Validated phone IMU geometry, mount state, speed, outdoor traces, conservative confirmation UX. | **Rejected now.** | Severe false positives/negatives and liability; high sensor energy/privacy. A future opt-in unusual-deceleration bookmark may be research-only. |
| Coverage goals | Verified road coverage aggregate plus user-defined target. | **Experimental and blocked with Explore.** | Cannot precede graph/matcher authority. Low incremental energy once coverage exists; never fake city percentages. |

## Recommended first feature-lab implementation

After the Drive vertical slice passes its hosted acceptance gate, implement a
package-owned versioned Ride Evidence Export rather than a sensor-dependent
feature. It should consume one accepted `RideHistoryRecord` plus an explicit
route state (`recorded`, `noGeometry`, `storageUnavailable`, or
`verificationFailed`) and emit deterministic schema-v1 JSON that:

- preserves separate route segments and every evidence gap;
- records coverage, point/gap counts, timestamps, accuracy, source/session
  identity, and schema version;
- never joins gaps, infers place names, calls rendered MapKit geometry evidence,
  or claims physical completeness;
- rejects session mismatch, corrupt/nonfinite geometry, and nondeterministic
  ordering;
- is created only by an explicit user share action in the portrait-owned layer.

This slice uses durable accepted evidence, needs no unverified BLE field,
background entitlement, MapKit server, or road license, and can be tested
package-first without editing portrait composition.

## Required review for every future feature

Before moving a candidate from this file into product code, record:

1. exact typed input and owner;
2. authority, source identity, chronology, currentness/gaps, and confidence;
3. failure and degraded presentation;
4. local/remote data retention and deletion behavior;
5. privacy disclosure and permission scope;
6. battery/network cost and background behavior;
7. Simulator/test fixture fence;
8. GitHub Xcode 27/runtime and, where physical, real-device evidence.
