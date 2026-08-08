# ES80 Research Capture App Wiring

Status: **dependent product-facing research slice; software/Simulator only until physical execution**

Recovery worker lane: `parallel/recover-es80-research-capture-app-v13/chat-m8q2r`

Recovery PR: #350

Accepted passive-runtime source dependency: PR #297 product head `ae0f2a20a6aecec02d972b9a66f75864d97796e9`.

Current-main passive-runtime integration dependency: PR #353 or its accepted reconciled descendant.

## Product outcome

Nembra has a dedicated **Nembra Capture** workflow around the accepted passive ES80 CoreBluetooth controller instead of leaving physical acquisition stranded inside a package-level technical surface.

This is research tooling, not production scooter control. The normal app launch remains the default and starts the existing `AppRuntime` exactly as before. The research launch deliberately does **not** start that runtime.

For normal physical research use in Xcode, select the shared **Nembra ES80 Research** scheme and Run. That scheme builds the existing `Nembra.app` in Debug and supplies `--es80-passive-capture`; it does not create a second app or target.

The Debug app also accepts either selector directly when automation needs it:

- launch argument: `--es80-passive-capture`
- environment: `NEMBRA_ES80_PASSIVE_CAPTURE=1`

Release builds ignore those selectors and use the standard app path.

## Nembra Capture workflow

The product-facing research surface is intentionally sparse and operator-oriented:

1. preflight Bluetooth while stationary;
2. **Scan for scooter** without auto-selecting a device;
3. physically correlate and explicitly select one nearby candidate using the accepted experiment procedure;
4. **Start Capture**, which invokes the controller's real target-session/connect boundary;
5. wait for finite service/topology/read/subscription acquisition to become complete;
6. once **Capture Active** appears, keep Nembra in the foreground with the screen awake and set the phone down safely;
7. do not switch apps or lock the screen during live evidence capture;
8. when safely stopped, choose **Finish Capture** once;
9. Nembra requests the controller's versioned JSON first, decodes those exact prepared bytes through the capture schema, then ends the selected connection;
10. review the prepared-file facts and share the unchanged JSON for offline analysis.

A separate same-target session currently requires relaunching Nembra Capture because the parent controller intentionally does not expose an unsafe public reset that could silently reuse or mix target evidence.

## No legacy-console escape hatch

The accepted package also contains `ES80PassiveCaptureResearchView`, a broad engineering console with its own scan, connect, cancel, marker, analysis, and export controls.

That console is useful package-level research infrastructure, but it is **not** a read-only details screen. Exposing it from the product shell would let an operator start a second acquisition path outside the shell's foreground-integrity, one-shot-finalization, and product-state rules.

Therefore #350 intentionally does **not** link the package console from Nembra Capture.

A future advanced disclosure may return only when it is implemented as a genuinely read-only inspector over the same authoritative selected session/artifact, or when the package console itself adopts the exact same product lifecycle contract. Do not re-add the existing control-capable console under a harmless-sounding **Advanced details** label.

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

Candidate selection still requires an external, accepted physical-correlation procedure. Name, candidate ID, and RSSI alone are never sufficient proof. If the accepted first-physical-capture runbook cannot mechanically disambiguate the target with current tooling, the experiment must stop rather than asking the operator to choose by intuition.

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

The product shell intentionally omits the control-capable package console. Future raw technical detail must be a read-only disclosure that cannot silently become a second acquisition workflow.

## Simulator acceptance

Simulator QA proves only that:

- the local capture package is actually linked into `Nembra.app`;
- the explicit launch selector resolves to **Nembra Capture**;
- the passive-only and foreground-only warnings remain visible;
- the obvious stationary setup action exists;
- the control-capable package research console is **not** exposed from the product shell;
- the normal `Vehicle controls` surface is absent;
- the shell renders at the iPhone 12 / iOS 27 baseline without claiming any physical Bluetooth result.

The UI test deliberately does not tap **Scan for scooter**, connect to a peripheral, manufacture CoreBluetooth callbacks, or convert Simulator behavior into physical evidence.

## Parent acceptance dependency

The product shell calls `encodedCaptureJSON(...)` before cancelling the selected connection; it does not copy or reinterpret recorder state.

PR #297's authoritative product head is `ae0f2a20a6aecec02d972b9a66f75864d97796e9`. Its Xcode 27 acceptance mirror `f0f6d14f6e5f5045b662a6c67667958e2d64443f` completed green in run `31224724399`, including immutable checkout, the package-wide no-application-`writeValue` guard, full `NembraBluetoothCapture` tests, and generic iOS Simulator package build.

That accepted parent proof does not accept later app-shell commits. This child requires a new exact-head app/Simulator gate after every acceptance-relevant shell change.

## First physical experiment after combined build acceptance

The authoritative V13 physical procedure is owned by #351 or its accepted descendant. Do not execute from this section if the dedicated runbook has moved.

At minimum, the product-shell side of the gate requires:

1. an accepted Debug build on the iPhone 12 / iOS 27 target through **Nembra ES80 Research**;
2. visible **Nembra Capture**, **Passive evidence only**, and foreground-only warnings;
3. one mechanically disambiguated candidate under the accepted first-capture procedure — never a choice based only on name/RSSI/candidate ID;
4. one **Start Capture** target session reaching **Capture Active** while stationary;
5. Nembra kept foregrounded with the screen awake for the accepted stationary evidence window;
6. one **Finish Capture** activation while safely stopped;
7. export of the prepared versioned JSON unchanged;
8. offline analysis before any Tuya framing or battery/current/power/speed field mapping is promoted.

If Nembra leaves the active foreground during live evidence capture, discard that attempt and repeat it; the shell intentionally refuses export from that session.

Expected first evidence is real advertisement identity, real GATT topology/properties, passive value streams, provenance, raw cadence, and continuity boundaries. It is **not** yet battery/current/power/speed semantics.

## Dependency / merge rule

This recovery intentionally targets the accepted #297 dependency branch while #353 owns the current-main passive-runtime re-anchor. It must not duplicate, rewrite, or race #353.

After #353 (or its successor) is accepted on then-current main, create/recover a fresh app-shell integration branch from that exact accepted descendant. Graft only this app-facing slice intentionally, refresh changed-path overlap against current main, and rerun exact-head Xcode 27 / iPhone 12 / iOS 27 acceptance before integration.

No ancestor, queued, skipped, or failed run becomes proof for a newer child head. Software/Simulator green is not physical AOVOPRO ES80 proof.
