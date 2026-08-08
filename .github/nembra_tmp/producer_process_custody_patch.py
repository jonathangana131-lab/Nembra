#!/usr/bin/env python3
from pathlib import Path
import re

producer_path = Path("scripts/ci/xcode27_signed_field_candidate.sh")
test_path = Path("scripts/ci/tests/test_xcode27_signed_field_candidate_source.py")
producer = producer_path.read_text(encoding="utf-8")
tests = test_path.read_text(encoding="utf-8")

if 'PATH="/usr/bin:/bin:/usr/sbin:/sbin"' in producer or 'PYTHON3="/usr/bin/python3"' in producer:
    raise SystemExit("producer custody repair already present")

python_invocations = len(re.findall(r'(?m)(?<![A-Za-z0-9_"/])python3(?=\s)', producer))
if python_invocations < 8:
    raise SystemExit(f"unexpectedly few unqualified Python invocations: {python_invocations}")
producer = re.sub(r'(?m)(?<![A-Za-z0-9_"/])python3(?=\s)', '"$PYTHON3" -I', producer)

anchor = "#!/bin/bash\nset -euo pipefail\n"
if producer.count(anchor) != 1:
    raise SystemExit("unexpected shell prologue")
prologue = '''#!/bin/bash
set -euo pipefail

# Close executable selection before any external process can observe private field-input paths or
# influence repository/build evidence. Do not append caller PATH later.
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

# Python participates directly in private-input validation and evidence admission. Pin the system
# interpreter and use isolated mode for every producer Python process so caller PYTHON* startup/import
# state cannot gain authority before descriptor-bound source executes.
PYTHON3="/usr/bin/python3"
if [[ ! -x "$PYTHON3" ]]; then
  echo "Signed field-candidate production requires the sealed system Python 3 at $PYTHON3." >&2
  exit 2
fi
'''
producer = producer.replace(anchor, prologue, 1)
if re.search(r'(?m)^\s*python3(?:\s|$)', producer):
    raise SystemExit("unqualified Python invocation survived repair")

if "import re\n" not in tests:
    tests = tests.replace("import os\n", "import os\nimport re\n", 1)

exec_method = "    def test_executes_inspection_code_from_exact_git_blob_descriptors(self):\n"
if tests.count(exec_method) != 1:
    raise SystemExit("unexpected producer source-test anchor")
new_test = '''    def test_closes_process_path_and_isolates_python_before_private_work(self):
        path_match = re.search(
            r'^PATH="/usr/bin:/bin:/usr/sbin:/sbin"\\s*\\nexport PATH$',
            self.source,
            re.MULTILINE,
        )
        self.assertIsNotNone(path_match)
        self.assertGreater(path_match.start(), self.source.index("set -euo pipefail"))
        self.assertLess(path_match.start(), self.source.index('ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"'))
        self.assertLess(path_match.start(), self.source.index('if [[ "$(uname -s)" != "Darwin" ]]'))
        self.assertEqual(len(re.findall(r'(?m)^\\s*PATH=', self.source)), 1)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\\s*PATH=.*\\$\\{?PATH\\}?'))

        self.assertIn('PYTHON3="/usr/bin/python3"', self.source)
        self.assertIn('[[ ! -x "$PYTHON3" ]]', self.source)
        self.assertNotRegex(self.source, re.compile(r'(?m)^\\s*python3(?:\\s|$)'))
        self.assertNotIn('$(python3 ', self.source)
        invocations = re.findall(r'(?m)^\\s*"\\$PYTHON3"[^\\n]*', self.source)
        self.assertTrue(invocations)
        self.assertEqual(
            [line for line in invocations if not re.search(r'"\\$PYTHON3"\\s+-I(?:\\s|$)', line)],
            [],
        )
        self.assertIn('"$PYTHON3" -I /dev/fd/7', self.source)
        self.assertIn('"$PYTHON3" -I /dev/fd/9', self.source)
        self.assertIn('"$PYTHON3" -I --version', self.source)

'''
tests = tests.replace(exec_method, new_test + exec_method, 1)

tests = tests.replace("self.assertIn('python3 /dev/fd/7', self.source)", "self.assertIn('\"$PYTHON3\" -I /dev/fd/7', self.source)")
tests = tests.replace("self.assertIn('python3 /dev/fd/9', self.source)", "self.assertIn('\"$PYTHON3\" -I /dev/fd/9', self.source)")
tests = tests.replace("self.assertNotIn('python3 scripts/ci/es80_signed_field_artifact_private_runner.py', self.source)", "self.assertNotIn('python3 scripts/ci/es80_signed_field_artifact_private_runner.py', self.source)")
tests = tests.replace("self.source.index('python3 /dev/fd/7')", "self.source.index('\"$PYTHON3\" -I /dev/fd/7')")

producer_path.write_text(producer, encoding="utf-8")
test_path.write_text(tests, encoding="utf-8")
