# ES80 TODAY Final GO Operator Attestation — RETIRED / NON-AUTHORIZING

Status: **RETIRED. THIS HISTORICAL `ES80-FINGERPRINT-v1` / `NembraField.ipa` FINAL-GO PROCEDURE MUST NOT BE USED TO AUTHORIZE A PHYSICAL ES80 ATTEMPT.**

This document is retained only as an explicit retirement marker for the old passive TODAY procedure. It no longer defines a valid operator attestation, executable-bundle pin, Final-GO invocation, retained-IPA installation route, or physical authorization path.

The old executable `scripts/ci/es80_today_final_go_hardened.py` is intentionally non-authorizing for real invocation. Do not recover an older Git head or older blob merely to make that executable issue a historical `decision = GO`. Old exact-head success, old tooling pins, old retained artifacts, and old operator attestations are historical evidence only.

The current Nembra Capture physical-authorization path is the separately reviewed **`ES80-AUTHENTICATED-STATIONARY-v1`** control-plane lineage. Resolve its live exact head, accepted software/pixel subject, reviewed dependency and intended-device authority, signed field artifact, and current Final-GO evidence from live GitHub state. Do not infer any of those values from this retired file.

Until the current authenticated-stationary control plane explicitly produces an accepted Final-GO result for the exact accepted Capture candidate:

- **PHYSICAL STATUS: NO-GO**;
- do not scan the ES80 for the experiment;
- do not run the old passive workflow;
- do not repeat the old ride;
- do not substitute Simulator evidence, package-only success, ancestor green runs, or a historical TODAY record for current physical authority;
- do not use any Bluetooth write, DP query/control, reset, unbind, OTA, or scooter-command path.

Historical validator modules may remain in the repository for adversarial regression evidence. Their presence does not make the retired procedure operational authority.

If another document or script points here expecting a usable TODAY Final-GO attestation or an executable-bundle invocation recipe, treat that reference as a retirement signal and remain NO-GO rather than reconstructing the old procedure.
