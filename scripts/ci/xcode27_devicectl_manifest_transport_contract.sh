#!/bin/bash
set -euo pipefail

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || {
  echo 'ERROR: devicectl transport contract must run on the Xcode Mac.' >&2
  exit 2
}

: "${ARTIFACTS_DIR:?ARTIFACTS_DIR must identify the exact-head Xcode artifact directory.}"
/bin/mkdir -p "$ARTIFACTS_DIR"

copy_to_help="$ARTIFACTS_DIR/devicectl-device-copy-to-help.txt"
copy_from_help="$ARTIFACTS_DIR/devicectl-device-copy-from-help.txt"

if ! /usr/bin/xcrun devicectl help device copy to >"$copy_to_help" 2>&1; then
  cat "$copy_to_help" >&2
  echo 'ERROR: Xcode devicectl does not expose device copy to on this runner.' >&2
  exit 3
fi

if ! /usr/bin/xcrun devicectl help device copy from >"$copy_from_help" 2>&1; then
  cat "$copy_from_help" >&2
  echo 'ERROR: Xcode devicectl does not expose device copy from on this runner.' >&2
  exit 4
fi

/usr/bin/python3 -I -B - "$copy_to_help" "$copy_from_help" <<'PY'
from pathlib import Path
import re
import sys

copy_to = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
copy_from = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")


def require_contract(text: str, direction: str) -> None:
    required = (
        f"copy {direction}",
        "--device",
        "--domain-type",
        "--domain-identifier",
        "--source",
        "--destination",
    )
    missing = [token for token in required if token not in text]
    if missing:
        raise SystemExit(
            f"ERROR: devicectl copy-{direction} help is missing required transfer controls: "
            + ", ".join(missing)
        )


require_contract(copy_to, "to")
require_contract(copy_from, "from")

# The accepted field design needs a bounded file rendezvous with one installed app's data container:
# stable retained-manifest bytes and the post-signing envelope travel TO the app, while the fresh
# process-local challenge rendezvous travels FROM the still-running app. This probe executes help
# only; it does not contact a device or transfer any file. Generic copy support is insufficient:
# exact-head evidence must name the appDataContainer domain in both directions and must document
# that the domain identifier for that domain is the app bundle ID. That keeps later transport tied
# to one explicit installed-app identity instead of a caller-invented container label.
missing_domain_evidence = []
missing_bundle_identity_evidence = []
for direction, text in (("TO", copy_to), ("FROM", copy_from)):
    if "appDataContainer" not in text:
        print(f"DEVICECTL_APP_DATA_DOMAIN_NOT_ENUMERATED_IN_COPY_{direction}_HELP")
        missing_domain_evidence.append(direction.lower())
    else:
        print(f"DEVICECTL_APP_DATA_DOMAIN_ENUMERATED_IN_COPY_{direction}_HELP")

    normalized = re.sub(r"\s+", " ", text)
    if "identifier is the bundle ID of the app" not in normalized:
        print(f"DEVICECTL_APP_DATA_BUNDLE_IDENTIFIER_SEMANTICS_MISSING_IN_COPY_{direction}_HELP")
        missing_bundle_identity_evidence.append(direction.lower())
    else:
        print(f"DEVICECTL_APP_DATA_BUNDLE_IDENTIFIER_SEMANTICS_PRESENT_IN_COPY_{direction}_HELP")

print("DEVICECTL_COPY_TO_CONTRACT_PRESENT")
print("DEVICECTL_COPY_FROM_CONTRACT_PRESENT")
if missing_domain_evidence:
    raise SystemExit(
        "ERROR: appDataContainer transport is not proven by exact Xcode help in direction(s): "
        + ", ".join(missing_domain_evidence)
    )
if missing_bundle_identity_evidence:
    raise SystemExit(
        "ERROR: appDataContainer bundle-ID identity semantics are not proven by exact Xcode help in direction(s): "
        + ", ".join(missing_bundle_identity_evidence)
    )
print("DEVICECTL_BIDIRECTIONAL_APP_CONTAINER_BUNDLE_IDENTITY_PRESENT")
print("DEVICECTL_BIDIRECTIONAL_APP_CONTAINER_RENDEZVOUS_PRESENT")
PY

printf '%s\n' 'DEVICECTL_MANIFEST_CHALLENGE_ENVELOPE_TRANSPORT_PROBE_COMPLETE'