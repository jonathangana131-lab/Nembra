#!/usr/bin/env python3
from pathlib import Path

producer_path = Path("scripts/ci/xcode27_signed_field_candidate.sh")
source = producer_path.read_text()

shell_anchor = "set -euo pipefail\n"
closed_path = """set -euo pipefail

# Field production must not select same-UID child executables from caller-controlled PATH. Establish
# one system-only search path before dirname, uname, git, xcodebuild, tee, or any other child process
# participates in source/provenance/private-input handling.
PATH=\"/usr/bin:/bin:/usr/sbin:/sbin\"
export PATH
"""
if source.count(shell_anchor) != 1:
    raise SystemExit("shell-options anchor drifted")
source = source.replace(shell_anchor, closed_path, 1)

old_python = """# Release evidence must not inherit interpreter selection or Python startup hooks from the caller.
# The SIP-protected system interpreter is fixed by absolute path and every invocation uses isolated
# mode, which ignores PYTHON* startup authority and excludes the user site directory.
PYTHON3=\"/usr/bin/python3\"
if [[ ! -x \"$PYTHON3\" ]]; then
  echo \"Signed field-candidate production requires the system Python 3 interpreter at $PYTHON3.\" >&2
  exit 2
fi
"""
new_python = """# Release evidence must not inherit interpreter selection or Python startup hooks from the caller.
# The system interpreter is fixed by absolute path and every invocation uses isolated mode. Because
# this interpreter receives private release-input paths and executes exact evidence subjects, its
# executable and complete canonical custody chain must also be root-owned and non-writable.
PYTHON3=\"/usr/bin/python3\"
validate_root_custodied_python() {
  local cursor=\"$PYTHON3\"
  local owner mode

  if [[ ! -f \"$cursor\" || ! -x \"$cursor\" || -L \"$cursor\" ]]; then
    echo \"Pinned Python executable must be one regular executable non-symlink: $cursor\" >&2
    return 1
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
if ! validate_root_custodied_python; then
  echo \"Signed field-candidate production requires a root-custodied system Python 3.\" >&2
  exit 2
fi
"""
if source.count(old_python) != 1:
    raise SystemExit("#1121 Python custody block drifted")
source = source.replace(old_python, new_python, 1)

required_preserved = [
    'exec 7< "$PRIVATE_RUNNER_SNAPSHOT"',
    'exec 8< "$INSPECTOR_SNAPSHOT"',
    'exec 9< "$PRIVATE_RUNNER_SNAPSHOT"',
    'os.pread(descriptor',
    '--repository-root "$ROOT"',
    'renamex_np',
]
for token in required_preserved:
    if token not in source:
        raise SystemExit(f"#1121/current producer protection disappeared: {token}")
producer_path.write_text(source)

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
        self.assertIn("validate_root_custodied_python", self.source)
        self.assertIn("Pinned Python custody path is not root-owned", self.source)
        self.assertIn("Pinned Python custody path is group/world writable", self.source)
        self.assertIn("Pinned Python custody path contains a symlink", self.source)
        self.assertIn("/usr/bin/stat -f", self.source)
        self.assertNotRegex(self.source, re.compile(r'^\s*python3(?:\s|$)', re.MULTILINE))

    def test_private_runner_is_started_in_isolated_mode(self):
        for descriptor in (7, 9):
            self.assertRegex(self.source, re.compile(rf'"\$PYTHON3"\s+-I\s+/dev/fd/{descriptor}\b'))

    def test_every_pinned_python_invocation_uses_isolated_mode(self):
        invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', self.source)
        self.assertTrue(invocations)
        non_isolated = [line for line in invocations if not re.search(r'"\$PYTHON3"\s+-I(?:\s|$)', line)]
        self.assertEqual(non_isolated, [])

    def test_root_custody_is_validated_before_first_python_invocation(self):
        validation = self.source.index("if ! validate_root_custodied_python; then")
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

    def test_closed_system_path_precedes_first_external_command(self):
        match = re.search(r'^PATH="/usr/bin:/bin:/usr/sbin:/sbin"\s*\nexport PATH$', self.source, re.MULTILINE)
        self.assertIsNotNone(match)
        path_index = match.start()
        self.assertGreater(path_index, self.source.index("set -euo pipefail"))
        self.assertLess(path_index, self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"'))
        self.assertLess(path_index, self.source.index('if [[ "$(uname -s)" != "Darwin" ]]'))

    def test_caller_path_cannot_be_restored_later(self):
        self.assertEqual(len(re.findall(r'(?m)^\s*PATH=', self.source)), 1)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\s*PATH=.*\$\{?PATH\}?'))

    def test_python_and_opened_tool_subject_custody_remain_composed(self):
        self.assertIn('PYTHON3="/usr/bin/python3"', self.source)
        self.assertIn("validate_root_custodied_python", self.source)
        for descriptor in (7, 8, 9):
            self.assertIn(f"/dev/fd/{descriptor}", self.source)
        self.assertIn("os.pread(descriptor", self.source)
        self.assertIn('--repository-root "$ROOT"', self.source)


if __name__ == "__main__":
    unittest.main()
''')

workflow_path = Path(".github/workflows/xcode27-pr-command.yml")
workflow = workflow_path.read_text()
needle = """          python3 -m py_compile scripts/ci/tests/test_xcode27_signed_field_candidate_python_custody_source.py
          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_python_custody_source.py
"""
addition = needle + """          python3 -m py_compile scripts/ci/tests/test_xcode27_signed_field_candidate_process_custody_source.py
          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_process_custody_source.py
"""
if workflow.count(needle) != 2:
    raise SystemExit(f"expected Python custody gate in two exact-head jobs, found {workflow.count(needle)}")
workflow = workflow.replace(needle, addition)
workflow_path.write_text(workflow)
