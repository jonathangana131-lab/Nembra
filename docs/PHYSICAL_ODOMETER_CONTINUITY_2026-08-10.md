# Physical odometer continuity — 2026-08-10

This record is user-supplied continuity evidence for the physical scooter. It is NOT Bluetooth-derived telemetry and must not be promoted to protocol truth.

## User-maintained odometer epochs

The Tuya app's visible odometer has reset twice. The user retained the prior totals:

- Epoch 1 before reset: `665.3 mi`
- Epoch 2 before reset: `429.5 mi`
- Current Tuya app value: `1070.0 mi`

Reference lifetime distance:

`665.3 + 429.5 + 1070.0 = 2164.8 mi`

Metric reference: approximately `3483.9 km`.

## Product semantics

Until authenticated physical Tuya DP payloads identify and validate the device's odometer field, Nembra should treat these as separate concepts:

- `deviceReportedOdometer`: unavailable / unknown for the physical profile.
- `userReferenceLifetimeOdometer`: `2164.8 mi`, explicitly user-maintained.
- `currentTuyaDisplayedEpoch`: `1070.0 mi`, explicitly a current app display reference, not total lifetime distance.
- reset offsets: `665.3 mi` and `429.5 mi` retained as provenance.

Nembra must not silently add these offsets to a future device value unless the UI/provenance layer labels the result as user-reconciled lifetime distance. If authenticated device evidence later proves the Tuya DP is itself lifetime rather than resettable epoch distance, this record must be re-evaluated rather than double-counted.

## UI recommendation

Where the product needs a useful value before protocol mapping is complete, show:

`2,164.8 mi  ·  user-reconciled lifetime`

with a secondary note such as:

`Tuya currently shows 1,070.0 mi; two earlier meter epochs are preserved.`

Do not label the number `Live odometer`, `Scooter odometer`, or `Bluetooth odometer` until physical DP evidence earns that authority.
