# Capture + Bluetooth continuity

Status: consolidation handoff for the stopped Capture/Bluetooth-truth workstream. `DEVELOPMENT_CONTINUITY.md` remains the repository-wide authority; this file supplies the Capture-specific evidence ledger and executable next steps for a new unified owner.

## Recovery coordinates

- Repository: `jonathangana131-lab/Nembra`
- Branch: `product/capture-1-0-main-20260818`
- Draft PR: [#3675 — Finish Capture checkpoint and production Nembra surfaces](https://github.com/jonathangana131-lab/Nembra/pull/3675)
- Latest pushed implementation checkpoint: `b16cec4c437b848339bd5b154ed43edf66220b2b`
- Last fully completed hosted Capture baseline: `3f0814ac70211f68b7af1a6913c78c91a810f663`
- Physical status: **NO-GO**. CI and Simulator evidence are not hardware evidence or field authorization.
- Current physical procedure: `ES80-AUTHENTICATED-STATIONARY-v1` in `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`
- Current installer entry point: `scripts/field/install_one_time_capture.command`
- Protocol ledger: `docs/ES80_PROTOCOL_MAP.md`

This file is updated by a continuity-only commit immediately after the implementation checkpoint and therefore cannot embed its own commit SHA. Verify `git ls-remote origin refs/heads/product/capture-1-0-main-20260818`, the PR head, and its exact-head checks before resuming; the remote branch head supersedes this file if newer.

## Acceptance boundary

Capture 1.0 is not done merely because it builds. It must:

1. guide the intended operator through the smallest safe one-time session;
2. preserve lossless source evidence, timing, continuity, build/procedure provenance, and human action windows;
3. export immutable machine-readable evidence plus a human-readable summary with few taps;
4. generate an evidence-backed protocol map that separates observation, inference, and hypothesis;
5. promote only verified mappings into production decoding, with stale/invalid/impossible-value behavior tested;
6. leave every unknown and physical limitation explicit.

No Home/menu or cockpit visual implementation is owned here. Those isolated workstreams consume only published, stable Capture/BLE contracts and fixtures.

## Preserved software inventory

Do not replace working evidence machinery while closing the missing mapping path.

| Capability | Preserved implementation |
| --- | --- |
| Versioned passive evidence model | `Packages/NembraCore/Sources/NembraCore/PassiveBluetoothCapture.swift` — schema v3 JSON; advertisements, connection state, complete discovered GATT topology, subscription results, raw value `Data`, human stock-app markers, interruptions, sequence, boot-relative receipt uptime, wall-date metadata, and observation boundaries. Schemas v1/v2 remain readable. |
| Physical transport ledger | `Packages/NembraCore/Sources/NembraCore/PhysicalCaptureTransportEvidence.swift` and `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md` — transport-only authority; `authorizesTelemetrySemantics` is always false. |
| Passive CoreBluetooth acquisition | `ForegroundCoreBluetoothCaptureController.swift`, `PassiveCoreBluetoothAcquisitionPolicy.swift`, `PassiveCoreBluetoothCaptureRecorder.swift`, `PassiveCoreBluetoothGATTIdentityRegistry.swift`, and lifecycle/operation-ledger files under `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/`. The controller scans without a service filter, discovers all services/included services/characteristics/descriptors, reads readable characteristics, subscribes to notify/indicate, records callbacks, and exposes no application-value write. |
| Fresh target correlation | `PassiveBluetoothPowerCycleObservationSession.swift`, `PassiveBluetoothPowerCycleTargetCorrelation.swift`, `PassiveBluetoothExperimentOneCoordinator.swift`, and related structural/readiness tests. The accepted method is the current-attempt `OFF1 -> ON1 -> OFF2 -> ON2` sequence with exactly one repeatable full CoreBluetooth identity and explicit operator confirmation. Hints cannot break ties. |
| Passive artifact sealing/export/import | `PassiveBluetoothExperimentOneSoftwareExport.swift`, `PassiveBluetoothExperimentOneFinalShareArtifact.swift`, their integrity types/tests, and `PassiveBluetoothCaptureJSON.decode`. Exact nested bytes, digests, build provenance, manifest, and capture binding are verified. This remains the historical `ES80-FINGERPRINT-v1` passive format, not the new authenticated mapping format. |
| Authenticated read-only session gates | `TuyaAuthenticatedReadOnlySessionLedger.swift`, `TuyaAuthenticatedReadOnlyPreflight.swift`, `TuyaLocalBLEAcquisitionWindow.swift`, `TuyaSDKAccountDeviceMembershipGate.swift`, `TuyaSDKAccountIdentityLeaseGate.swift`, `StationaryCaptureOperatorAttestation.swift`, and `NembraApp/App/NembraCaptureEntrypoint.swift`. These enforce generation, chronology, account/device lease, local-BLE, safety, seal, and no-query/no-command boundaries. |
| Typed private SDK observations | `TuyaStructuredApplicationEvidence.swift` — canonical, type-preserving Tuya SDK application observations with pseudonymous session identity, connection generation, delivery sequence, monotonic/wall receipt, closed recursive value types, deterministic JSON, replay checks, and permanent `rawTransportBytesAvailable=false` / no-telemetry-authority boundaries. Encoded events can still contain sensitive SDK payload strings and belong only in private custody until an explicit sanitizer derives a reviewed fixture. |
| Guided stationary action windows | `ES80GuidedCapturePlan.swift` — an observation-only mode/headlight/brake plan with exact before/during/after receipts, retained duplicate observations, non-operator baseline/recovery completion, mandatory operator confirmation for each still-unmapped action, bounded receipt accumulation, and terminal disconnect/background/import continuity breaks. Arbitrary payload churn cannot prove an action or auto-advance it. Charger transitions and wheel motion remain deferred to separate safety procedures. |
| Field authorization foundation | Historical `PassiveBluetoothCaptureFieldAuthorization.swift` remains non-authorizing for the current procedure. New `AuthenticatedStationaryCaptureFieldAuthorization.swift` plus `es80_signed_field_artifact_evidence.py` / `es80_field_authorization_envelope.py` define a current-procedure single-attempt challenge/expiry/replay contract with exact runtime and retained-evidence binding. Its production trust anchor is deliberately `nil`, no app adapter consumes its opaque capability, and no device can be reached through it. |
| Standalone app and QA | `NembraApp/App/NembraCaptureEntrypoint.swift`, `NembraApp/App/NembraCaptureBuildIdentity.swift`, `NembraApp/App/NembraCaptureSimulatorQAHarness.swift`, `NembraCaptureUITests/NembraCaptureUITests.swift`, `.github/workflows/capture-v16-standalone.yml`, `.github/workflows/capture-standalone-visual-evidence.yml`, and `.github/workflows/capture-field-build-provenance.yml`. |
| Truthful production fallback | `Packages/NembraCore/Sources/NembraCore/UnverifiedScooterService.swift` remains disconnected/unsupported, emits no telemetry, and rejects every scooter command until verified mappings exist. |

## Physical and fixture inventory

| Evidence ID | Classification | What it proves | What it does not prove | Repository custody |
| --- | --- | --- | --- | --- |
| `C7D09A22` | Accepted physical transport evidence | Tuya FD50 service/topology, Tuya manufacturer prefix, 17/17 completed historical scenarios, notification subscription, 15 peripheral disconnects, zero application payloads, and an observed mean connected interval of about 29.930 seconds. | Durable scooter identity; authenticated session; raw application payloads; DP IDs; telemetry meaning; framing; scale; units; cadence; command acknowledgement or write safety. | Only the Git-safe code ledger and human summary are retained. The raw/private source artifact is not tracked in Git and cannot be reconstructed from the summary. |
| Public/synthetic Capture fixtures | Software-only | Deterministic lifecycle, export, corruption, safety, provenance, UI, and accessibility behavior. | Physical ES80 behavior, account ownership, RF delivery, SDK authentication, or any semantic mapping. | Tracked tests and hosted CI artifacts. |
| Authenticated P0 session | **Not collected** | Nothing yet. | All application/DP and semantic facts. | No accepted artifact exists. |

There is no GitHub-safe physical packet or DP fixture that can authorize a production ES80 decoder today.

## Current P0 secure-link gate

The only authoritative next physical gate is `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`. It is stationary, foreground-only, charger-disconnected, and read-only:

- use the official SmartLife SDK account method that owns the exact scooter;
- prove current same-account exact-device membership;
- complete and explicitly confirm fresh four-window target correlation;
- retire direct CoreBluetooth ownership before the official SDK owns authenticated BLE;
- send no Nembra DP query, scooter command, unknown characteristic write, unbind/reset, or OTA request;
- require Tuya local BLE observably online, at least two non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate` callbacks, the latest at least 30 seconds after authentication, and at least 45 seconds of accepted authenticated observation;
- seal/share an artifact that states `rawFD50BytesCaptured=false`, `dpQueriesSent=false`, and `dpCommandsSent=false`.

This P0 establishes only a legitimate supported application-level observation channel. It does not map a DP or make a structured SDK value into a raw FD50 notification.

### P0 blockers

1. **Field authority is intentionally impossible in the current app.** `NembraCaptureBuildIdentity.isAuthoritativeFieldBuild` is hard-coded `false`; therefore even an app produced by the current private installer cannot begin `OFF1`. Preserve this fail-closed state. Do not replace it with a Boolean, plist flag, build setting, launch argument, or locally self-signed assertion.
2. The new current-procedure P-256 verifier/helper contract is not deployable yet: its independent production trust anchor is deliberately nil, no independently controlled production signer/GO key has been accepted for this candidate, and the app is not wired to durably consume `AuthenticatedStationaryCaptureAttemptCapability`. The software schema now binds exact source, dependency lock, build/runtime, evidence, procedure, challenge, expiry, and one replay-consumption request; those package/Python tests do not substitute for key review, app wiring, signed retained-IPA evidence, or physical proof. The historical `ES80-FINGERPRINT-v1` envelope remains procedure-stale and non-authorizing.
3. The private user-owned Tuya configuration/security component, intended account session, exact scooter membership, signed install, and intended iPhone are necessarily outside public CI and have not been accepted for this head.
4. No physical authenticated P0 artifact exists. Public/synthetic greens cannot close this gap.
5. The current SDK callback is sanitized into `[String: String]` through `String(describing:)`. It is deterministic and secret-aware but not lossless or type-preserving, so it is insufficient for the Capture 1.0 machine-readable mapping outcome.
6. Official-SDK ownership currently exposes structured `dpsUpdate` values, not raw authenticated FD50/ATT bytes. Opening a second CoreBluetooth connection is forbidden. Raw authenticated bytes remain unavailable unless a supported same-session source is later proven; this limitation must remain explicit rather than relabeling SDK values.
7. The installer now validates exact retained input paths/hashes/modes and stops unconditionally before its unreachable legacy Debug rebuild/device-install block. It cannot install until a reviewed workflow install manifest and app authorization adapter cross-bind every retained subject. The dead legacy block must be deleted when that replacement lands, not re-enabled.
8. The signer/evidence helpers named by the trusted workflow now exist and pass local focused tests, but the workflow has not yet produced or cross-verified a real current-procedure retained artifact set on this head. Production private key custody remains external; no key, signed private IPA, authorization envelope, or raw evidence belongs in Git.

## P1 stationary-mapping gap

P1 begins only after a genuine P0 pass. It does not yet exist as a complete product flow.

- The package now defines the versioned private typed-observation domain in `TuyaStructuredApplicationEvidence.swift`, but the standalone app still emits lossy `[String: String]` projections and does not adapt real `dpsUpdate` values into it.
- The package now defines the conservative one-action-at-a-time receipt plan in `ES80GuidedCapturePlan.swift`, but no app coordinator drives its observation-window policy, prompts, evidence digests, interruption export, or UI progression yet. An imported unfinished plan is inspection-only and terminalized at the process boundary; it can never resume the prior chronology.
- No P1 artifact combines the accepted P0 prefix, typed observations, action markers, contradictions, source/build/session provenance, a human summary, and a machine-verifiable protocol-map claim set.
- No public import/verifier exists for an authenticated P1 bundle. The app-private schema-v13 P0 decoder only validates its own sealed export path.
- No accepted physical DP mapping, Git-safe semantic fixture, production decoder, or reconnect/stale/impossible-value policy exists.
- App termination cannot truthfully continue a process-uptime chronology. A canonical artifact may be inspected or re-shared, but an interrupted live attempt must restart as an explicitly new generation/session rather than splice evidence across relaunch. Guided-plan hashes provide deterministic identity, not signature or independent authenticity; a later bundle verifier must cross-check every receipt against the retained typed event stream.

Physical actions beyond the P0 untouched baseline—including mode, light, brake, charger transition, wheel motion, throttle, or riding—remain unauthorized until a reviewed P1 recipe defines safety, observable boundaries, and stop behavior. Commands sent by Nembra remain unauthorized independently of whether the same action is available on the scooter or in the stock app.

## Raw GATT versus SDK application evidence

- **Direct passive CoreBluetooth:** `PassiveBluetoothCaptureJSON` can preserve exact advertisement/service data and exact characteristic callback `Data` with service UUID, characteristic UUID, origin, sequence, receipt uptime, wall date, connection state, and interruption boundaries. This is raw GATT evidence only while Nembra owns that connection.
- **Official SmartLife SDK:** `ThingSmartDeviceDelegate.dpsUpdate` is already decoded above GATT by Tuya. The current export stores sanitized string projections; a future typed representation can be lossless for supported SDK values but will still be application-level evidence. It cannot supply transport characteristic identity, fragmentation, ciphertext, byte offsets, or endianness.
- **One-owner rule:** direct CoreBluetooth target correlation must retire before authenticated SDK BLE begins. Never run a competing connection merely to obtain bytes.

## Exact CI snapshot

Queried on 2026-08-19 PDT / 2026-08-20 UTC.

### Consolidation implementation `b16cec4c437b848339bd5b154ed43edf66220b2b`

- Base `9659fbbed…` files: `AuthenticatedStationaryCaptureFieldAuthorization.swift` and its test; `es80_signed_field_artifact_evidence.py`; `es80_field_authorization_envelope.py`; their focused Python test; `TuyaFieldInstallerRetainedIPAAdmissionSourceTests.swift`; and `scripts/field/install_one_time_capture.command`. Follow-up `6d3a6f78…` caps expiry from attempt start and replaces absent historical test references in `.github/workflows/capture-xcode27-trusted-command.yml`; `b16cec4c4…` repins the TODAY trust-subject workflows to that exact new workflow blob.
- Focused local evidence: SwiftPM 14/14 in 2 suites; Python 13/13 across the new authorization and existing signer-custody suites; trusted pin/subject/Final-GO suites 22/22; both helper self-tests; installer syntax/self-test; three Swift parsers; exact workflow-blob equality; diff/whitespace/secret scans. No local Xcode, signing, device contact, BLE, private key, or physical run occurred.
- Exact-head `b16cec4c4…` workflows were newly dispatched: V16 `32326067450`, visual `32326067536`, field provenance `32326067466`, Xcode 27 Simulator `32326067473`, TODAY preflight `32326067386`, TODAY Final GO `32326067439`, and trusted-workflow pin/process/build/index custody `32326067492` / `32326067426` / `32326067430` / `32326067462` were pending or in progress. PR exact-head `32326067397` was skipped by policy. A new owner must inspect their terminal results.
- The preceding `cb00ee46a…` V16 run `32321917923` failed 1 of 13 UI tests at `NembraCaptureUITests.swift:309`: the compact-landscape correlation confirmation control did not become hittable after bounded scroll attempts. Artifact `9390495057`, digest `sha256:4a4922697e6a009aea09494b159e845d35453da97542e1617c7130afbaa984ee`. This remains an unresolved reachability blocker, not permission to weaken the assertion.
- Physical status remains **NO-GO**. The production trust root is nil, app consumption wiring is absent, the installer stops before device work, and there is no authenticated P0 artifact.

### Implementation head `5c32d29d5327e4c54d0f3a70b548da6eeeb537a5`

- Local focused evidence: root-owned combined SwiftPM passed 33/33 tests in the typed-event and guided-plan suites; the component runs passed 12/12 and 21/21. Four new Swift files parse, whitespace/diff/secret checks are green, and an independent post-fix adversarial audit returned GO. This is not Xcode 27 or physical evidence.
- [Capture TODAY Final GO QA `32321764453`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764453) and [TODAY Field Candidate Preflight `32321764641`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764641): **green software contracts only**; neither authorizes physical Capture.
- [Capture V16 Standalone Exact-Head `32321764574`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764574), [Capture Standalone Visual Evidence `32321764568`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764568), and [Capture Field Handoff Provenance `32321764666`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764666) were still running when this update was prepared.
- [Xcode 27 Simulator QA `32321764484`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764484) was queued. [Xcode 27 PR Exact-Head QA `32321764522`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764522) was skipped by its event/admission policy.

### Remote head `3f0814ac70211f68b7af1a6913c78c91a810f663`

- [Capture V16 Standalone Exact-Head `32315926223`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315926223): **green**; 84 scoped Swift tests, 9 Python handoff tests, build/product verification, and 13/13 iPhone 12/iOS 27 UI tests. Artifact `nembra-capture-synthetic-ui-3f0814ac70211f68b7af1a6913c78c91a810f663`, ID `9388386960`, digest `sha256:dbf8a04f668f199e66f6cea9ad79da9444c4a89b0f2f1e38a6d427934bce3f65`.
- [Capture Standalone Visual Evidence `32315926201`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315926201): **green**. Artifact `nembra-capture-standalone-visual-3675-1`, ID `9388184207`, digest `sha256:3428770ac4077ac79d2109f7defe318d53fe18f65fd7d079a1933e669ae961e4`.
- [Capture Field Handoff Provenance `32315926220`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315926220), [TODAY Field Candidate Preflight `32315926193`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315926193), and [TODAY Final GO QA `32315926207`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315926207): **green software contracts only**; none authorizes physical Capture.
- [Xcode 27 Simulator QA `32315926225`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315926225): workflow **green**, but only the change-admission job ran; the full build/test/capture job was skipped for this continuity-only delta. [Xcode 27 PR Exact-Head QA `32315926222`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32315926222) was skipped.

### Implementation head `0b7e3b27de5e9b547911558ae8ed4cb852becb59`

- Capture visual `32315523022`, field provenance `32315522998`, TODAY preflight `32315522997`, and TODAY Final GO `32315523032` were green.
- Capture V16 `32315522994` was **cancelled** while its 13-test UI stage was running after compile, 84 Swift tests, 9 Python tests, standalone build, and product verification had passed. It produced partial artifact `9388047422`. The replacement `3f0814ac…` V16 run above completed green; the cancellation is not a physical or semantic verdict.
- Product Xcode 27 run `32315523013` was **cancelled** during the app build/test/capture step after Core validation passed; artifact `9388066185` retains partial logs. The `3f0814ac…` admission-only run did not rerun that full product gate, so product-wide exact-head acceptance remains separate from the green Capture lanes.

## Privacy and custody

- Never commit AppKey/AppSecret, account or identity tokens, verification codes, Tuya device IDs, account UIDs, CoreBluetooth peripheral UUIDs, local keys, session keys, private security components, provisioning profiles, signed private IPAs, logs containing those values, or raw sensitive field artifacts.
- The short evidence label `C7D09A22` is safe provenance. Do not copy its historical peripheral identity into a new artifact or use it as current target authority.
- Share physical exports privately and preserve their exact bytes. Keep them under the ignored `CaptureEvidencePrivate/` root or the reserved `.nembra-capture-evidence.json` / `.nembra-capture-evidence.ndjson` names. Commit only reviewed sanitized summaries, digests/provenance, and the smallest deterministic derived fixtures needed to test an accepted mapping; renaming raw evidence does not make it safe for Git.
- The private source artifact preserves every supported typed value exactly; unsupported runtime types must produce an explicit diagnostic rather than a string projection. Redaction belongs only in the separately derived Git-safe fixture, must record what class of value was removed, and must never create a misleading semantic substitute.

## Exact next code batches

1. **Unified-owner authorization review:** verify remote head and rerun the focused Swift/Python suites named above. Review the compact sorted Swift/Python wire contract and external signing custody together. Arrange independent private-key custody; only after review, pin the matching public P-256 X9.63 bytes. Never commit the private key or let an envelope/plist/caller choose the trust root.
2. **App capability and exact install:** add an app-owned atomic ThisDeviceOnly Keychain consumption store, then pass the opaque capability through every OFF1/authentication/connection/seal boundary. Define the trusted install-manifest cross-binding, delete the unreachable legacy installer block, and install only the exact retained accepted signed IPA. Keep `isAuthoritativeFieldBuild` false; no Boolean/plist/environment shortcut.
3. **Compact-landscape closure:** inspect V16 artifact `9390495057` and fix the confirmation control's real scroll/layout reachability while preserving the final hittability assertion. Run all exact-head hosted Xcode 27 Capture lanes before any physical GO claim.
4. **App adapter and private journal:** losslessly classify supported `dpsUpdate` key/value runtime types into `TuyaStructuredApplicationEvidenceEvent`, fail closed with an explicit diagnostic for unsupported values, and atomically append exact canonical bytes before UI publication. Never relabel application observations as raw FD50 bytes.
5. **P1 coordinator/bundle/claims:** drive `ES80GuidedCapturePlan` from the accepted typed stream, export exact private bytes plus a human summary, cross-verify on import, derive a reviewed repository-safe fixture, preserve contradictions/session IDs, and keep every claim `unknown`/`hypothesis`/`correlated` until repeatable evidence makes it `verified`.
6. **Fixtures and decoder promotion:** only after accepted physical evidence exists, implement `verified` mappings with stale/invalid/impossible-value tests. Update `docs/ES80_PROTOCOL_MAP.md`, both continuity files, and PR #3675; notify sibling workstreams only when a stable privacy-safe contract/fixture exists.

## Eventual one-time operator session

Do **not** execute this until the repository explicitly records GO and the app visibly verifies independent field authorization. The intended final experience is short:

1. Install the exact accepted signed Capture build through the canonical installer on the intended iPhone; authenticate with the actual SmartLife account that owns the exact scooter.
2. Leave the scooter stationary, initially off, and charger-disconnected. Follow the four automatic `OFF1 -> ON1 -> OFF2 -> ON2` prompts and confirm the single correlated target.
3. Start the official-SDK read-only P0 session, leave the scooter untouched, and wait for Capture to accept repeated application evidence beyond 30 seconds and authenticated continuity beyond 45 seconds.
4. Only if P0 passes, follow the separately reviewed P1 screen one physical action at a time. Do not improvise actions, ride, connect the charger, or send a command that the screen did not explicitly authorize.
5. Tap Share once and retain the exact sealed bundle. If the app stops, backgrounds beyond the accepted limit, loses authority, disconnects, or reports ambiguity, preserve any legitimate diagnostic export and restart as a new attempt instead of guessing.

Until batches 1–4 are complete and accepted, the exact user action is: **do not run physical Capture yet**.

## Provisional consumer boundary for sibling workstreams

Portrait and cockpit branches may inspect the following package contracts after this checkpoint, but they must not treat them as telemetry or a signed evidence authority. The raw types remain Capture-internal until the app adapter, bundle cross-verifier, and privacy-safe fixture boundary are reviewed:

- `TuyaStructuredApplicationEvidenceEvent` is private, unmapped Tuya SDK application evidence. `authorizesProductionTelemetry` is permanently false and `rawTransportBytesAvailable` is permanently false.
- `ES80GuidedCapturePlan` describes Capture-only operator/evidence progression and exposes no write/query/command authority.
- `docs/ES80_PROTOCOL_MAP.md` remains the sole semantic claim ledger; every production-consumable scooter field is still `unknown`.

No Home or cockpit UI should consume these raw evidence types. A later reviewed decoder contract and privacy-safe deterministic fixture will be announced here and in PR #3675 only after a mapping reaches `verified`.
