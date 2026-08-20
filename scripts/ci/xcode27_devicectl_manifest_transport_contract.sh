#!/bin/bash
set -euo pipefail

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || {
  echo 'ERROR: devicectl transport contract must run on the Xcode Mac.' >&2
  exit 2
}

: "${ARTIFACTS_DIR:?ARTIFACTS_DIR must identify the exact-head Xcode artifact directory.}"
/bin/mkdir -p "$ARTIFACTS_DIR"

help_file="$ARTIFACTS_DIR/devicectl-device-copy-to-help.txt"
if ! /usr/bin/xcrun devicectl help device copy to >"$help_file" 2>&1; then
  cat "$help_file" >&2
  echo 'ERROR: Xcode devicectl does not expose device copy to on this runner.' >&2
  exit 3
fi

/usr/bin/python3 -I -B - "$help_file" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
required = (
    "copy to",
    "--domain-type",
    "--domain-identifier",
    "--source",
    "--destination",
)
missing = [token for token in required if token not in text]
if missing:
    raise SystemExit("ERROR: devicectl copy-to help is missing required app-container transfer controls: " + ", ".join(missing))

# The accepted field design needs a file copied into one installed app's data container, never an
# app-group or bundle rewrite. Require the CoreDevice domain vocabulary when this Xcode build emits
# it in subcommand help; otherwise leave the raw help artifact for exact-head review rather than
# inventing an unsupported enum value.
if "appDataContainer" not in text:
    print("DEVICECTL_APP_DATA_DOMAIN_NOT_ENUMERATED_IN_SUBCOMMAND_HELP")
else:
    print("DEVICECTL_APP_DATA_DOMAIN_ENUMERATED")
print("DEVICECTL_COPY_TO_CONTRACT_PRESENT")
PY

printf '%s\n' 'DEVICECTL_MANIFEST_TRANSPORT_PROBE_COMPLETE'
