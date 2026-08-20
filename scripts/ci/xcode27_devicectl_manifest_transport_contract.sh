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
import sys

copy_to = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
copy_from = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")


def require_contract(text: str, direction: str) -> None:
    required = (
        f"copy {direction}",
        "--domain-type",
        "--domain-identifier",
        "--source",
        "--destination",
    )
    missing = [token for token in required if token not in text]
    if missing:
        raise SystemExit(
            f"ERROR: devicectl copy-{direction} help is missing required app-container "
            "transfer controls: " + ", ".join(missing)
        )


require_contract(copy_to, "to")
require_contract(copy_from, "from")

# The accepted field design needs a bounded file rendezvous with one installed app's data container:
# stable retained-manifest bytes and the post-signing envelope travel TO the app, while the fresh
# process-local challenge rendezvous travels FROM the still-running app. This probe executes help
# only; it does not contact a device or transfer any file. Require the CoreDevice domain vocabulary
# when this Xcode build emits it, otherwise preserve both raw help artifacts for exact-head review
# instead of inventing an unsupported enum value.
for direction, text in (("TO", copy_to), ("FROM", copy_from)):
    if "appDataContainer" not in text:
        print(f"DEVICECTL_APP_DATA_DOMAIN_NOT_ENUMERATED_IN_COPY_{direction}_HELP")
    else:
        print(f"DEVICECTL_APP_DATA_DOMAIN_ENUMERATED_IN_COPY_{direction}_HELP")

print("DEVICECTL_COPY_TO_CONTRACT_PRESENT")
print("DEVICECTL_COPY_FROM_CONTRACT_PRESENT")
print("DEVICECTL_BIDIRECTIONAL_APP_CONTAINER_RENDEZVOUS_PRESENT")
PY

printf '%s\n' 'DEVICECTL_MANIFEST_CHALLENGE_ENVELOPE_TRANSPORT_PROBE_COMPLETE'