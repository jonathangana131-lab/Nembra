# Production Visual Audit — 2026-08-06

Worker: `chat-w6r8f`
Lane: `production-visual-audit`

## Evidence basis

This audit is grounded in the real **iPhone 12 / iOS 27 Simulator** output preserved by successful GitHub Actions run `31101483080` (`Xcode 27 Simulator QA`, run 411) at `main@3fcf0afd090b075373cbae113a27477c10a3dc4b`.

Reviewed preserved artifact: `nembra-xcode27-simulator-411-1`.

The artifact contains eleven scripted Home/state screenshots:

- `connected-stopped-light.png`
- `connected-stopped-dark.png`
- `riding-light.png`
- `low-battery-light.png`
- `reconnecting-light.png`
- `reconnecting-dark.png`
- `cold-disconnected-light.png`
- `bluetooth-off-light.png`
- `permission-denied-light.png`
- `scooter-unavailable-light.png`
- `unsupported-configuration-light.png`

It also contains XCTest screenshot attachments for:

- Dashboard moving/riding landscape;
- Dashboard Walk, Eco, Drive, Sport, and confirmed Sport stopped states;
- automatic ride active/recovered Home;
- completed-ride history;
- completed-ride details with durable route geometry.

The subsequent default-branch work through the lane claim base, `main@5763caf87ae2d955f9e4f93a8d7790c7c2229d52`, is dominated by research and CI infrastructure. A compare audit found no Home implementation path in that interval, and the current visual directives still explicitly classify these screens as systems-era baselines. This screenshot set is therefore valid for the structural critique below, while any later visual implementation must still recapture the newest exact head before editing.

## Overall judgment

The current UI is a **good functional evidence harness and a useful systems-era baseline, but it is not close to the required production visual bar**.

Its strongest qualities are truthful state separation, readable typography, safe controls, restrained color, and a Dashboard whose speed already dominates appropriately. Its main weakness is that the product still looks assembled from system groups, rows, pills, and labels rather than designed as one premium vehicle experience.

The permanent anti-goals are visible in the current screenshots:

- portrait Home reads as a sequence of rounded functional panels;
- landscape Dashboard leaves a very large black field around three isolated regions;
- completed rides expose evidence-system language directly in the primary product surface;
- floating tab chrome overlaps or visually competes with content in several captures;
- history uses a large amount of empty space without converting that space into useful ride context or product identity.

This is not a regression verdict. Those screenshots were accepted as intermediate functional baselines. The point of this audit is to prevent that intermediate composition from being accidentally treated as the final Nembra design.

## P0 — shell and content geometry

### 1. Floating tab chrome must not obscure content

The completed Ride Details capture shows the Home/Rides glass tab control sitting directly over the route map and the lower route/coverage area. Several Home captures similarly place the floating tab control over the bottom of the Vehicle surface / `All Vehicle Controls` region.

That is a release-quality layout defect, not merely a taste issue. Interactive navigation chrome may float, but content must reserve its footprint or scroll beneath it with a deliberate readable termination state.

**Production requirement:** define one root safe-content inset for floating navigation chrome and verify the final visible row/map annotation remains fully readable and tappable at the scroll limit on iPhone 12.

### 2. Portrait screens need a deliberate bottom termination

Home currently ends with a rounded Vehicle group while the tab control hovers on top of the same visual zone. Ride Details terminates beneath an overlapping tab control. Rides leaves a very large blank canvas between the single ride row and the bottom control.

**Production requirement:** bottom whitespace should feel intentional and should never be used to hide a collision. Lists/detail screens need enough inset for chrome, but the composition should still have a designed endpoint.

## P1 — Portrait Home

### What works

- Connection truth is readable and never disguised as live data.
- Reconnecting correctly distinguishes `Last known vehicle data`.
- Low battery receives semantic red emphasis without turning the whole screen red.
- State-changing controls visibly become unavailable when the domain says they are unavailable.
- The screen remains understandable in both light and dark appearances.

### What currently feels intermediate

1. **The signature data is visually subordinate.** Battery, trip, and mode share an equal three-column status card. Battery is supposed to become one of Nembra's signature interactions, including `% ↔ estimated remaining range`, yet it currently has no hero-level identity.
2. **The composition is card/section driven instead of vehicle-state driven.** Header → recovery card → metrics card → Controls → segmented Ride Mode → Vehicle rows is functionally logical but visually resembles a polished settings/control form.
3. **Repeated rounded containers flatten hierarchy.** Recovery, status, controls, mode background, Vehicle group, pills, and the floating tab control all compete with similar soft geometry.
4. **Nembra's own identity is weak.** The small centered navigation title, system-blue links, SF Symbols, and standard grouped surfaces are coherent iOS, but almost nothing yet feels recognizably Nembra.
5. **Connection problem states are too compositionally similar.** Bluetooth off, permission denied, scooter unavailable, unsupported configuration, and cold disconnected all become variants of a gray recovery strip followed by disabled product sections. Their factual wording differs, but glance-level priority does not differ enough.
6. **Active ride state is only a banner addition.** `Ride automatically` / `Ride resumed` sits above the same Home stack. A real live ride should make the product feel meaningfully alive while keeping the automatic-domain truth unchanged.

### Production direction

Do not solve this by making larger cards or adding decorative scooter art.

The next Home composition should be organized around a **single vehicle-status field**:

- identity + connection + lock form one compact top cluster;
- battery/range becomes the primary interactive instrument;
- trip/ride context and confirmed mode become supporting data, not equal tiles;
- immediate controls live as compact native actions attached to the current vehicle state;
- deeper configuration becomes disclosure/navigation rather than another primary card;
- active ride context is integrated into the same state field instead of bolted on above it.

Until authoritative battery/range dependencies are accepted, the final instrument must not invent range, current, watts, or fake high-resolution SoC. Layout work can reserve the interaction contract without fabricating its inputs.

## P1 — Landscape Dashboard

### What works

- Speed is unmistakably the primary glance target.
- Moving state hides state-changing controls.
- Confirmed mode personality is restrained and monochrome.
- Battery/trip/connection remain visible without overtaking speed.
- The existing three-subtree structure is compatible with localized high-frequency speed rendering.

### What currently feels intermediate

1. **The screenshot matches the explicit anti-goal of a large unused black region too closely.** The moving Dashboard is essentially a left status rail, a central number, and a right mode rail suspended in black space. The dark field makes the speed legible but does not yet feel like an authored cockpit architecture.
2. **Side rails read as developer instrumentation.** Upper-left model/connection, lower-left battery/trip, upper-right mode, lower-right moving-controls message are isolated informational islands rather than one composition.
3. **Stopped mode controls use `W / E / D / S`.** They are compact, but the visual grammar is cryptic and more prototype-like than premium. Accessibility labels solve VoiceOver, not visible comprehension.
4. **`Controls available when stopped` occupies valuable visual territory while moving.** Safety behavior is correct, but the persistent sentence is weak cockpit content. The absence of controls can communicate the restriction; a short transient affordance/help treatment can explain it when necessary.
5. **Battery is still a text metric, not the signature battery/range instrument required by the product.** The future toggle must integrate without turning the left rail into another card.
6. **Ride context is thin.** Moving state has trip but no integrated duration/route/navigation composition yet, leaving the central architecture underused.

### Production direction

Preserve the localized speed subtree and truthful moving/stopped control rules, but redesign the surrounding frame:

- speed remains the dominant visual anchor;
- battery/range becomes one compact signature instrument rather than a label/value pair;
- trip + ride duration form a coherent secondary ride cluster when evidence exists;
- model/connection collapses to a quieter status identity unless attention is required;
- confirmed mode becomes a compact readable treatment; stopped selection should not require memorizing four initial letters;
- navigation should later claim a deliberate region and rebalance the same cockpit rather than open a separate visual language;
- negative space remains generous, but every occupied region should align to one invisible cockpit grid so the screen feels intentional rather than empty.

Do not add fake gauges, power meters, tachometers, or decorative telemetry to fill space.

## P1 — Rides list

The current single-ride capture is truthful but looks like a developer validation screen:

- the primary row is a large white rounded rectangle with a completion check, timestamp, `ODO` label, and chevron;
- a full explanatory paragraph below the row explains evidence reconciliation;
- most of the screen is then empty.

### Production direction

- Make a ride recognizable as a trip, not as a ledger row. Use date/time, truthful distance state, duration when legitimate, and route/location context when recorded.
- Preserve source uncertainty, but move long evidence-system prose behind a concise disclosure or detail affordance. Primary history should not teach the internal reconciliation architecture every time the user opens it.
- A route thumbnail is valuable when route geometry exists; when no route exists, the absence must remain truthful rather than replaced by a fake map.
- Period summaries/stats can eventually use the currently empty upper/lower space once those aggregates are accepted. Do not fabricate them merely to make the screen fuller.

## P1 — Ride Details

The route screenshot proves important real pipeline behavior, but the presentation is visibly diagnostic:

- `Ride timeline` exposes Started / Confirmed / Ended timestamps and `Continuity — Uninterrupted process` as a large primary card;
- `Distance evidence` exposes `Scooter odometer delta` plus a paragraph explaining internal evidence reconciliation;
- route map is useful but is partially obstructed by persistent tab chrome in the captured scroll position;
- coverage/evidence terminology dominates the product hierarchy.

### Production direction: progressive disclosure of truth

Truthfulness does **not** require putting every internal evidence term at the top level.

Use three disclosure layers:

1. **Glance layer:** when, how far (with explicit unresolved/partial state if needed), duration, map/route availability.
2. **Evidence layer:** concise source chips/rows such as scooter distance, GPS coverage, partial recording, recovered ride.
3. **Technical detail:** exact continuity/timestamps/source-reconciliation information for debugging, support, or an explicit `Recording details` disclosure.

Never collapse unknown/partial evidence into a fake final ride total. The redesign changes information hierarchy, not truth semantics.

## P1 — Connection and error-state family

The current state matrix is comprehensive, which is a major asset. The visual system should now distinguish **attention level** without turning everything into warnings.

Suggested hierarchy:

- routine offline/reconnecting: quiet status treatment;
- actionable local permission/Bluetooth state: clear single action with concise explanation;
- scooter unavailable: reconnect action plus proximity/power guidance;
- unsupported hardware/firmware: stronger protective state explaining why controls are intentionally blocked;
- low battery: vehicle-status emphasis that remains visible across Home and Dashboard.

Keep the factual copy and fail-closed domain behavior. Redesign the containers and emphasis.

## Nembra identity opportunities

Do not manufacture branding with a giant logo, RGB color, fake carbon, or decorative scooter renders.

A stronger identity can come from:

- the planned route/trajectory `N` mark used sparingly;
- a consistent signature battery/range silhouette and motion language;
- a distinctive but restrained cockpit grid;
- one Nembra accent for interactive emphasis;
- stable numerical typography and rolling transitions;
- coherent route/map treatments;
- transition choreography between Home → riding → Dashboard/navigation.

The product should be recognizable by its instrumentation and interaction behavior even if the word `Nembra` is hidden.

## Motion audit requirements for the redesign

Static screenshots cannot accept:

- speed roll/interpolation;
- battery integer transitions;
- `% ↔ range` toggle;
- confirmed mode changes;
- connection/reconnection transitions;
- automatic ride activation/recovery;
- Dashboard moving/stopped control changes;
- navigation insertion/removal;
- route/map camera changes.

Every final implementation checkpoint must test normal motion and Reduce Motion. Presentation frames never become telemetry evidence.

## Performance guardrails

Visual redesign must preserve the current good architectural direction:

- keep the speed refresh subtree localized;
- do not make a whole Home/Dashboard tree tick at display rate for battery/speed animation;
- keep map route reconstruction out of frame-rate update paths;
- avoid stacked material/blur layers merely to create depth;
- profile Dashboard + map/navigation together on the iPhone 12 baseline;
- test long rides/history growth, not just clean one-item fixtures.

The active `swiftui-performance-audit` lane owns concrete Dashboard invalidation changes; this audit deliberately does not edit those files.

## Recommended visual implementation order

This is sequencing guidance, not a competing implementation claim.

1. **App shell / safe-area geometry** — eliminate floating-tab content obstruction everywhere.
2. **Battery/range interaction contract** — after the accepted truth/readout dependencies exist, make this the signature cross-surface instrument.
3. **Portrait Home composition** — collapse card soup into one cohesive vehicle-state hierarchy.
4. **Landscape Dashboard frame** — preserve speed core, redesign side context and stopped controls, then integrate battery/range.
5. **Rides list + Ride Details** — progressive disclosure, route-first product hierarchy, truthful evidence details beneath it.
6. **Navigation cockpit transformation** — after route/progress/reroute contracts are accepted.
7. **State-family pass** — offline/reconnect/permission/unsupported/low-battery consistency across surfaces.
8. **Motion, haptics, accessibility, performance** — repeated runtime iteration, not a final cleanup checkbox.

## Screenshot acceptance matrix for the eventual production pass

At minimum, recapture and critique these real iPhone 12 / iOS 27 states after each material redesign:

### Home
- connected/stopped light + dark;
- automatic ride active;
- automatic ride recovered;
- low battery;
- reconnecting with last-known data light + dark;
- cold disconnected;
- Bluetooth off;
- permission denied;
- scooter unavailable;
- unsupported configuration.

### Dashboard
- moving/riding;
- stopped Walk / Eco / Drive / Sport;
- confirmed-mode transition result;
- low battery while riding;
- reconnecting while a ride is still legitimately continuous;
- Reduce Motion;
- navigation active, rerouting, and navigation ended once those systems exist.

### Rides
- empty history;
- one ride;
- long history;
- ride with full/partial/no route;
- ride with unresolved distance evidence;
- recovered ride;
- map/detail scrolled to the bottom with floating navigation chrome visible.

## Acceptance boundary

This audit intentionally changes **no production UI or domain behavior**. It does not claim that the final overhaul should begin before its truthful dependencies are sufficiently mature, and it does not make physical ES80, outdoor GPS, or physical-iPhone performance claims.

Its actionable conclusion is narrower: **the current functional UI must not be visually frozen**. The real Simulator evidence already demonstrates specific structural problems — especially tab/content overlap, card-driven Home hierarchy, diagnostic ride presentation, and under-authored Dashboard negative space — that the mandatory Production Visual + Performance Overhaul must solve through repeated real-runtime iteration.
