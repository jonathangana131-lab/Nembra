# NEMBRA DESIGN SYSTEM — v0.1

## Personality
Quiet precision. Native iOS at rest; instrument-grade while riding. No gamer RGB, fake carbon fiber, fake analog gauges, or giant grids of glass cards.

## Brand mark direction
An abstract `N` built from two route/trajectory strokes with a small forward cut. It should read as motion without looking like a racing logo.

## Typography
- System/SF family only in app UI.
- Portrait: semantic text styles wherever possible.
- Dashboard: fixed, tabular monospaced digits only where stable instrumentation demands it.
- Numeric units are visually subordinate and never cause width jumps.

## Spacing
Base rhythm: 4 pt.
- micro: 4
- compact: 8
- control interior: 12
- row/group: 16
- section: 24
- major separation: 32

Avoid arbitrary one-off spacing unless optical alignment genuinely needs it.

## Radius
- compact control: 14
- regular control/surface: 20
- hero surface: 28
Do not stack multiple rounded rectangles merely to make “cards.”

## Materials
- Normal content: solid/system backgrounds and restrained gradients.
- Liquid Glass: navigation chrome, primary floating controls, compact mode/action controls where interaction benefits from glass response.
- Never place a glass panel over another glass panel without a hierarchy reason.

## Color behavior
Use semantic system colors plus one restrained Nembra accent. Mode personality comes from hierarchy, motion, and subtle tint—not completely different RGB themes.

## Motion
- Controls acknowledge immediately with haptic/pressed feedback.
- Domain state does not visually commit until confirmed by service state.
- Springs are short and interruptible.
- Reduce Motion replaces spatial transforms with fades/state changes.
- Dashboard speed animation is display-only interpolation; raw telemetry is untouched.
- Rolling digits reserve fixed slot geometry. Carries roll upward when the display value rises; borrows roll downward when it falls. Leading digits appear/disappear inside reserved slots instead of resizing the number.
- Decimal precision and unit placement remain stable during motion; do not animate the unit itself.
- Rolling digits reserve fixed slot geometry. Carries roll upward when the value rises; borrows roll downward when it falls. Leading digits appear/disappear inside reserved slots instead of resizing the number.
- Decimal precision and unit placement remain stable during motion; do not animate the unit itself.

## Haptics
- light: selection/mode stepping
- rigid/medium: confirmed lock action
- success: important command confirmed where appropriate
- error: command failure/invalid test
Avoid haptic spam from continuously changing telemetry.

## Dashboard principles
1. speed is dominant,
2. glance time is minimal,
3. stopped controls disappear/reduce while moving,
4. nav transforms the composition instead of opening a separate-looking page,
5. mode changes personality subtly without hurting readability,
6. battery/connection warnings outrank decorative telemetry.
