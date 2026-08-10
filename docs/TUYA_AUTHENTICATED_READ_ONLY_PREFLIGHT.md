# Tuya Authenticated Read-Only Preflight

Purpose: define the smallest safe physical experiment after capture `C7D09A22` proved Tuya FD50 transport but produced zero application payloads.

Current field procedure: `docs/CAPTURE_NEXT_TUYA_SECURE_LINK_TEST.md`.

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

AppKey/AppSecret, account tokens, local keys, session keys, and generated Tuya security material are private runtime inputs. They must never be committed to Git, exported in Capture JSON, printed to ordinary logs, or exposed in screenshots.

## Capture architecture — one authenticated BLE owner

The authenticated observation path has one owner: Tuya's official SDK.

### CoreBluetooth correlation phase

Before authentication, Nembra may use CoreBluetooth only to correlate the nearby physical scooter using already-accepted evidence such as:

- the prior iOS peripheral UUID when it is still assigned;
- FD50 service evidence;
- Tuya company ID evidence;
- deterministic scooter OFF -> ON appearance delta.

Nembra stops its scan before secure authentication begins.

CoreBluetooth correlation does **not** mint authenticated-session provenance and must not open a second connection after the Tuya SDK takes BLE ownership.

### Tuya SDK authenticated phase

The SDK adapter:

- initializes the documented Tuya SDK with the matching private app configuration;
- establishes the documented BLE connection for the selected Tuya device;
- attaches `ThingSmartDeviceDelegate` to the SDK-owned device object;
- records non-empty application/DP update callbacks as opaque evidence;
- polls Tuya's documented local-BLE status API for continuity;
- exposes no generic DP publish/query or GATT-write surface to Capture.

If Tuya's SDK emits protocol traffic required to establish its session, classify it as SDK-owned transport authentication. Nembra does not construct, replay, or expose those frames.

## Payload authority

The current accepted receive authority is the SDK-delivered application/DP callback for the SDK-owned device session.

That callback is already application-level/decoded data. It is **not** raw FD50 characteristic bytes and must never be labeled as raw transport capture.

The current field build may export a sanitized representation of opaque DP IDs/values so later physical mapping can compare changes. Preserve value types where the SDK exposes them; if an implementation converts a value for serialization, record that representation honestly rather than claiming byte-exact fidelity.

Raw FD50 transport bytes remain a separate evidence class. They may be claimed only if a future documented same-session SDK hook or other authority proves they came from the authenticated session. A second independent CoreBluetooth connection cannot satisfy that requirement.

## Runtime preflight UX

Before any stationary or outdoor scenario, show a dedicated authenticated-link preflight with these states:

- `Tuya configuration unavailable` — no physical test allowed;
- `Account/device authorization required` — no CoreBluetooth fallback pretending to be authenticated;
- `Authenticating` — scenarios disabled;
- `Authenticated, waiting for application data` — timer visible, scenarios disabled;
- `Authenticated application data confirmed` — only then unlock stationary mapping;
- `Authentication lost` — fail the attempt, preserve diagnostic evidence, do not silently downgrade to an unauthenticated reconnect loop.

The preflight is indoor and stationary. Riding is not required.

## Acceptance criteria

All of the following are required in one physical run:

1. The correct physical scooter is correlated from accepted local evidence.
2. The official/documented Tuya SDK path reports connection success for the selected already-bound Tuya device.
3. Tuya's local-BLE status reports the SDK-owned device locally connected.
4. At least one non-empty genuine SDK application/DP update is received from that device session.
5. The authenticated local-BLE session remains continuously proven for more than 45 seconds, comfortably beyond the prior approximately-30-second rejection cadence.
6. No unbind, reset, re-pair, lock, speed-limit, mode, light, cruise, motor-control, DP query, or DP publish action occurs.
7. The diagnostic export records correlation evidence, authentication/session state, monotonic continuity evidence, application-update evidence, and failure state without credentials or session secrets.
8. The export does not claim raw FD50 bytes unless a separately accepted same-session authority actually captured them.

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
- unbinding or factory reset;
- pairing the scooter to a different ownership context merely for research;
- DP publish/query during this preflight;
- command fuzzing;
- exposing authenticated write primitives in Capture;
- labeling SDK-decoded DP callbacks as raw FD50 bytes;
- assigning speed/battery/mode/light/brake/power/odometer semantics before repeatable physical correlation.
