# ES80 TODAY Export Readiness Truth — RETIRED / NON-AUTHORIZING

Status: **RETIRED HISTORICAL CLARIFICATION. PHYSICAL STATUS: NO-GO.**

This file clarified export-readiness semantics for the superseded private TODAY / `ES80-FINGERPRINT-v1` lane. It no longer participates in the physical authority order and must not direct an operator back into a retired TODAY runbook.

The current Nembra Capture physical procedure is `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md` with procedure identifier **`ES80-AUTHENTICATED-STATIONARY-v1`**. Current shipping source plus that procedure and its accepted exact-head Final-GO authority win over this historical clarification.

One product-truth invariant remains useful: export readiness is not a speculative pre-scan filesystem certificate. Authoritative Share/export readiness is earned only after the accepted evidence prefix is sealed, the finalized Share bytes exist, and the current integrity contract accepts those exact bytes. A later external Share destination may still fail operationally without retroactively changing capture truth.

That invariant does not authorize Bluetooth activity, build/sign/install acceptance, Tuya authentication, physical identity, protocol semantics, or telemetry. Until the current authenticated-stationary control plane explicitly earns GO for one exact accepted candidate, **PHYSICAL STATUS: NO-GO / DO NOT SCAN / DO NOT RUN**.
