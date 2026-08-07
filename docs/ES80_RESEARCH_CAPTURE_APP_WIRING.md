# ES80 Research Capture App Wiring

Status: **dependent product-facing research slice; software/Simulator only until physical execution**

Worker lane: `parallel/es80-research-capture-app/chat-x5n7q`

Dependency: passive-capture recovery PR #239 / `parallel/recover-es80-passive-capture-runtime/chat-c7m2q`.

## Product outcome

Nembra now has a dedicated **Nembra Capture** workflow around the existing passive ES80 CoreBluetooth controller instead of leaving physical acquisition stranded inside a package-level technical Form.

This is research tooling, not production scooter control. The normal app launch remains the default and starts the existing `AppRuntime` exactly as before. The research launch deliberately does **not** start that runtime.

For normal physical use in Xcode, select the shared **Nembra ES80 Research** scheme and Run. That scheme builds the existing `Nembra.app` in Debug and supplies `--es80-passive-capture`; it does not create a second app or target.

The Debug app also accepts either selector directly when automation needs it:

- launch argument: `--es80-passive-capture`
- environment: `NEMBRA_ES80_PASSIVE_CAPTURE=1`

Release builds ignore those selectors and use the standard app path.

## Nembra Capture workflow

The default research surface is intentionally sparse and operator-oriented:

1. preflight Bluetooth while stationary;
2. **Scan for scooter** without auto-selecting a device;
3. physically correlate and explicitly select one nearby candidate;
4. **Start Capture**, which invokes the controller's real target-session/connect boundary;
5. wait for finite service/topology/read/subscription acquisition to become complete;
6. once **Capture Active** appears, put the phone away and do not interact with it while riding;
7. when safely stopped, choose **Finish Capture**;
8. Nembra requests the controller's versioned JSON first, decodes those exact prepared bytes through the capture schema, then ends the selected connection;
9. review the prepared-file facts and share the unchanged JSON for offline analysis.

Technical UUID/GATT/raw-stream/marker controls remain available behind **Advanced details** while the controller is idle. The polished shell does not duplicate the recorder, invent a second capture state machine, or promote presentation state into evidence.

A separate same-target session currently requires relaunching Nembra Capture because the parent controller intentionally does not expose an unsafe public reset that could silently reuse or mix target evidence.

## Prepared-file summary

After finalization, the product shell summarizes only facts derived from the exact JSON bytes being offered for export:

- capture schema version;
- total recorded events;
- raw value-observation count;
- explicit continuity-break count;
- observed evidence span computed from the first/last boot-relative monotonic receipt timestamps.

The shell does not call this a protocol-verification or hardware-integrity verdict. The summary explicitly says that these file facts do **not** identify scooter fields or prove protocol semantics.

Decoding the exact prepared JSON before presenting the finished state also prevents the UI from summarizing a second, later recorder snapshot that could differ from the file being shared. Parent PR #239 still owns the stronger export-watermark/snapshot consistency guarantee described below.

## Safety / truth boundary

The app wiring adds no Bluetooth characteristic write path and does not reinterpret the parent package's passive acquisition semantics.

The research controller:

- performs broad foreground discovery without assuming a service family;
- requires explicit peripheral selection before target-labelled evidence exists;
- reads only where CoreBluetooth reports `.read`;
- subscribes only where CoreBluetooth reports notify/indicate capability;
- records raw attribution, timing, topology, reads, subscriptions, and notifications;
- fails closed when a finite acquisition is incomplete;
- keeps stock-app values as correlation markers rather than protocol truth;
- never turns a CoreBluetooth UUID, local name, RSSI, or the app's `VehicleIdentity` label into proof of physical ES80 identity.

The app-supplied identity (`AOVOPRO ES80 research target`, protocol family `unverified-passive-research`) is an operator/research label only.

**Start Capture** is therefore not a protocol-verification claim. It means only that the explicitly chosen candidate becomes the controller's target-scoped passive session and connection attempt.

**Capture Active** means the parent controller reports complete finite passive acquisition for that selected target. It does not mean battery/current/power/speed semantics are decoded or verified.

## App lifetime separation

Research capture is intentionally a separate Debug launch mode rather than a hidden button inside Home or Dashboard. This avoids:

- starting normal scooter service and ride persistence alongside the research central;
- presenting vehicle controls next to unverified protocol acquisition;
- accidentally suggesting captured fields are already production telemetry;
- adding conflict-heavy Home/Dashboard/AppRoot edits before physical evidence exists.

The `ForegroundCoreBluetoothCaptureController` is created once for the app launch and retained for the research surface's lifetime.

## Accessibility / motion

The product shell keeps primary actions at large touch targets, gives candidate rows combined semantic labels, expresses failure/warning/capture states in text rather than color alone, and suppresses candidate-list animation when Reduce Motion is enabled.

The intentionally black research surface uses an explicit dark presentation so semantic secondary text keeps deterministic contrast even when the phone otherwise uses Light appearance.

Raw technical detail remains a secondary disclosure rather than occupying the primary physical workflow.

## Simulator acceptance

Simulator QA proves only that:

- the local capture package is actually linked into `Nembra.app`;
- the explicit launch selector resolves to **Nembra Capture**;
- the passive-only warning and safe-use copy remain visible;
- the obvious stationary setup action exists;
- advanced technical detail remains available by disclosure;
- the normal `Vehicle controls` surface is absent;
- the shell renders at the iPhone 12 / iOS 27 baseline without claiming any physical Bluetooth result.

The UI test deliberately does not tap **Scan for scooter**, connect to a peripheral, manufacture CoreBluetooth callbacks, or convert Simulator behavior into physical evidence.

## Parent artifact consistency dependency

Final export truth remains owned by PR #239's controller/recorder layer. The product shell calls `encodedCaptureJSON(...)` before cancelling the selected connection; it does not copy or reinterpret recorder state.

Any unresolved parent concern about exact export watermark/snapshot consistency remains a blocker for calling a shared file authoritative. Decoding and summarizing the exact bytes in this child does not repair or conceal that parent concern. This child must not call a queued/failed parent gate accepted.

## First physical experiment after combined build acceptance

Use the smallest first physical action before any moving capture or field decoding:

1. install/run the accepted Debug build on the iPhone 12 / iOS 27 target by selecting **Nembra ES80 Research**;
2. verify **Nembra Capture** and **Passive evidence only** are visible;
3. keep the ES80 powered on, stationary, charger state noted, and do not enable any unknown command path;
4. choose **Scan for scooter**;
5. physically correlate the likely scooter candidate, then explicitly select it; do not treat name/RSSI/UUID as identity proof;
6. choose **Start Capture** and wait until the shell reports **Capture Active**;
7. keep the first baseline stationary for about 60 seconds;
8. while still safely stopped, choose **Finish Capture**, review the prepared-file facts, and share the versioned JSON unchanged;
9. inspect the immutable artifact with Nembra's offline tooling before proposing Tuya framing or any battery/current/power/speed field mapping.

Only after this stationary path is repeatable and accepted should a later experiment ask for a short moving capture. The phone must be put away before motion and handled again only after safely stopping.

Expected first evidence is real advertisement identity, real GATT topology/properties, passive value streams, provenance, raw cadence, and continuity boundaries. It is **not** yet battery/current/power/speed semantics.

## Dependency / merge rule

This branch is intentionally based on PR #239's recovery head and should target that branch while #239 remains unmerged. It must not duplicate or rewrite the parent package. If the parent moves, reconcile this child non-destructively, verify the dependency-relative diff, and rerun exact-head Xcode 27 / iPhone 12 / iOS 27 acceptance.

After the passive-capture parent lands, reconcile this app-facing slice onto the accepted descendant before main integration. No ancestor, queued, skipped, or failed run becomes proof for a newer child head.
