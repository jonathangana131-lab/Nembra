#!/usr/bin/env python3
from pathlib import Path

producer = Path("scripts/ci/xcode27_signed_field_candidate.sh")
source = producer.read_text()

shell_anchor = "set -euo pipefail\n"
closed_path = """set -euo pipefail

# Field production must not select same-UID child executables from caller-controlled PATH. Establish
# one system-only executable search path before dirname, uname, git, xcodebuild, tee, or any other
# child process participates in source/provenance/private-input handling.
PATH=\"/usr/bin:/bin:/usr/sbin:/sbin\"
export PATH
"""
if source.count(shell_anchor) != 1:
    raise SystemExit("shell-options anchor drifted")
source = source.replace(shell_anchor, closed_path, 1)

python_anchor = """unset NEMBRA_INTENDED_FIELD_DEVICE_UDID

# Produce one exact signed iOS Nembra Capture field-build CANDIDATE.
"""
python_assignment = """unset NEMBRA_INTENDED_FIELD_DEVICE_UDID

# Python participates directly in private-input validation and evidence admission. It is selected by
# one absolute system path and every invocation below uses isolated mode so caller PYTHON* startup
# or import state cannot gain authority before descriptor-bound source executes.
PYTHON3=\"/usr/bin/python3\"

# Produce one exact signed iOS Nembra Capture field-build CANDIDATE.
"""
if source.count(python_anchor) != 1:
    raise SystemExit("Python assignment anchor drifted")
source = source.replace(python_anchor, python_assignment, 1)

platform_anchor = """if [[ \"$(uname -s)\" != \"Darwin\" ]]; then
  echo \"Signed iOS field-candidate production requires macOS.\" >&2
  exit 2
fi

"""
custody_block = platform_anchor + """# The fixed Python path is security-sensitive because it receives the private intended-device file
# path and executes evidence code. Require root-owned, non-writable, non-symlink custody from the
# executable through every canonical parent before the first Python process starts.
validate_root_custodied_path() {
  local candidate=\"$1\"
  local kind=\"$2\"
  local cursor=\"$candidate\"
  local owner mode

  if [[ \"$kind\" == \"file\" ]]; then
    if [[ ! -f \"$cursor\" || ! -x \"$cursor\" || -L \"$cursor\" ]]; then
      echo \"Pinned Python executable must be one regular executable non-symlink: $cursor\" >&2
      return 1
    fi
  fi

  while :; do
    if [[ -L \"$cursor\" ]]; then
      echo \"Pinned Python custody path contains a symlink: $cursor\" >&2
      return 1
    fi
    owner=\"$(/usr/bin/stat -f '%u' \"$cursor\")\" || return 1
    mode=\"$(/usr/bin/stat -f '%Sp' \"$cursor\")\" || return 1
    if [[ \"$owner\" != \"0\" ]]; then
      echo \"Pinned Python custody path is not root-owned: $cursor\" >&2
      return 1
    fi
    if [[ \"${mode:5:1}\" == \"w\" || \"${mode:8:1}\" == \"w\" ]]; then
      echo \"Pinned Python custody path is group/world writable: $cursor\" >&2
      return 1
    fi
    [[ \"$cursor\" == \"/\" ]] && break
    cursor=\"$(/usr/bin/dirname \"$cursor\")\"
  done
}
if ! validate_root_custodied_path \"$PYTHON3\" file; then
  echo \"Signed field-candidate production requires a root-custodied system Python 3.\" >&2
  exit 2
fi

"""
if source.count(platform_anchor) != 1:
    raise SystemExit("Darwin platform anchor drifted")
source = source.replace(platform_anchor, custody_block, 1)

occurrences = source.count("python3 ")
if occurrences < 10:
    raise SystemExit(f"expected at least ten producer python3 invocations, found {occurrences}")
source = source.replace("python3 ", '"$PYTHON3" -I ')

env_anchor = """  echo \"physical_authorization=not-granted\"
  xcodebuild -version
"""
env_replacement = """  echo \"physical_authorization=not-granted\"
  \"$PYTHON3\" -I --version
  xcodebuild -version
"""
if source.count(env_anchor) != 1:
    raise SystemExit("field-candidate environment-record anchor drifted")
source = source.replace(env_anchor, env_replacement, 1)

required_preserved = [
    '--repository-root "$ROOT"',
    'NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE',
    'PRIVATE_RUNNER_SNAPSHOT',
    'INSPECTOR_SNAPSHOT',
    'FINAL_STAGING_OWNED=0',
    'renamex_np',
]
for token in required_preserved:
    if token not in source:
        raise SystemExit(f"current producer protection disappeared: {token}")

producer.write_text(source)

python_test = Path("scripts/ci/tests/test_xcode27_signed_field_candidate_python_custody_source.py")
python_test.write_text(r'''#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidatePythonCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_producer_pins_root_custodied_system_python(self):
        self.assertRegex(self.source, re.compile(r'^PYTHON3="/[^"]*/python3"$', re.MULTILINE))
        self.assertIn('validate_root_custodied_path "$PYTHON3" file', self.source)
        self.assertIn("Pinned Python custody path is not root-owned", self.source)
        self.assertIn("Pinned Python custody path is group/world writable", self.source)
        self.assertIn("Pinned Python custody path contains a symlink", self.source)
        self.assertNotRegex(self.source, re.compile(r'^\s*python3(?:\s|$)', re.MULTILINE))

    def test_private_runner_is_started_in_isolated_mode(self):
        for descriptor in (7, 9):
            self.assertRegex(self.source, re.compile(rf'"\$PYTHON3"\s+-I\s+/dev/fd/{descriptor}\b'))

    def test_every_pinned_python_invocation_uses_isolated_mode(self):
        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations)
        self.assertEqual([line for line in invocations if not re.search(r'"\$PYTHON3"\s+-I(?:\s|$)', line)], [])

    def test_pinned_python_is_validated_before_first_invocation(self):
        validation = self.source.index('validate_root_custodied_path "$PYTHON3" file')
        first_invocation = self.source.index('"$PYTHON3" -I')
        self.assertLess(validation, first_invocation)


if __name__ == "__main__":
    unittest.main()
''')

process_test = Path("scripts/ci/tests/test_xcode27_signed_field_candidate_process_custody_source.py")
process_test.write_text(r'''#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"


class SignedFieldCandidateProcessCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = PRODUCER.read_text()

    def test_trusted_system_path_is_established_before_first_external_command(self):
        match = re.search(r'^PATH="/usr/bin:/bin:/usr/sbin:/sbin"\s*\nexport PATH$', self.source, re.MULTILINE)
        self.assertIsNotNone(match)
        path_index = match.start()
        self.assertGreater(path_index, self.source.index("set -euo pipefail"))
        self.assertLess(path_index, self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"'))
        self.assertLess(path_index, self.source.index('if [[ "$(uname -s)" != "Darwin" ]]'))

    def test_caller_path_cannot_be_restored_later(self):
        self.assertEqual(len(re.findall(r'(?m)^\s*PATH=', self.source)), 1)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*PATH=.*\$\{?PATH\}?'))

    def test_python_is_pinned_and_isolated_in_addition_to_global_path_custody(self):
        self.assertIn('PYTHON3="/usr/bin/python3"', self.source)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*python3(?:\s|$)'))
        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations)
        for invocation in invocations:
            self.assertRegex(invocation, re.compile(r'"\$PYTHON3"\s+-I(?:\s|$)'))


if __name__ == "__main__":
    unittest.main()
''')
