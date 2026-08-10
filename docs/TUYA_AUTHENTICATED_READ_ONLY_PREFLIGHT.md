# Tuya Authenticated Read-Only Preflight

Purpose: define the smallest safe physical experiment after capture `C7D09A22` proved Tuya FD50 transport but produced zero application payloads.

Current field procedure: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`.

## Why this is the next gate

The first physical capture established:

- Tuya FD50 transport identity;
- app-to-device write and device-to-app notify characteristics;
- successful unauthenticated CoreBluetooth notification subscription;
- zero application characteristic payloads;
- repeatable peripheral-initiated disconnects at approximately the unauthenticated timeout window.

The next experiment must establish a legitimate Tuya application-layer session before any semantic DP mapping.

## Supported authentication route

Use Tuya's documented SmartLife App SDK / BLE device-management path for the user's already-bound device, backed by a legitimate Tuya Developer Platform application identity and the user's authorized SDK account/device session.

Do not implement guessed raw pairing packets from packet fragments. Do not scrape credentials from the installed Tuya app. Do not attempt to bypass ownership or binding checks. A cloud `local_key` is not accepted as BLE-session provenance by itself.

AppKey/AppSecret, account tokens, local keys, session keys, verification codes, and generated Tuya security material are private runtime inputs. They must never be committed to Git, exported in Capture JSON, printed to ordinary logs, or exposed in screenshots.

## Authority chain before BLE authentication

A logged-in SDK account alone is not sufficient authority for the selected scooter.

Before BLE authentication, the field app must:

1. initialize the official SDK with the matching private app identity;
2. establish/login the user's SDK account session;
3. enumerate the account's Tuya homes;
4. load every home required for a complete membership result;
5. find the exact selected scooter `deviceID` in an owned or shared device list;
6. fail closed if home enumeration/loading is incomplete or the exact ID is absent.

Metadata QR approval is a separate device-discovery/ownership aid; it does not substitute for this SDK-account exact-device membership gate.

## Capture architecture — one authenticated BLE owner

The authenticated observation path has one owner: Tuya's official SDK.

### CoreBluetooth correlation phase

Before authentication, Nembra may use CoreBluetooth only to correlate the nearby physical scooter using accepted deterministic evidence:

- the prior iOS peripheral UUID when it is still assigned; or
- corroborating FD50 service evidence plus Tuya company ID evidence.

Power-cycle appearance, name, and RSSI may rank/display candidates but must not independently authorize the target.

Nembra stops its scan before secure authentication begins.

CoreBluetooth correlation does **not** mint authenticated-session provenance and must not open a second connection after the Tuya SDK takes BLE ownership.

### Tuya SDK authenticated phase

The SDK adapter:

- initializes the documented Tuya SDK with the matching private app configuration;
- establishes the documented BLE connection for the exact membership-verified Tuya device;
- attaches `ThingSmartDeviceDelegate` to the SDK-owned device object;
- records non-empty application/DP update callbacks as opaque structured evidence;
- observes Tuya's documented local-BLE status for continuity;
- exposes no generic DP publish/query or GATT-write surface to Capture.

If Tuya's SDK emits protocol traffic required to establish its session, classify it as SDK-owned transport authentication. Nembra does not construct, replay, or expose those frames.

## Canonical session authority

Every connection attempt must use `TuyaAuthenticatedReadOnlySessionLedger` as the chronology authority and `TuyaAuthenticatedReadOnlyPreflight` as the acceptance verdict.

- A new attempt receives a fresh opaque ledger-instance-bound connection token/generation.
- Authentication start/success/failure and application updates are admitted only through that token.
- A stale token cannot mutate a newer generation.
- The app records structured SDK update presence with `recordApplicationUpdate(isNonEmpty:for:)`; it does not invent serialized payload bytes.
- Observed local-BLE liveness advances the current generation only while the app can sample it often enough to maintain the accepted foreground continuity contract.
- A long observation/suspension gap fails closed before liveness advances; wall-clock time across an unobserved gap is not proof of continuous BLE survival.
- A disconnect/failed attempt retires the current authority; late callbacks cannot promote it back to PASS.

## Payload authority

The current accepted receive authority is the SDK-delivered application/DP callback for the SDK-owned device session.

That callback is already application-level/decoded data. It is **not** raw FD50 characteristic bytes and must never be labeled as raw transport capture.

The current field build may export sanitized opaque DP IDs/value string projections for diagnostic comparison. These projections are descriptive only and are not byte-exact or lossless payload authority.

Raw FD50 transport bytes remain a separate evidence class. They may be claimed only if a future documented same-session SDK hook or other authority proves they came from the authenticated session. A second independent CoreBluetooth connection cannot satisfy that requirement. The current authenticated preflight explicitly records `rawFD50BytesCaptured = false`.

## Runtime preflight UX

Before any stationary or outdoor scenario, show a dedicated authenticated-link preflight with these states:

- `Tuya configuration unavailable` — no physical test allowed;
- `SDK account login required` — no metadata/CoreBluetooth fallback pretending to be authenticated;
- `Exact scooter membership not verified` — no BLE authentication yet;
- `Authenticating` — scenarios disabled;
- `Authenticated, waiting for application data / continuity` — timer/status visible, scenarios disabled;
- `Authenticated application data confirmed` — only after canonical 45-second acceptance may stationary mapping unlock;
- `Authentication/continuity lost` — fail the attempt, preserve diagnostic evidence, do not silently downgrade to an unauthenticated reconnect loop.

The preflight is indoor and stationary. Riding is not required.

## Acceptance criteria

All of the following are required in one current physical attempt/generation:

1. The correct physical scooter is deterministically correlated from accepted local evidence.
2. The exact selected Tuya `deviceID` is verified in the logged-in SDK account's fully loaded owned/shared home membership.
3. The official/documented Tuya SDK path establishes the connection for that selected already-bound device.
4. Tuya's local-BLE status reports the SDK-owned device locally connected.
5. At least one non-empty genuine SDK application/DP update is admitted for the same authenticated connection generation.
6. The canonical monotonic authenticated chronology reaches at least 45 seconds while local BLE is observably online and without a disqualifying observation gap.
7. `TuyaAuthenticatedReadOnlyPreflight.verdict` is `readyForStationaryMapping` for that same generation.
8. No unbind, reset, re-pair, lock, speed-limit, mode, light, cruise, motor-control, DP query, or DP publish action occurs.
9. The diagnostic export records deterministic target evidence, exact-device membership, connection generation, authentication/session chronology, local-BLE state, application-update evidence, and failure state without credentials/session secrets.
10. The export does not claim raw FD50 bytes and keeps `rawFD50BytesCaptured = false` unless a separately accepted same-session raw-byte authority is introduced later.

If any condition fails, export the attempt as diagnostic evidence but keep telemetry mapping locked.

## First mapping pass after acceptance

Do not repeat the full outdoor run immediately. Perform stationary scenarios first:

1. untouched powered-on idle;
2. battery percentage shown by the official Tuya app, recorded only as an operator reference marker;
3. ECO / Drive / Sport selection using scooter-local controls only;
4. headlight OFF / ON using scooter-local controls;
5. brake held and brake pulses;
6. optional charger plug-in / unplug transition while stationary.

Only after repeatable application-value differences appear should individual DP semantics be proposed. A proposed DP is not accepted from a single transition.

## Movement gate

Outdoor testing resumes only after authenticated stationary application data is flowing and repeatable. Then perform the minimum motion set needed to correlate speed, trip/odometer growth, and motion-dependent electrical fields if present.

The user-supplied lifetime odometer continuity of `2164.8 mi` remains `userReferenceHistory`; it is not Bluetooth evidence and must not be used to validate a DP by itself.

## Explicitly prohibited

- arbitrary characteristic writes;
- guessed Tuya pairing/authentication frames;
- extracting secrets from Tuya app binary/storage/memory;
- opening a second CoreBluetooth connection after Tuya owns the authenticated session;
- score/name/RSSI-only target authorization;
- unbinding or factory reset;
- pairing the scooter to a different ownership context merely for research;
- DP publish/query during this preflight;
- command fuzzing;
- exposing authenticated write primitives in Capture;
- serializing decoded callbacks into invented raw payload bytes;
- labeling SDK-decoded DP callbacks as raw FD50 bytes;
- counting an unobserved suspension/event-loop gap as authenticated continuity;
- assigning speed/battery/mode/light/brake/power/odometer semantics before repeatable physical correlation.
