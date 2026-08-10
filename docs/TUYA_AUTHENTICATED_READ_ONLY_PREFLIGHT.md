# Tuya Authenticated Read-Only Preflight

Purpose: define the smallest safe next physical experiment after capture `C7D09A22` proved Tuya FD50 transport but produced zero application notification payloads.

## Why this is the next gate

The first physical capture established:

- Tuya FD50 transport identity;
- app-to-device write and device-to-app notify characteristics;
- successful CoreBluetooth notification subscription;
- zero application characteristic payloads;
- repeatable peripheral-initiated disconnects at approximately the unauthenticated timeout window.

The next experiment must therefore establish a legitimate Tuya application-layer session before any further physical semantic mapping.

## Supported authentication route

Use Tuya's documented SmartLife App SDK / BLE device-management path for an already-bound device, backed by a legitimate Tuya developer application identity and the user's own account/device authorization.

Do not implement guessed raw pairing packets from packet fragments. Do not scrape credentials from the installed Tuya app. Do not attempt to bypass ownership/binding checks.

The integration must treat Tuya app key/secret material, account tokens, local keys, device identifiers that are secret-bearing, and session keys as private runtime inputs. None may be committed to Git, exported in Capture JSON, printed to ordinary logs, or included in screenshots.

## Capture architecture

Keep two sharply separated layers:

1. `TuyaAuthenticatedSessionAdapter`
   - owns Tuya SDK initialization and authenticated connection lifecycle;
   - may establish the documented secure session only;
   - exposes connection/authentication state and raw incoming application payload events to Capture;
   - exposes no arbitrary public write API to the Capture UI;
   - fails closed if required Tuya developer/account configuration is missing or invalid.

2. Existing passive CoreBluetooth evidence recorder
   - records advertisements, GATT topology, RSSI, lifecycle, scenario markers, location reference, and raw incoming notification bytes;
   - does not infer telemetry semantics;
   - does not issue unknown scooter commands.

If the Tuya SDK itself must perform protocol writes required solely to authenticate/connect, classify them as `transportAuthentication`, never as scooter control commands, and do not expose their payloads as reusable command primitives.

## Runtime preflight UX

Before any stationary or outdoor scenario, show a dedicated `Authenticated link preflight` screen with these states:

- `Tuya configuration unavailable` — no physical test allowed.
- `Account/device authorization required` — no CoreBluetooth fallback pretending to be authenticated.
- `Authenticating` — scenarios disabled.
- `Authenticated, waiting for payload` — timer visible; scenarios disabled.
- `Authenticated payload confirmed` — only then unlock stationary mapping.
- `Authentication lost` — freeze the current scenario and retain evidence; do not silently downgrade to unauthenticated reconnect loops.

The preflight must be runnable indoors and must not require riding.

## Acceptance criteria

All of the following are required in one physical run:

1. Correct physical peripheral selected: `6815A5F5-4D1E-E004-BAE8-6DF924123907` or a newly assigned iOS peripheral UUID that is re-identified through the same physical Tuya advertisement evidence.
2. Tuya authenticated/authorized session reports success through the documented SDK path.
3. FD50 notification transport becomes active.
4. At least one non-empty real application payload is received.
5. Connection remains alive continuously beyond 45 seconds, comfortably past the prior approximately-30-second rejection cadence.
6. No unbind, reset, re-pair, lock, speed-limit, mode, light, cruise, or motor-control action occurs.
7. Capture export contains authentication-state markers and raw application payload bytes, but no credentials/session secrets.

If any condition fails, the result is still exported as diagnostic evidence but telemetry mapping remains locked.

## First mapping pass after acceptance

Do not repeat the full outdoor run immediately. Perform stationary scenarios first:

1. untouched powered-on idle;
2. battery percentage reference as visually reported by the official Tuya app, recorded only as an operator reference marker;
3. optional charger plug-in / unplug transition while indoors;
4. ECO / Drive / Sport selection using scooter-local controls only;
5. headlight OFF / ON;
6. brake held and brake pulses.

Only after repeatable payload differences appear should individual DP semantics be proposed. A proposed DP is not accepted from a single transition.

## Movement gate

Outdoor testing resumes only when authenticated stationary telemetry proves that application payloads are flowing. Then repeat the minimum motion set needed to correlate:

- speed;
- trip/odometer growth;
- motion-dependent current/power if present.

The existing user-supplied lifetime odometer continuity of `2164.8 mi` remains `userReferenceHistory` and must never be used to identify or validate a Bluetooth DP by itself.

## Explicitly prohibited

- arbitrary characteristic writes;
- guessed Tuya pairing frames;
- extracting secrets from the Tuya app binary/storage;
- unbinding or factory reset;
- pairing the scooter to a different ownership context merely for research;
- command fuzzing;
- exposing authenticated write primitives in Capture;
- assigning speed/battery/mode/light/brake/power/odometer semantics before repeatable physical correlation.
