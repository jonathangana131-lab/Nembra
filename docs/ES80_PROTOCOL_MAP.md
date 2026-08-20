# ES80 protocol map

Ledger format: `nembra.es80.protocol-map/v1`
Status: transport topology only; every ES80 semantic field is unknown.
Physical evidence authority: `C7D09A22` only.
Last audited code baseline: `3f0814ac70211f68b7af1a6913c78c91a810f663`.

This is a claim ledger, not a decoder specification. `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md` and `PhysicalCaptureTransportEvidence.c7d09a22` establish only transport facts. The source artifact contained zero application characteristic payloads and is not stored in Git.

## Confidence vocabulary

| Confidence | Meaning | Production use |
| --- | --- | --- |
| `unknown` | No accepted physical evidence identifies the field, codec, or behavior. | Never decode or display as device truth. |
| `hypothesis` | Public research, another Tuya product, stock-app presentation, or one ambiguous observation suggests a candidate. | Diagnostic analysis only; never select a decoder or command. |
| `correlated` | Repeated physical observations change with a controlled action and preserve source/timing/continuity, but identity/codec/scale or independent repeatability remains unresolved. | Quarantined experimental path only. |
| `verified` | Repeatable physical evidence fixes the source and interpretation, contradictions are resolved, and accepted fixtures cover valid and invalid behavior. | Eligible for reviewed production promotion. Transport verification alone never promotes semantics. |

## Transport and application ledger

| Claim | Source service / characteristic / DP | Field / byte / bit | Codec / endianness | Scale / unit | Cadence | Confidence | Evidence IDs | Contradictions / limitations |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Tuya transport service | GATT service `FD50` | Service identity | UUID | n/a | Discovery-time | `verified` | `C7D09A22` | Verified for the physical capture; not durable scooter identity or authentication. |
| App-to-device characteristic topology | `FD50` / `00000001-0000-1001-8001-00805F9B07D0` / no DP | Characteristic properties `write`, `writeWithoutResponse` | Opaque | n/a | Unknown | `verified` | `C7D09A22` | A property advertises capability; it does not authorize any application write or identify a command codec. |
| Device-to-app characteristic topology | `FD50` / `00000002-0000-1001-8001-00805F9B07D0` / no DP | Characteristic property `notify` | Opaque | n/a | Unknown | `verified` | `C7D09A22` | Subscription succeeded, but zero application value payloads were received. |
| Notification subscription descriptor | Notify characteristic / `2902` / no DP | CCCD | Standard GATT descriptor | n/a | Setup-time | `verified` | `C7D09A22` | CoreBluetooth may update CCCD to subscribe; this is transport setup, not a scooter application command. |
| Tuya manufacturer prefix | Advertisement manufacturer data / no DP | Prefix identifies company value `0x07D0`; exact ES80 product fields unknown | Opaque beyond company identifier | n/a | Advertisement-time | `verified` | `C7D09A22` | Does not authenticate the scooter or define service payload bytes. |
| Historical disconnect pattern | Connection callbacks / no DP | 15 peripheral disconnects; observed mean interval about 29.930 seconds | Monotonic timing observation | seconds | About 30 seconds in this one unauthenticated session | `verified` | `C7D09A22` | Session behavior, not a protocol timer guarantee. No authenticated comparison exists. |
| Raw FD50 application notifications | `FD50` notify characteristic / no DP | Unknown | Unknown framing, fragmentation, encryption, checksum, and endianness | Unknown | Unknown | `unknown` | `C7D09A22` | Payload count was zero. Public Tuya-family framing research is only a hypothesis for the ES80. |
| Official SDK application updates | `ThingSmartDeviceDelegate.dpsUpdate`; characteristic unavailable; DP keys unknown | SDK-decoded values, not bytes | Current app uses sanitized `String(describing:)`; package-owned typed private codec exists but is not app-wired | Unknown | Unknown | `unknown` | `P0-PENDING` | No accepted physical P0 session. `rawFD50BytesCaptured=false`; current app string projections are not lossless. |

## Semantic field ledger

Every row below remains unknown. A stock-app screen, simulator fixture, GPS value, scenario timing, vehicle spec sheet, or public Tuya DP catalog is not ES80 field evidence.

| Semantic field | Source characteristic / DP | Field / byte / bit | Codec / endianness | Scale / unit | Cadence | Confidence | Evidence IDs | Contradictions / limitations |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Speed | Unknown | Unknown | Unknown | Unknown; km/h versus mph and scaling unproven | Unknown | `unknown` | `C7D09A22` | Zero payloads; GPS/motion must not mint a BLE mapping. |
| Battery state of charge | Unknown | Unknown | Unknown | Unknown percentage scale/range | Unknown | `unknown` | `C7D09A22` | UI battery values do not identify a DP. |
| Charging state | Unknown | Unknown | Unknown | Unknown enum/boolean | Unknown | `unknown` | `C7D09A22` | Charger state was not protocol evidence. |
| Pack voltage | Unknown | Unknown | Unknown signedness/endianness | Unknown V/mV scale | Unknown | `unknown` | `C7D09A22` | Stock-app voltage is not source evidence. |
| Battery/motor current | Unknown | Unknown | Unknown signedness/endianness/direction | Unknown A/mA scale | Unknown | `unknown` | `C7D09A22` | Direction and zero point unproven. |
| Electrical/live power | Unknown | Unknown | Unknown; reported versus derived unproven | Unknown W scale/sign | Unknown | `unknown` | `C7D09A22` | Must not be derived from an invented current/voltage mapping. |
| Ride mode | Unknown | Unknown | Unknown enum | Unknown ECO/Drive/Sport coding | Unknown | `unknown` | `C7D09A22` | Physical mode changes were not paired with payloads. |
| Start mode | Unknown | Unknown | Unknown enum/boolean | Unknown | Unknown | `unknown` | `C7D09A22` | No semantic evidence. |
| Brake state | Unknown | Unknown | Unknown bit/enum | Unknown | Unknown | `unknown` | `C7D09A22` | No payload correlation. |
| Throttle state | Unknown | Unknown | Unknown bit/value | Unknown | Unknown | `unknown` | `C7D09A22` | No payload correlation; stationary safety remains separate. |
| Headlight state | Unknown | Unknown | Unknown bit/enum | Unknown | Unknown | `unknown` | `C7D09A22` | A physical or stock-app toggle does not identify a DP without captured observations. |
| Lock state | Unknown | Unknown | Unknown bit/enum | Unknown | Unknown | `unknown` | `C7D09A22` | No read or safe-write authority. |
| Cruise state | Unknown | Unknown | Unknown bit/enum | Unknown | Unknown | `unknown` | `C7D09A22` | No semantic evidence. |
| Speed-limit slots | Unknown | Unknown | Unknown array/DP set | Unknown km/h scale/ranges | Unknown | `unknown` | `C7D09A22` | Product specifications do not identify a device field. |
| Trip distance | Unknown | Unknown | Unknown endianness/width | Unknown km/mi scale and reset semantics | Unknown | `unknown` | `C7D09A22` | GPS trip distance is a separate phone-derived domain. |
| Device odometer | Unknown | Unknown | Unknown endianness/width | Unknown km/mi scale and reset/rollover semantics | Unknown | `unknown` | `C7D09A22` | User-recorded lifetime continuity is separate history, not BLE evidence. |
| Fault/error codes | Unknown | Unknown | Unknown bitset/enum | Unknown | Unknown | `unknown` | `C7D09A22` | No device-error payload exists. |
| Firmware/model identity | Unknown | Unknown | Unknown string/blob | Unknown | Unknown | `unknown` | `C7D09A22` | Local name and Tuya transport family do not prove model/firmware identity. |

Adaptive range is intentionally absent from the device-field ledger: Nembra may derive it from verified SOC plus persisted ride history under its separate range contract, but it must not be presented as a scooter-reported value unless a distinct verified source is later established.

## Command authority ledger

All application commands are unauthorized. The verified write characteristic properties do not establish message bytes, acknowledgement, safety, or semantic effect.

| Command family | Source characteristic / DP | Payload / acknowledgement | Authority | Evidence / limitation |
| --- | --- | --- | --- | --- |
| DP query / state sync | Unknown | Unknown | **unauthorized** | Current P0 requires `dpQueriesSent=false`. |
| Lock/unlock | Unknown | Unknown | **unauthorized** | No verified read mapping, write mapping, or acknowledgement. |
| Light | Unknown | Unknown | **unauthorized** | A physical control action may later be observed; Nembra must not command it during evidence collection. |
| Ride/start mode | Unknown | Unknown | **unauthorized** | No verified DP or safe value range. |
| Cruise / speed limit | Unknown | Unknown | **unauthorized** | Safety-critical semantics are entirely unknown. |
| Throttle / brake / motor | Unknown | Unknown | **unauthorized** | No application write is permitted. |
| Reset / unbind / pairing mutation | Unknown | Unknown | **unauthorized** | Destructive and explicitly forbidden. |
| Firmware / OTA | Unknown | Unknown | **unauthorized** | Explicitly forbidden. |

## Raw-versus-SDK evidence rule

1. A direct CoreBluetooth capture may record exact `Data` from the notify characteristic, exact callback boundaries, origin, source UUIDs, connection generation, and monotonic receipt. It does not by itself decrypt or interpret the bytes.
2. A SmartLife SDK `dpsUpdate` is application-level, SDK-decoded evidence. Even a future type-preserving canonical representation remains distinct from raw FD50/ATT bytes and has no truthful byte offset or endianness.
3. The official SDK is the sole authenticated BLE owner during P0/P1. Nembra must not open a second connection to manufacture raw evidence.
4. Claims must name their source class: `rawGATT`, `tuyaSDKApplication`, `phoneSensor`, `GPSMapKit`, `persistedHistory`, or `operatorObservation`. Evidence from one class cannot silently become another.

## Promotion rules

A semantic mapping may move from `unknown`/`hypothesis` to `correlated` only when an accepted physical artifact preserves:

- exact evidence session ID and build/procedure provenance;
- source class and, where available, service/characteristic/DP identity;
- value type or exact bytes without lossy stringification;
- monotonic receipt order, wall metadata, connection generation, and continuity breaks;
- explicit before/during/after action windows and the observed physical/stock-app reference;
- repeated samples and every contradiction or non-change.

Promotion to `verified` additionally requires independent repeatability, an unambiguous codec/field identity, width/signedness/endianness/scale/unit/range/cadence definition, resolved contradictions, and accepted invalid/stale/impossible-value behavior. Only `verified` mappings may enter the production decoder. `correlated` mappings stay behind diagnostic/experimental boundaries.

Read verification never grants write authority. Each command requires a separate, explicitly authorized, non-destructive physical experiment with exact request bytes, response/acknowledgement evidence, timeout/retry/idempotence behavior, safe ranges, failure handling, and user confirmation. Until then, `UnverifiedScooterService` remains production truth.

## Fixture requirements

Before a verified mapping is consumed by Nembra, commit a privacy-reviewed deterministic fixture and tests that include:

- schema/version, pseudonymous evidence IDs, source class, source identity, connection generation, sequence and monotonic receipt;
- exact raw bytes **or** canonical typed SDK values, never a reconstructed substitute;
- action-window markers, expected decoded observation, confidence, provenance, and known limitations;
- duplicates, truncated/corrupt input, unknown DP/field, out-of-order receipt, disconnect/generation change, stale age, boundary values, impossible values, and unsupported type cases;
- deterministic round-trip/import and a human-readable summary assertion;
- no private device/account identifiers, secrets, keys, tokens, signing material, or unreviewed raw field artifact.

The fixture must cite the private artifact's reviewed digest/provenance without copying sensitive content into Git. If sanitization would alter the bytes or typed value that establishes the mapping, keep the fixture out of production and leave the mapping unverified until a safe derivation is possible.

## Next evidence rung

Physical status remains **NO-GO**. The package now has type-preserving private SDK-event and conservative guided-window contracts, but neither is wired to the standalone app, durable journal, verified bundle, or field authorization. First close independent field authorization, the real SDK adapter/private journal, and lossless bundle/import. Then run the stationary P0 gate. Only a genuine P0 pass may authorize execution of the reviewed P1 physical-action plan; this ledger must be updated from sealed evidence before any decoder work begins.
