# ES80 Research Capture App Wiring

Status: **dependent product-facing research slice; software/Simulator only until physical execution**

Recovery worker lane: `parallel/recover-es80-research-capture-app-v13/chat-m8q2r`

Recovery PR: #350

Accepted passive-runtime dependency: PR #297 product head `ae0f2a20a6aecec02d972b9a66f75864d97796e9`.

Current-main passive-runtime re-anchor remains separately owned; do not race that worker or treat this dependent PR as permission to write its branch.

## Product outcome

Nembra has a dedicated **Nembra Capture** workflow around the accepted passive ES80 CoreBluetooth controller instead of leaving physical acquisition stranded inside a package-level technical surface.

This is research tooling, not production scooter control. The normal app launch remains the default and starts the existing `AppRuntime` exactly as before. The research launch deliberately does **not** start that runtime.

For normal physical research use in Xcode, select the shared **Nembra ES80 Research** scheme and Run. That scheme builds the existing `Nembra.app` in Debug and supplies `--es80-passive-capture`; it does not create a second app or target.

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
6. once **Capture Active** appears, keep Nembra in the foreground with the screen awake and set the phone down safely;
7. do not switch apps or lock the screen during live evidence capture;
8. when safely stopped, choose **Finish Capture** once;
9. Nembra requests the controller's versioned JSON first, decodes those exact prepared bytes through the capture schema, then ends the selected connection;
10. review the prepared-file facts and share the unchanged JSON for offline analysis.

Technical UUID/GATT/raw-stream/marker controls remain available behind **Advanced details** while the controller is idle. The polished shell does not duplicate the recorder, invent a second telemetry source, or promote presentation state into evidence.

A separate same-target session currently requires relaunching Nembra Capture because the parent controller intentionally does not expose an unsafe public reset that could silently reuse or mix target evidence.

## Foreground-only lifecycle contract

The first physical research workflow is deliberately **foreground-only**. It does not declare `bluetooth-central` background execution and does not use a Core Bluetooth Live Activity background path.

While a selected target connection is live, the shell:

- disables the app idle timer so ordinary inactivity does not auto-lock the screen;
- tells the operator to keep Nembra foregrounded and the screen awake;
- treats a transition away from the active scene as an evidence-integrity failure;
- cancels the active connection at that boundary;
- permanently refuses export from that shell session after the lifecycle failure.

This is intentionally conservative. A suspended foreground-only app can receive queued Bluetooth callbacks only after it resumes, so an apparently continuous receipt timeline could otherwise hide an observation gap or resume-time callback burst. A future background-capable research design requires its own explicit provenance and acceptance rather than inheriting foreground evidence semantics accidentally.

The idle timer is reset to its normal value when live evidence capture no longer needs it.

## Finalization admission

**Finish Capture** is admitted synchronously on the main actor before asynchronous artifact preparation begins.

The shell sets its one-shot finalization state before spawning the export task. A second rapid Finish action is therefore ignored instead of starting an overlapping `encodedCaptureJSON(...)` read. The parent controller's immutable artifact-read barrier remains defense-in-depth, not normal UI flow control.

If successful preparation has already produced the export document, the shell does not allow a later synthetic overlapping-read failure to coexist with that success state.

## Candidate identity and accessibility

Broad scan results remain candidates, not verified ES80 identities.

The visible row and VoiceOver semantics both include the same short UUID prefix as a **candidate ID**. This lets VoiceOver users distinguish two nearby peripherals with the same or missing local name without promoting that UUID, local name, or RSSI into physical identity proof.

The shell also fails closed if a locally selected UUID disappears from the controller's current candidate catalog. A stale UUID cannot continue to render an enabled **Start Capture** action after a scan epoch or central-state invalidation clears the candidate catalog.

## Prepared-file summary

After finalization, the product shell summarizes only facts derived from the exact JSON bytes being offered for export:

- capture schema version;
- total recorded events;
- raw value-observation count;
- explicit continuity-break count;
- **receipt timeline span** computed from the first/last boot-relative monotonic receipt timestamps.

The receipt timeline span is explicitly described as a first-to-last clock interval that may include known continuity gaps. It is **not** labeled continuously observed duration.

The shell does not call these facts a protocol-verification or hardware-integrity verdict. The summary explicitly says that they do **not** identify scooter fields or prove protocol semantics.

Decoding the exact prepared JSON before presenting the finished state prevents the UI from summarizing a second, later recorder snapshot that could differ from the file being shared. The accepted #297 parent owns the stronger immutable artifact-read watermark/authority guarantee.

## Privacy prompt truth

The app target's Bluetooth purpose string covers both normal vehicle use and the optional research launch without promising automatic/background behavior:

> Use Bluetooth to connect to your scooter and receive vehicle data, including passive evidence you explicitly capture in research mode.

The research launch remains manually scanned, explicitly target-selected, and foreground-only.

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

The app-supplied identity (`Selected Bluetooth candidate`, protocol family `unverified-passive-research`) is an operator/research label only.

**Start Capture** is not a protocol-verification claim. It means only that the explicitly chosen candidate becomes the controller's target-scoped passive session and connection attempt.

**Capture Active** means the parent controller reports complete finite passive acquisition for that selected target. It does not mean battery/current/power/speed semantics are decoded or verified.

## App lifetime separation

Research capture is intentionally a separate Debug launch mode rather than a hidden button inside Home or Dashboard. This avoids:

- starting normal scooter service and ride persistence alongside the research central;
- presenting vehicle controls next to unverified protocol acquisition;
- accidentally suggesting captured fields are already production telemetry;
- adding conflict-heavy Home/Dashboard/AppRoot edits before physical evidence exists.

The `ForegroundCoreBluetoothCaptureController` is created once for the app launch and retained for the research surface's lifetime.

## Accessibility / motion

The product shell keeps primary actions at large touch targets, gives candidate rows disambiguating semantic labels, expresses failure/warning/capture states in text rather than color alone, and suppresses candidate-list animation when Reduce Motion is enabled.

The intentionally black research surface uses an explicit dark presentation so semantic secondary text keeps deterministic contrast even when the phone otherwise uses Light appearance.

Raw technical detail remains a secondary disclosure rather than occupying the primary physical workflow.

## Simulator acceptance

Simulator QA proves only that:

- the local capture package is actually linked into `Nembra.app`;
- the explicit launch selector resolves to **Nembra Capture**;
- the passive-only and foreground-only warnings remain visible;
- the obvious stationary setup action exists;
- advanced technical detail remains available by disclosure;
- the normal `Vehicle controls` surface is absent;
- the shell renders at the iPhone 12 / iOS 27 baseline without claiming any physical Bluetooth result.

The UI test deliberately does not tap **Scan for scooter**, connect to a peripheral, manufacture CoreBluetooth callbacks, or convert Simulator behavior into physical evidence.

## Parent acceptance dependency

The product shell calls `encodedCaptureJSON(...)` before cancelling the selected connection; it does not copy or reinterpret recorder state.

PR #297's authoritative product head is `ae0f2a20a6aecec02d972b9a66f75864d97796e9`. Its Xcode 27 acceptance mirror `f0f6d14f6e5f5045b662a6c67667958e2d64443f` completed green in run `31224724399`, including immutable checkout, the package-wide no-application-`writeValue` guard, full `NembraBluetoothCapture` tests, and generic iOS Simulator package build.

That accepted parent proof does not accept later app-shell commits. This child requires a new exact-head app/Simulator gate after every acceptance-relevant shell change.

## First physical experiment after combined build acceptance

Use the smallest first physical action before any moving capture or field decoding:

1. install/run the accepted Debug build on the iPhone 12 / iOS 27 target by selecting **Nembra ES80 Research**;
2. verify **Nembra Capture**, **Passive evidence only**, and the foreground-only warning are visible;
3. keep the ES80 powered on, stationary, charger state noted, and do not enable any unknown command path;
4. choose **Scan for scooter**;
5. physically correlate the likely scooter candidate, then explicitly select it; do not treat name/RSSI/candidate ID as identity proof;
6. choose **Start Capture** and wait until the shell reports **Capture Active**;
7. keep Nembra foregrounded with the screen awake; set the phone down safely and keep the first baseline stationary for about 60 seconds;
8. while still safely stopped, choose **Finish Capture**, review the prepared-file facts, and share the versioned JSON unchanged;
9. inspect the immutable artifact with Nembra's offline tooling before proposing Tuya framing or any battery/current/power/speed field mapping.

If Nembra leaves the active foreground during live evidence capture, discard that attempt and repeat it; the shell intentionally refuses export from that session.

Only after this stationary path is repeatable and accepted should a later experiment ask for a short moving capture. A moving experiment still requires a safe mounting/handling plan that keeps the research app foregrounded without rider interaction.

Expected first evidence is real advertisement identity, real GATT topology/properties, passive value streams, provenance, raw cadence, and continuity boundaries. It is **not** yet battery/current/power/speed semantics.

## Dependency / merge rule

This recovery intentionally targets the accepted #297 dependency branch while the current-main passive-capture re-anchor is owned elsewhere. It must not duplicate, rewrite, or race that re-anchor branch.

After the passive runtime is accepted on current main (or an explicitly accepted successor branch), reconcile this six-path app-facing slice onto that exact descendant, verify dependency-relative scope again, and rerun exact-head Xcode 27 / iPhone 12 / iOS 27 acceptance before integration.

No ancestor, queued, skipped, or failed run becomes proof for a newer child head. Software/Simulator green is not physical AOVOPRO ES80 proof.
