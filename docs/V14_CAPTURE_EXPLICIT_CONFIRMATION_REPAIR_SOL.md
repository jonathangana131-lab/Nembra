# V14 Capture explicit target confirmation repair

Protocol: V14
Feature: Nembra Capture / ES80 authenticated stationary preflight
Lane: explicit operator target-confirmation closure
Exact parent: `integration/v14-capture-final-stationary-convergence-sol@a21dad534fac750de74ce02d478a24bc96aa0e6f`
Status: ACTIVE REPAIR CHECKPOINT / PHYSICAL NO-GO

## Live defect

The composed lineage contains the expected-red `TuyaExplicitCorrelatedTargetConfirmationSourceTests`, but `SecureLinkController.finishCorrelationSeries(_:)` still auto-promotes `.singleRepeatableCandidate(id)` by assigning `selectedID = id`, changing `phase = .selected`, and logging `candidate_selected` immediately after the package-owned OFF1 -> ON1 -> OFF2 -> ON2 correlation.

That violates the V14 authority ladder. Fresh repeated correlation earns only a **correlated Bluetooth target / current-session correlation evidence**. It does not earn operator selection and does not establish permanent ES80 identity.

## Required production repair

On the next Entrypoint edit, keep the unique candidate in `byID` / `candidates` but do not assign `selectedID` and do not enter `.selected` inside `finishCorrelationSeries(_:)`. Retire `correlationSession`, present a pending confirmation state/message, and expose an explicit `confirmCorrelatedTarget` action.

`confirmCorrelatedTarget` must:

1. require exactly one still-current `freshlyCorrelated` candidate;
2. re-check current SDK login, exact-device membership, and `accountIdentityLeaseIsAuthorized` before promotion;
3. assign `selectedID` only inside this explicit operator action;
4. set `phase = .selected` only after that action;
5. log `candidate_selected` with authority wording that remains correlation-local, not permanent identity;
6. leave authentication gated by the selected candidate plus the independent official-Tuya same-account membership/UID lease.

The primary discovery UI must visibly offer confirmation after the four-window series succeeds and before the authentication card can proceed. Copy must use the earned level: **correlated Bluetooth target** / **current-session correlation evidence**.

## Reset / invalidation invariant

Any account/membership invalidation, discovery reset, new OFF1 attempt, or terminal failure before confirmation must clear the pending correlated candidate so a stale candidate cannot be confirmed into a later attempt.

## Acceptance

The already-composed explicit-confirmation source contract is the minimum executable regression. Final acceptance still belongs to one exact composed head carrying lifecycle settlement ownership, no-clock terminal truth, fresh four-window correlation, authoritative field-build presentation, this explicit confirmation repair, and the remaining private intended-device provenance gates.

Do not spend physical field time on this checkpoint. **NO-GO / DO NOT SCAN / DO NOT RUN** until the final composed exact app build passes required package/source + Xcode 27 runtime acceptance and the field gate explicitly flips to GO.
