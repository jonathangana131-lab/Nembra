# NEMBRA CAPTURE — ONE-TIME UTILITY CONTRACT

This file defines the product scope of **Nembra Capture** before the first real AOVOPRO ES80 artifact.

## Purpose

Nembra Capture exists to do one job well:

**Collect the real Bluetooth / timing / packet / provenance evidence needed to teach the main Nembra app how to truthfully recognize, connect to, observe, and later integrate the ES80.**

It is a temporary research/field utility, not a second consumer app and not a long-lived flagship surface.

The expected lifecycle is:

1. open Capture;
2. find/connect to the intended ES80 candidate safely;
3. perform the guided stationary passive OFF -> ON -> OFF -> ON correlation;
4. observe for the required window;
5. seal the exact artifact;
6. verify integrity;
7. share/export one analysis-ready JSON artifact;
8. preserve that raw artifact unchanged;
9. use the resulting evidence to continue the real Nembra product.

After the first useful physical artifact, engineering gravity should move from improving Capture toward using the evidence in the main Nembra app: Bluetooth identity/connection, telemetry semantics, battery/range, power/speed, controls when physically verified, Dashboard, Vehicle, and the rest of the product.

## Product-quality target

Capture must be **simple, clean, obvious, safe, and trustworthy**.

It must NOT become:
- a second premium Nembra app;
- a showcase dashboard;
- a giant engineering console;
- a UUID/GATT/hex/DP browser on its primary surface;
- a debug-looking wall of text;
- a visual-polish sink that delays the first ES80 artifact;
- a place to duplicate long-term Dashboard/Battery/Vehicle product experiences.

The correct bar is a polished utility, not a masterpiece product surface.

A good first-run user should understand the flow without Bluetooth expertise:

**Find scooter -> Start capture -> follow the safe prompts -> Capture complete -> Share capture.**

Engineering details may exist behind a secondary disclosure for diagnosis, but raw UUIDs, GATT internals, packet hex, DP speculation, signing internals, and provenance machinery should not dominate the primary workflow.

## Visual rule

Do enough design work that Capture does not feel ugly, broken, confusing, or like an internal debug build.

Required visual qualities:
- clear hierarchy;
- readable state and safety instructions;
- obvious primary action;
- calm progress/status feedback;
- good portrait layout and usable compact landscape where required for acceptance;
- reasonable Dynamic Type/VoiceOver/contrast for the actual field path;
- explicit Simulator/QA disclosure when synthetic;
- clear COMPLETE / SHARE state.

Not required before the first artifact:
- bespoke flagship motion systems;
- ornamental haptics;
- elaborate glass choreography;
- deep visual experimentation;
- exhaustive cosmetic state perfection;
- premium dashboard-style instrumentation;
- optional accessibility polish that does not block the actual field path.

If a visual change does not make the one-time field workflow clearer, safer, easier, or acceptance-capable, it is normally **POST-CAPTURE**.

## Engineering rule

Capture needs enough engineering quality to reliably produce the one artifact Nembra needs.

TODAY blockers are limited to defects that can plausibly:
- prevent build/install/launch;
- crash/hang/corrupt the normal capture path;
- select the wrong/ambiguous peripheral;
- bypass stationary or charger-disconnected safety;
- permit an unauthorized application characteristic write/command;
- prevent the required observation/correlation flow;
- produce mutable/wrong/unexportable final bytes;
- prevent exact-head acceptance needed for the research build;
- prevent production/install/recognition of the exact intended Research Field Build;
- prevent the first safe passive artifact.

Release-grade hostile-host hardening, exotic filesystem races, forensic publication custody, speculative analyzer hardening, and similar work are deferred unless a concrete normal-path failure promotes them.

## One-time means optimize for data unlock

Do not spend another day turning Capture into a forever product.

Once the utility is safe, clear, buildable, installable, and capable of producing the required artifact, freeze it and run the experiment.

The artifact is the unlock. The main Nembra app is the product.

## After the first artifact

Immediately prioritize extracting durable reusable truth into Nembra rather than continuing Capture aesthetics:
- physical peripheral/advertisement fingerprint evidence;
- service/characteristic/notification source evidence;
- timing and continuity;
- framing/Tuya/DP candidate analysis;
- repeatability confidence;
- battery/voltage/current/power/speed semantics only when physically supported;
- command/control semantics only with strong evidence and explicit authorization;
- production Bluetooth service/profile architecture;
- real Dashboard/Battery/Range/Vehicle integration.

Capture may remain as a hidden/research diagnostic tool if useful, but it should not compete with Nembra's primary product surfaces for swarm capacity.

## Swarm scheduling consequence

While Capture is blocked on Xcode/signing/device/physical access, only the minimum closure crew stays attached. Overflow workers must develop the real Nembra app under `ADAPTIVE_SWARM_PRIORITY.md`.

Even when Capture has actionable work, visual/product workers should ask:

**Does this materially improve the one-time safe evidence workflow?**

If no, move to Dashboard/Cockpit, Battery/Range, Rides/Records, Navigation, Home, Vehicle/Controls, or another real Nembra closure lane.

## Truth boundary

A successful Capture artifact does not magically prove every ES80 feature. It supplies physical evidence for analysis. Only evidence that survives repeatable analysis/validation may become production Nembra truth.

Never fabricate Bluetooth identity, GATT/DP semantics, electrical units/scales, speed semantics, command acknowledgement, or hardware behavior.
