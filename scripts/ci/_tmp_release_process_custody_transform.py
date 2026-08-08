#!/usr/bin/env python3
from pathlib import Path
import re

PRODUCER = Path("scripts/ci/xcode27_signed_field_candidate.sh")
WORKFLOW = Path(".github/workflows/capture-producer-custody-source.yml")

source = PRODUCER.read_text(encoding="utf-8")

needle = "#!/bin/bash\nset -euo pipefail\n"
replacement = '''#!/bin/bash
set -euo pipefail

# Field-candidate production is an authority boundary. Replace caller executable discovery before
# dirname, uname, Git, Xcode, tee, or any other child process can observe private field inputs.
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
'''
if source.count(needle) != 1:
    raise SystemExit("producer header moved unexpectedly")
source = source.replace(needle, replacement, 1)

python_guard = '''PYTHON3="/usr/bin/python3"
if [[ ! -x "$PYTHON3" || -L "$PYTHON3" ]]; then
  echo "Signed field-candidate production requires the sealed system Python 3 at $PYTHON3." >&2
  exit 2
fi
'''
process_boundaries = python_guard + '''
GIT="/usr/bin/git"
if [[ ! -x "$GIT" || -L "$GIT" ]]; then
  echo "Signed field-candidate production requires the system Git executable at $GIT." >&2
  exit 2
fi

# Git defines dirty-tree admission, exact source identity, exact tool blobs, ignore policy, and the
# detached build subject. Execute it without caller GIT_* or system/global config authority and with
# replacement objects disabled so those meanings cannot be redefined by the invoking environment.
run_git() {
  /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \\
    GIT_NO_REPLACE_OBJECTS=1 GIT_TERMINAL_PROMPT=0 \\
    "$GIT" --no-replace-objects -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
}
'''
if source.count(python_guard) != 1:
    raise SystemExit("Python custody block moved unexpectedly")
source = source.replace(python_guard, process_boundaries, 1)

old_xcode = '''# Keep the producer compatible with the Bash 3.2 still shipped by macOS. Avoid optionally empty
# arrays under nounset; pass provisioning updates through one explicit wrapper instead.
run_xcodebuild() {
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    xcodebuild -allowProvisioningUpdates "$@"
  else
    xcodebuild "$@"
  fi
}
'''
new_xcode = '''# Keep signed-device build settings and toolchain selection outside caller environment authority.
# xcode-select chooses the installed developer directory; only that explicit selection and the closed
# system executable path enter xcodebuild. The same boundary handles version, archive, and export.
XCODE_SELECT="/usr/bin/xcode-select"
XCODEBUILD="/usr/bin/xcodebuild"
if [[ ! -x "$XCODE_SELECT" || -L "$XCODE_SELECT" || ! -x "$XCODEBUILD" || -L "$XCODEBUILD" ]]; then
  echo "Signed field-candidate production requires system xcode-select and xcodebuild." >&2
  exit 2
fi
SELECTED_DEVELOPER_DIR="$(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin "$XCODE_SELECT" -p)"
if [[ "$SELECTED_DEVELOPER_DIR" != /* || ! -d "$SELECTED_DEVELOPER_DIR" || -L "$SELECTED_DEVELOPER_DIR" ]]; then
  echo "System-selected Xcode developer directory is not one absolute non-symlink directory." >&2
  exit 2
fi

# Keep the producer compatible with the Bash 3.2 still shipped by macOS. Avoid optionally empty
# arrays under nounset; pass provisioning updates through one explicit closed-environment wrapper.
run_xcodebuild() {
  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" \\
      "$XCODEBUILD" -allowProvisioningUpdates "$@"
  else
    /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" \\
      "$XCODEBUILD" "$@"
  fi
}

XCODE_VERSION="$(run_xcodebuild -version)"
case "$XCODE_VERSION" in
  "Xcode 27"*) ;;
  *)
    echo "Signed field-candidate production requires Xcode 27 from $SELECTED_DEVELOPER_DIR." >&2
    printf '%s\\n' "$XCODE_VERSION" >&2
    exit 2
    ;;
esac
'''
if source.count(old_xcode) != 1:
    raise SystemExit("xcodebuild wrapper moved unexpectedly")
source = source.replace(old_xcode, new_xcode, 1)

# Route each shell-level Git authority operation through run_git while leaving comments/heredoc code alone.
lines = source.splitlines(keepends=True)
out = []
heredoc_terminator = None
for line in lines:
    stripped = line.strip()
    if heredoc_terminator is not None:
        out.append(line)
        if stripped == heredoc_terminator:
            heredoc_terminator = None
        continue
    heredoc = re.search(r"<<'([A-Za-z0-9_]+)'", line)
    if heredoc:
        heredoc_terminator = heredoc.group(1)
    if not line.lstrip().startswith("#") and "git " in line and "run_git " not in line:
        line = re.sub(r"(?<![A-Za-z0-9_])git ", "run_git ", line)
    out.append(line)
source = "".join(out)

raw_git = [
    line for line in source.splitlines()
    if re.search(r"(^|[;&|$(]\s*)git\s", line) and not line.lstrip().startswith("#")
]
if raw_git:
    raise SystemExit("raw authority Git invocation survived: " + " | ".join(raw_git))

PRODUCER.write_text(source, encoding="utf-8")

workflow = WORKFLOW.read_text(encoding="utf-8")
path_anchor = "      - scripts/ci/tests/test_xcode27_signed_field_candidate_descriptor_subject_custody_source.py\n"
path_add = path_anchor + '''      - scripts/ci/tests/test_xcode27_signed_field_candidate_process_custody_source.py
      - scripts/ci/tests/test_xcode27_signed_field_candidate_git_environment_custody_source.py
      - scripts/ci/tests/test_xcode27_signed_field_candidate_xcode_environment_custody_source.py
'''
if workflow.count(path_anchor) != 1:
    raise SystemExit("custody workflow path anchor moved unexpectedly")
workflow = workflow.replace(path_anchor, path_add, 1)

command_anchor = "          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_descriptor_subject_custody_source.py\n"
command_add = command_anchor + '''          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_process_custody_source.py
          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_git_environment_custody_source.py
          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_xcode_environment_custody_source.py
'''
if workflow.count(command_anchor) != 1:
    raise SystemExit("custody workflow command anchor moved unexpectedly")
WORKFLOW.write_text(workflow.replace(command_anchor, command_add, 1), encoding="utf-8")
