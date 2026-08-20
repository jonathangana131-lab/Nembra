# Nembra development continuity

Status: active recovery authority. Update this file after every meaningful checkpoint and before pausing, handing off, merging, or ending a development session.

## Resume protocol

Before changing code in a resumed task:

1. Read this file completely.
2. Read `docs/design-reference/horizon-v4-final/NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md` and `docs/NEMBRA_V2_PRODUCTION_FOUNDATION.md` completely.
3. Run `git status --short`, `git log -5 --oneline --decorate`, `git fetch origin`, and compare `HEAD` with the branch and PR head below.
4. Inspect the current PR and exact-head Actions results. Evidence from an ancestor SHA does not transfer to a newer head.
5. Continue the exact next action recorded below. Do not restart planning or revive rejected V2/V3 cockpit work.

This repository file is the recovery authority. Chat/task summaries are supplementary.

## Authoritative GitHub state

- Repository: `jonathangana131-lab/Nembra`
- Branch: `product/capture-1-0-main-20260818`
- Pull request: [#3675 — Finish Capture checkpoint and production Nembra surfaces](https://github.com/jonathangana131-lab/Nembra/pull/3675)
- PR base: `main`
- PR state: draft until all exact-current-head acceptance gates below are green and inspected
- Latest pushed Capture implementation checkpoint recorded here: `b16cec4c437b848339bd5b154ed43edf66220b2b`
- Latest pushed continuity checkpoint preceding this update: `a7262317b864b95e38a3672adc511eb3a7cfe2d7`
- Recovery rule: after cloning, run `git rev-parse HEAD` and `git ls-remote origin refs/heads/product/capture-1-0-main-20260818`; if either is newer than the recorded checkpoints, inspect those commits and update this file before development.

The file cannot self-embed the SHA of the commit containing its own changed bytes. Therefore the SHAs above name the latest pushed implementation and meaningful continuity checkpoints this document has audited; the remote branch HEAD is the authority for any later continuity-only commit.

## Current focused aspect and production acceptance gate

The integration branch still carries the complete Nembra 1.0 objective, but implementation ownership is now deliberately split:

1. **Nembra Capture 1.0 software checkpoint** — safe, fail-closed, one-time Bluetooth evidence utility. Software acceptance requires exact-head Capture source/provenance suites, standalone public/synthetic UI matrix, iPhone 12/iOS 27 visual evidence, artifact custody, and truthful nonphysical authority boundaries. Physical/private status remains **NO-GO** until the separate documented intended-account/intended-scooter field procedure has authorized prerequisites and a real device run.
2. **Portrait Home and menus** — owned by the isolated Codex task `01a01c57-b619-7262-8971-ba9044659a29`. The root branch does not duplicate that implementation. Its PR is an integration input and must preserve the selected Home truth/accessibility/performance contracts.
3. **Landscape cockpit and feature lab** — owned by the isolated Codex task `01a01c57-590f-7c21-8071-39e8bfdd78e8`. Horizon V4 remains requirements-only and visually rejected. The user-approved post-V4 direction is the Energy Chamber family recorded under `docs/design-reference/horizon-post-v4-studies/`; its live-power gauge and typography still require redesign and exact Xcode 27 proof.

The root task was the dedicated **Capture + Bluetooth truth** workstream and integration owner. It is now stopped at the fail-closed authorization checkpoint below for user-authorized consolidation. A new unified owner must resume from the exact action in this file; no visual sibling branch should absorb or reinterpret raw Capture evidence.

The current focused production gate is the current-procedure field-authorization and private-evidence path: an exact retained GitHub-hosted Xcode 27 signed IPA, short-lived single-use externally signed P-256 authorization bound to an app-generated attempt challenge and `ES80-AUTHENTICATED-STATIONARY-v1`, lossless real `dpsUpdate` journaling, cross-verified export/import, and a stationary user flow that cannot begin OFF1 or send a write without the verified opaque attempt capability. Until that chain and a real intended-iPhone/intended-ES80 run exist, physical Capture remains **NO-GO**.

The current Home screenshot is a functional checkpoint only and is explicitly **not visually accepted**. Home visual acceptance additionally requires one fresh exact-head Xcode 27 iPhone 12 screenshot placed side-by-side with `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png` and proving all of the following together:

- a dimensional battery instrument with fine SOC-clipped ribs/micro-lines, gold gradient/highlight, deep graphite empty region, metallic rim/inner depth, and terminal detail;
- refined SF battery/range typography with state-appropriate contrast and hierarchy for learned, unavailable, low, reconnecting, and retained/stale states;
- a provenance-documented, high-resolution, truthful ES80 side render with premium graphite material/lighting and no invented/counterfeit geometry;
- zero intersection between the scooter and percentage, range/unavailable copy, status text, or accessibility content in every deterministic state;
- separate tire contact shadows, a longer deck shadow, ambient occlusion, restrained warm under-deck light, and a believable floor/reflection plane;
- native Liquid Glass depth/specular/environmental response on actual interactive controls/actions and the system floating tab bar, without glass-coating telemetry or passive content;
- one integrated lighting scene: warm energy light may influence the scooter, floor, contact shadows, and nearby functional glass edges while primary information stays white, secondary information cool grey, connection health green, and energy/active state gold.

Do not merge PR #3675 or claim either aspect complete until the latest remote head—not an ancestor—meets these gates.

## Completed and pushed work

The current pushed implementation checkpoint includes:

- Capture authority, provenance, immutable artifact sealing/validation, recoverable sharing, public/synthetic UI, field handoff and exact-head workflows under `NembraApp/App/NembraCaptureEntrypoint.swift`, `Packages/NembraBluetoothCapture/`, `NembraCaptureUITests/`, `Scripts/`, `.github/workflows/`, and the canonical Capture docs.
- Selected portrait Home/Rides/Vehicle/Settings implementation under `NembraApp/Features/Home/`, `NembraApp/App/AppRootView.swift`, and `NembraApp/Features/Settings/`, with selected references under `docs/design-reference/nembra-1.0-gold-glass/`.
- Existing cockpit functional implementation, exact-scene orientation ownership, idle animation shutdown, and product performance harness under `NembraApp/Features/Dashboard/`, `NembraApp/App/DashboardSessionStore.swift`, `NembraUITests/`, `scripts/ci/xcode27_product_simulator_capture.sh`, `scripts/ci/validate_xcode27_dashboard_performance.py`, and `.github/workflows/xcode27-simulator.yml`. Its current visuals are not 1.0 acceptance.
- Automatic-capture readiness/candidate journal, crash-safe daily ride segments, ride history/route persistence, and road-exploration provenance foundations under `Packages/NembraCore/Sources/NembraCore/` and their focused tests.
- Horizon functional/state requirements under `docs/design-reference/horizon-v4-final/NEMBRA_HORIZON_V4_PRODUCTION_HANDOFF.md`; V2/V3/V4 cockpit PNGs are rejection/history evidence only.

Checkpoint `5c32d29d…` establishes the first Capture/Bluetooth-truth foundation without promoting any scooter semantic:

- `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaStructuredApplicationEvidence.swift` defines lossless typed Tuya SDK application observations with fresh pseudonymous session identity, connection generation, delivery sequence, monotonic and wall receipts, closed recursive values, canonical JSON, replay validation, event/payload SHA-256 identities, and a 1 MiB canonical boundary. It permanently states `rawTransportBytesAvailable=false` and `authorizesProductionTelemetry=false`; private strings remain exact and therefore Git-sensitive.
- `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ES80GuidedCapturePlan.swift` defines a bounded, observation-only mode/headlight/brake before/during/after plan. It retains repeated receipts, accepts only typed events at the live mutation boundary, caps each window at 2,048 receipts and canonical plans at 8 MiB, requires explicit operator confirmation while fields are unmapped, rejects zero chronology, and makes decoded unfinished state inert/terminal across process import. It exposes no query/write/firmware/command authority. Charger transition and wheel motion remain deferred to separate safety procedures.
- Exact focused tests live in `Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaStructuredApplicationEvidenceTests.swift` and `ES80GuidedCapturePlanTests.swift`.
- `docs/CAPTURE_BLUETOOTH_CONTINUITY.md` is the dedicated recovery/evidence ledger. `docs/ES80_PROTOCOL_MAP.md` is the sole semantic claim ledger; every production-consumable ES80 field remains `unknown`.
- `.gitignore` excludes known Capture bundles, the dedicated private evidence root, reserved `.nembra-capture-evidence.json` / `.ndjson` exports, signing material, provisioning material, and private dependency workspaces. Renaming sensitive evidence never makes it safe to commit.

Local proportional evidence for `5c32d29d…`: the root-owned combined SwiftPM run passed **33/33 tests in 2 suites**; the focused guided suite passed 21/21 and typed evidence suite passed 12/12; all four new Swift files parse; tracked/untracked whitespace and cached diff checks pass; secret/private-path scan is clean; and a final independent read-only adversarial audit returned GO after imported-state, arbitrary-change auto-advance, receipt-minting, chronology, and resource-bound fixes. This is package/static evidence only; GitHub-hosted Xcode 27 remains build/release authority.

Checkpoint `9659fbbed363ea7a0b85c19379d2bd7aa181ec7b` preserves the next field-authorization unit without unlocking a device:

- `Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/AuthenticatedStationaryCaptureFieldAuthorization.swift` defines the current `ES80-AUTHENTICATED-STATIONARY-v1` closed envelope/payload schema, exact runtime/build/dependency/evidence/pseudonym bindings, package-generated process-local challenge, 15-minute maximum validity, wall/monotonic divergence checks, app-owned atomic replay-consumption boundary, and opaque non-Codable one-OFF1 capability. The production P-256 trust anchor remains deliberately `nil`; `verifyForCurrentApplication` therefore fails closed.
- `scripts/ci/es80_signed_field_artifact_evidence.py` and `scripts/ci/es80_field_authorization_envelope.py` produce and verify deterministic offline evidence/envelopes with the same compact sorted JSON wire contract, external mode-0600 private-key custody, P-256 signing, bounded inputs, no production-key generator, and no-replace mode-0600 output. They grant software authority only and never establish BLE, scooter, or physical truth.
- `scripts/field/install_one_time_capture.command` now validates seven exact retained subjects by absolute no-follow path, ownership/mode/size, stable descriptor identity, and SHA-256. It then stops unconditionally before every legacy rebuild/device-install statement. The unreachable legacy block remains only as explicitly recorded WIP pending the install-manifest contract.
- Focused regressions live in `AuthenticatedStationaryCaptureFieldAuthorizationTests.swift`, `TuyaFieldInstallerRetainedIPAAdmissionSourceTests.swift`, and `test_es80_authenticated_stationary_offline_authorization.py`.

Proportional local evidence for `9659fbbed…`: focused SwiftPM passed **14/14 tests in 2 suites**; Python authorization plus existing custody suites passed **13/13**; both Python helper self-tests passed; installer `bash -n` and `--self-test` passed; all three new Swift files parse; cached diff, whitespace, and targeted secret scans are clean. This is local package/static evidence, not Xcode 27, signed-install, or physical evidence.

Follow-up `6d3a6f78abe6ec87455fd49f193edbe53ba6ef35` closes the last live-attempt bound discovered before consolidation: envelope expiry must also remain within 15 minutes of the app attempt start, not merely within 15 minutes of signer issuance. Its regression is included in the same 14/14 focused result. It also updates `.github/workflows/capture-xcode27-trusted-command.yml` to execute the new authenticated-stationary test instead of two absent historical test paths.

Follow-up `b16cec4c437b848339bd5b154ed43edf66220b2b` repins the two TODAY custody workflows and `es80_today_trusted_capture_xcode_subject.py` to the exact new trusted-workflow blob `d55801aaa70c494e70c9ceed7fd52b0fbd08f3ae`. The pin, trusted-subject, and Final-GO hardened suites passed 22/22 locally; the pinned hash equals `git hash-object .github/workflows/capture-xcode27-trusted-command.yml`.

Checkpoint `0b7e3b27…` closes the exact `cf817a8b…` integration failures without beginning new portrait or cockpit feature work:

- `NembraApp/Features/Home/HomeView.swift` removes compounded dimming from retained percentage and adaptive-range qualifier text while preserving explicit retained/currentness semantics.
- `NembraApp/App/AppRootView.swift` removes shared labeled-pair identities from both `ViewThatFits` timeline alternatives so Xcode audits the visible native semantic-font `Text` nodes in title-then-timestamp order.
- `NembraUITests/NembraUITests.swift` makes the deterministic landscape screenshot terminal in its fixture, then strengthens the separately passing battery-hitch test to prove the real Home control restores portrait and removes the cockpit. This avoids the evidenced hosted-XCUI post-screenshot animation-idle deadlock without disabling motion, raising timeouts, or weakening product assertions.
- Focused source contracts are updated under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift` and `RideWindowNavigationClearanceSourceTests.swift`.
- `docs/design-reference/horizon-post-v4-studies/` preserves four original `1844 × 853` studies with hashes and generation provenance. The user selected the Energy Chamber material/composition family; its ambiguous/fabricated live-power scale, NOW locator, and generic typography are explicitly rejected pending redesign. The one-value battery contract remains percentage **or** range inside the same battery while SOC fill always means charge.

Proportional local evidence for `0b7e3b27…`: all five changed Swift files parse; `git diff --check` passes; focused Home/Ride source tests pass 4/4; secret/path scan is clean; and a diagnostic local generic-iOS-Simulator `build-for-testing` exits 0 for app, unit-test, and UI-test targets. Local Xcode 26.1 is compile evidence only, never release authority.

Checkpoint `1095f367…` specifically fixes the steady-state Dashboard animation/idleness timeout and Ride-window timeline accessibility semantics:

- `NembraApp/Features/Dashboard/SpeedInstrumentModel.swift`
- `NembraUITests/NembraUITests.swift`
- `NembraApp/App/AppRootView.swift`
- `Packages/NembraCore/Tests/NembraCoreTests/RideWindowNavigationClearanceSourceTests.swift`

Checkpoint `a381a30f…` implements the first focused Home energy-material correction without claiming visual acceptance:

- `NembraUITests/NembraUITests.swift` terminates the intentionally continuous render-stress fixture after its preserved 3×6-second measurement, post-update proof, QA screenshot, and metrics rather than waiting for impossible XCUI animation quiescence. Independent exact-scene portrait restoration coverage remains unchanged.
- `NembraApp/App/AppRootView.swift` gives the explicit read-only Ride timeline label/value node the full existing padded-row accessibility focus shape without adding a button trait or changing layout.
- `NembraApp/Features/Home/HomeView.swift` adds a synchronous, input-driven engineered battery Canvas with truthful SOC fill, SOC-clipped graphite copy well, gold/red dimensional fill, fine clipped ribs, metallic shell/rim/terminal, state-aware typography/contrast, early large-text reflow, a measured current-asset copy corridor, and separate blurred tire/deck/ambient/gold/floor grounding layers. It shortens the standard hero to restore populated-row/tab clearance and applies native glass only to the actionable saved-ride continuation.
- `NembraApp/DesignSystem/NembraVisuals.swift` uses a stable dark Nembra fallback and boundary under Reduce Transparency/Show Borders rather than an adaptive light surface that could erase white glyphs.
- `NembraUITests/NembraUITests.swift` adds standard accessibility auditing (including contrast), explicit Accessibility XXXL reachability/screenshots, and retained/low-battery contrast audits.
- Focused source contracts are updated under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityControlLayoutSourceTests.swift`, `HomeAccessibilityMetricLayoutSourceTests.swift`, and `RideWindowNavigationClearanceSourceTests.swift`.

Historical checkpoint `245fb44a…` closed the five exact Xcode 27 accessibility failures in run `32306810002` without weakening the audits. Its labeled-pair timeline approach was later superseded by `0b7e3b27…` after exact Xcode 27 exposed an inactive-candidate audit failure:

- `NembraUITests/NembraUITests.swift` now launches Accessibility XXXL with UIKit's actual raw category identifier, `UICTContentSizeCategoryAccessibilityXXXL`; the prior expanded Swift-symbol spelling was read but did not activate the larger layout.
- `NembraApp/Features/Home/HomeView.swift` removes compounded numeric opacity, retains truthful stale/range de-emphasis, uses a higher-contrast semantic low-battery red, and adds one restrained specular boundary around the native-glass Vehicle Controls button.
- `NembraApp/App/AppRootView.swift` replaces the synthetic Ride timeline accessibility node with native scaling `Text` elements associated through `accessibilityLabeledPair`, while preserving `ViewThatFits`, timestamp truth, and the 72-point navigation-launcher clearance.
- Focused source regressions remain under `Packages/NembraCore/Tests/NembraCoreTests/HomeAccessibilityMetricLayoutSourceTests.swift` and `RideWindowNavigationClearanceSourceTests.swift`.
- `docs/design-reference/nembra-1.0-gold-glass/runtime-evidence/` retains the exact b319 selected-vs-runtime comparison and its explicit non-acceptance record so this visual diagnosis survives artifact expiry.

Local proportional evidence for `245fb44a…`: all five changed Swift files parse; `git diff --check` passes; Home source tests pass 5/5; Ride Window source test passes 1/1; a diagnostic generic-Simulator app build exits 0 under local Xcode 26.1; and an adversarial scope/secret audit is green. This local result is compile evidence only, not release authority.

## Work in progress

No intentional implementation or evidence change is local-only after `b16cec4c437b848339bd5b154ed43edf66220b2b`; that implementation commit is pushed and `git ls-remote` verified. This document is the continuity-only consolidation follow-up and will be pushed separately; because it cannot contain its own commit SHA, the remote branch HEAD is the recovery authority as described above.

The typed observation and guided plan are package foundations only. They are not yet wired into `NembraCaptureEntrypoint`, durable private storage, the P0/P1 export bundle, a sanitizer, protocol-claim cross-verification, or a production decoder. No physical session or semantic fixture exists, and no sibling UI branch should consume these raw types.

The current root Capture/Bluetooth lane is stopped for consolidation. The authorization foundation is committed and pushed, but it is intentionally not app-wired and cannot authorize OFF1. The next unified owner must review the software wire/custody chain, add the independently controlled public trust root and app-owned consumption adapter, replace the installer's unreachable legacy block only after a closed install manifest exists, and then run hosted Xcode 27. Portrait task `01a01c57-b619-7262-8971-ba9044659a29` and cockpit task `01a01c57-590f-7c21-8071-39e8bfdd78e8` retain their isolated UI ownership.

## Exact CI and retained evidence

The current implementation checkpoint is exact `b16cec4c437b848339bd5b154ed43edf66220b2b` (authorization foundation `9659fbbed…`, live-attempt/workflow follow-up `6d3a6f78…`, and trusted-subject repin):

- Exact-head `b16cec4c4…` workflows were newly dispatched at consolidation: V16 `32326067450`, visual `32326067536`, field provenance `32326067466`, Xcode 27 Simulator `32326067473`, TODAY preflight `32326067386`, TODAY Final GO `32326067439`, and the trusted-workflow pin/process/build/index custody lanes `32326067492`, `32326067426`, `32326067430`, and `32326067462` were pending/in progress. Their terminal results do not exist yet and must be inspected before relying on this head.
- [`Xcode 27 PR Exact-Head QA` run `32326067397`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32326067397) was skipped by its event/admission policy.

The immediately preceding continuity head `cb00ee46a0fe3ecc53b7143fb61939615102919b` had green TODAY, field-provenance, standalone-visual, and admission-only Xcode workflows, but V16 run [`32321917923`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321917923) was genuinely red: 12/13 UI tests passed and `testSyntheticCorrelationToObservationFitsCompactLandscape` failed at the final `waitForHittable` assertion for the confirmation control after bounded scroll attempts. Its retained artifact is `nembra-capture-synthetic-ui-cb00ee46a0fe3ecc53b7143fb61939615102919b`, ID `9390495057`, digest `sha256:4a4922697e6a009aea09494b159e845d35453da97542e1617c7130afbaa984ee`. Visual artifact `9390242263` has digest `sha256:3574059741e1c4e2f5ac0dccc5952ef77841ff763e5c9b5ac122a8606b4848ab`. This ancestor failure is an unresolved UI-test/product-reachability blocker, not physical evidence and not silently waived by the new authorization code.

The current implementation checkpoint is exact `5c32d29d5327e4c54d0f3a70b548da6eeeb537a5`:

- [`Capture TODAY Final GO QA` run `32321764453`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764453): green software-contract authority only.
- [`Capture TODAY Field Candidate Preflight QA` run `32321764641`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764641): green software-contract authority only.
- [`Capture V16 Standalone Exact-Head` run `32321764574`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764574), [`Capture Standalone Visual Evidence` run `32321764568`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764568), and [`Capture Field Handoff Provenance` run `32321764666`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764666) were in progress when this continuity update was prepared; record their terminal results/artifacts in both continuity ledgers before relying on them.
- [`Xcode 27 Simulator QA` run `32321764484`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764484) is queued. [`Xcode 27 PR Exact-Head QA` run `32321764522`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32321764522) was skipped under its event/admission policy.

The latest completed Capture baseline is exact `3f0814ac70211f68b7af1a6913c78c91a810f663`: V16 `32315926223` passed 84 Swift checks, 9 Python checks, and 13/13 iPhone 12/iOS 27 UI tests with artifact `9388386960`, digest `sha256:dbf8a04f668f199e66f6cea9ad79da9444c4a89b0f2f1e38a6d427934bce3f65`; visual run `32315926201` passed with artifact `9388184207`, digest `sha256:3428770ac4077ac79d2109f7defe318d53fe18f65fd7d079a1933e669ae961e4`; field/TODAY lanes were green. These remain simulator/software evidence and do not authorize physical Capture.

The latest completed baseline is exact `cf817a8b1c1f74640055af317671497a202e4f74`; its evidence is root-cause context only and does not transfer to `0b7e3b27…`:

- All five Capture lanes were **green**: TODAY preflight `32310420811` (53/53), Final GO contracts `32310421001` (73/73), field provenance `32310420850` (12 Python + 39 Swift), standalone visual `32310420920` (artifact `9386365261`, digest `1f83a866c52bf7ff74def59728805c2a0ade8f04e86dc9236d4e6729d1ab93c2`), and V16 `32310420859` (84 Swift + 9 Python + 13/13 UI; artifact `9386603633`, digest `0265b7884a329610ce7fcd4c8e6297ba3f0943662fa5fb2c187fe6bdbfa6afea`). These prove software/simulator contracts only and do not authorize physical/private Capture.
- [`Xcode 27 Simulator QA` run `32310434323`](https://github.com/jonathangana131-lab/Nembra/actions/runs/32310434323) was a genuine exact-head **red** run: Core 1,355/1,355 and app/unit 76/76 passed; UI 17/22 passed.
- Its five final failures were connected-Home contrast, low-battery qualifier contrast, retained percent contrast, Ride timeline Dynamic Type, and one Dashboard post-screenshot animation-idle timeout. The sustained Debug render test passed three approximately six-second clock samples, but no Hitch Time Ratio was emitted; Debug red prevented direct screenshots and the separate Release performance lane.
- Artifact `9386781377`, digest `a51913e14e2ce7ed62bc4606be15819d894046e222e0cfad8544d6b8cbecc519`.

## Known blockers

### Code/CI work

- Monitor and record exact `b16cec4c4…` Capture/Xcode 27 terminal results. Only hosted Xcode 27 is release authority; package greens do not prove the standalone app consumes the new contracts. Separately diagnose the `cb00ee46a…` compact-landscape confirmation-control reachability failure without weakening the hittability contract.
- Complete the new `ES80-AUTHENTICATED-STATIONARY-v1` field-authorization chain. The closed verifier and offline helpers now exist, but the production trust anchor is nil, no app-owned durable consumption adapter is wired, the hard-false build gate remains, and the retained-IPA installer stops before all device work because the trusted install manifest/cross-binding contract is absent.
- Wire the accepted typed SDK event into an atomic private journal and later bundle cross-verifier. Never use receipt hashes as signatures or application-level SDK values as raw FD50 bytes.
- Build the smallest app-owned guided coordinator and private export/import only after field authorization is fail-closed. Arbitrary payload changes cannot auto-confirm mode/light/brake until a verified correlation exists.
- Keep PR description/checklist synchronized with this file after each pushed checkpoint.
- Portrait Home/menu and cockpit implementation are owned by their two isolated tasks. Root must not overwrite those branches; integrate their PRs only after reviewing contracts, checks, and merge conflicts.

### GitHub/external

- Hosted `xcode-27` capacity can queue for roughly 30–90+ minutes. Queue delay is not a product failure.
- PR remains draft. It requires a final exact-current-head ready-for-review rerun before merge.

### User/physical Capture

- Physical Capture remains **NO-GO** without private Tuya provisioning/signing material, intended iPhone, intended SmartLife account, intended stationary charger-disconnected ES80, explicit current-attempt target confirmation, and execution of `ES80-AUTHENTICATED-STATIONARY-v1` by the authorized field operator.
- Do not commit private credentials, raw sensitive Capture output, device identifiers, or field artifacts.

### User/asset-rights

- Final Home 1.0 scooter artwork requires either a user-owned/commissioned high-resolution side photograph of the actual ES80 configuration or written AOVOPRO media/license permission for a specific high-resolution source. The existing 500×500 raster is useful for temporary layout but its exact original URL, transformation chain, license, and permission are not retained; do not AI-generate or upscale invented hardware detail.

## Exact next executable action

1. In a new unified-owner checkout, verify remote head, read both continuity files, inspect implementation `9659fbbed…` plus follow-ups `6d3a6f78…` and `b16cec4c4…`, and run `swift test --package-path Packages/NembraBluetoothCapture --filter 'AuthenticatedStationaryCaptureFieldAuthorizationTests|TuyaFieldInstallerRetainedIPAAdmissionSourceTests'` plus `python3 scripts/ci/tests/test_es80_authenticated_stationary_offline_authorization.py`. Review the Swift/Python compact sorted JSON contract and trusted-workflow pin together before pinning any production key.
2. Arrange independent private-key custody and review the matching public P-256 X9.63 bytes. Only then replace the nil `AuthenticatedStationaryCaptureFieldAuthorizationTrustAnchor` in source. Add `NembraCaptureFieldAuthorizationStore` with an atomic ThisDeviceOnly Keychain `consumeIfUnseen` implementation and wire the opaque capability through every OFF1/authentication/connection/seal boundary in `NembraCaptureEntrypoint`. Process/background/expiry/build drift must revoke it. Never flip `isAuthoritativeFieldBuild` or add a Boolean/plist/environment bypass.
3. Define and verify the exact trusted-workflow install manifest that cross-binds retained IPA, signed evidence, Final-GO, Tuya lock, pseudonym, authorization envelope, source/build/runtime, bundle, procedure, and intended device. Then delete the installer's unreachable legacy Debug rebuild block and install only the exact retained accepted signed IPA. Until then `scripts/field/install_one_time_capture.command` must keep stopping before device contact.
4. Diagnose `testSyntheticCorrelationToObservationFitsCompactLandscape` at `NembraCaptureUITests.swift:309` using the retained `cb00ee46a…` artifact. Preserve the final hittability assertion and fix the real scroll/compact-layout reachability issue. Run the exact-head hosted Xcode 27 Capture workflows and record terminal run IDs/artifacts.
5. After authorization/install closure, wire the real SDK callback into `TuyaStructuredApplicationEvidenceEvent` and an atomic private journal, then implement bundle cross-verification, human summary, sanitized fixture derivation, and the guided coordinator. No physical mapping or decoder promotion occurs before an accepted P0/P1 artifact.
6. When a BLE mapping or privacy-safe fixture becomes stable and production-consumable, update `docs/ES80_PROTOCOL_MAP.md`, sync PR #3675, and notify the portrait/cockpit tasks through repository docs/PR notes. Do not merge until current-head Capture and integrated product gates are green and inspected; use a merge commit, not squash.

## Rejected designs and approaches

- Horizon V2 Orbit/Vector/Apex and the V2 Option 2 execution are rejected. Do not merge, polish, or use their geometry, typography, thin roads, debug labels, or metric strips.
- Every Horizon V3 cockpit image/layout is rejected prototype history. Do not resurrect its clipped/crooked arc, map collisions, card structure, typography, or styling.
- Horizon V4 retains requirements authority only. Its PNGs and current runtime visual execution are rejected pixel targets; `docs/design-reference/horizon-v4-final/V4_COCKPIT_VISUAL_REJECTED.md` is the durable rejection record.
- The selected portrait package under `docs/design-reference/nembra-1.0-gold-glass/` is the sole Home/Rides/Vehicle/Settings composition authority.
- The Energy Chamber family is the selected post-V4 material/composition direction, not a pixel-final screenshot. Its original `-18/18 kW` scale, ambiguous NOW locator, unreadable direction/intensity, and generic typography are rejected and must not ship.
- Cockpit battery is one unified in-instrument value: percentage by default, tap to range, tap back. SOC fill always means charge; simultaneous/detached range is forbidden.
- Do not convert Capture into a second product app or let hardware waiting freeze main-app work.
- Do not fabricate BLE facts, range, route progress, ride totals, or road coverage. Simulator fixtures stay Debug+iOS-Simulator-only and visibly disclosed.
- Do not glass-coat telemetry/content or use independent blur stacks; use native Liquid Glass only for functional chrome and grouped glass containers where required.
- Do not use local Xcode 26 as release authority. GitHub-hosted Xcode 27/iPhone 12/iOS 27 evidence controls acceptance.
- Do not squash-merge PR #3675; the planned integration uses a merge commit after final exact-head approval.

## Unverified assumptions and evidence still required

- The `0b7e3b27…` accessibility/test-harness fixes are statically and locally compile-verified, but exact Xcode 27 must prove the full audits and that the Release metric validator receives real clock and Hitch Time Ratio samples.
- The Energy Chamber material/composition direction is user-approved, but its live-power visualization and typography are explicitly unfinished. The isolated cockpit task owns that implementation and must prove it with later exact-head screenshots/performance.
- Native Ride Window title/timestamp Text nodes still need the exact Xcode 27 Dynamic Type and VoiceOver audit.
- The retained b319 screenshot proves default 92%/unavailable copy is not visibly occluded, but it is not state-parallel with the selected 73%/learned-range reference and cannot prove other states, larger text, or populated-row clearance.
- The current 500×500 `ES80Side` presentation asset is linked to AOVOPRO's official product page but is not production-cleared: the exact source/hash, retrieval date, masking steps, author/license, and written reproduction permission are missing. The user has also rejected its low-resolution grey/red treatment as final. A replacement needs a user-owned actual-scooter photo or written licensed high-resolution source, full provenance, truthful geometry, and visual review.
- Battery microtexture, dimensional shell/rim, adaptive typography/contrast, SOC-clipped copy well, floor/contact lighting, and actionable continuation glass remain visually unfinished. The b319 comparison specifically records the overly bright double rim, wide copy well, uniform ribs, weak floor/contact grounding, temporary grey/red scooter, and flatter glass response.
- The standard, retained, low-battery, and Accessibility XXXL Home audits need exact Xcode 27 execution at `0b7e3b27…`; later portrait work belongs to the isolated Home task.
- No current GitHub-safe artifact proves a production ES80 packet mapping. CI proves software contracts and simulator fixtures, not physical BLE semantics. `docs/ES80_PROTOCOL_MAP.md` classifies every existing field/byte claim as observed fact, inference, hypothesis, contradiction, or unknown; every production semantic remains unknown.
- `TuyaStructuredApplicationEvidenceEvent` and `ES80GuidedCapturePlan` are compile/test-verified package foundations but are not app-wired. Their hashes are deterministic evidence identities, not signatures; the future private bundle must cross-check every plan receipt against exact retained typed event bytes.
- Field authorization is deliberately impossible on current production paths. The new current-procedure verifier/helpers are locally test-green, but their production trust anchor remains nil, no app consumption adapter exists, no trusted install manifest cross-verifies the retained subjects, and the installer now stops before the unreachable legacy Debug rebuild/device block. Exact hosted Xcode 27, independent key review, signed retained-IPA evidence, and real-device proof are still required rather than relaxing these blockers.
- Production numeric adaptive range remains unavailable because no accepted physical estimator/identity/evidence pipeline is wired. Do not synthesize the reference image's `8.4 mi`.
- Automatic capture is public-API best effort. Force-quit, restart-before-first-unlock, permissions, real ES80 restoration/reconnect, and background location behavior still require real-device evidence.
- Explore domain foundations do not select a road-graph provider or license. No road may be marked covered without accepted map-matched evidence.
