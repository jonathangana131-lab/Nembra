from pathlib import Path

producer = Path("scripts/ci/xcode27_signed_field_candidate.sh")
text = producer.read_text(encoding="utf-8")

if 'PYTHON3="/usr/bin/python3"' in text:
    raise SystemExit("Python custody block already exists; refuse duplicate transform")

# Replace only command-token spellings that existed before introducing the pinned variable.
text = text.replace("python3 ", '"$PYTHON3" -I ')

anchor = "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID\n"
block = '''unset NEMBRA_INTENDED_FIELD_DEVICE_UDID

# Python participates directly in private-input validation and evidence admission. Never discover it
# through caller PATH, and always use isolated mode so PYTHON* startup/import state cannot gain
# authority before descriptor-bound source executes.
PYTHON3="/usr/bin/python3"
if [[ ! -x "$PYTHON3" ]]; then
  echo "Signed field-candidate production requires the sealed system Python 3 at $PYTHON3." >&2
  exit 2
fi
'''
if text.count(anchor) != 1:
    raise SystemExit(f"expected one legacy raw-UDID retirement anchor, found {text.count(anchor)}")
text = text.replace(anchor, block, 1)

env_anchor = '  echo "physical_authorization=not-granted"\n  xcodebuild -version\n'
env_replacement = '  echo "physical_authorization=not-granted"\n  "$PYTHON3" -I --version\n  xcodebuild -version\n'
if text.count(env_anchor) != 1:
    raise SystemExit(f"expected one field environment anchor, found {text.count(env_anchor)}")
text = text.replace(env_anchor, env_replacement, 1)

if 'python3 /dev/fd/7' in text or 'python3 /dev/fd/9' in text:
    raise SystemExit("descriptor-bound private runner still uses ambient Python")
if '"$PYTHON3" -I /dev/fd/7' not in text or '"$PYTHON3" -I /dev/fd/9' not in text:
    raise SystemExit("descriptor-bound runner did not receive pinned isolated Python")
producer.write_text(text, encoding="utf-8")

workflow = Path(".github/workflows/xcode27-pr-command.yml")
w = workflow.read_text(encoding="utf-8")
anchor = "          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_source.py\n"
addition = anchor + "          python3 -m py_compile scripts/ci/tests/test_xcode27_signed_field_candidate_python_custody_source.py\n          python3 scripts/ci/tests/test_xcode27_signed_field_candidate_python_custody_source.py\n"
if "test_xcode27_signed_field_candidate_python_custody_source.py" not in w:
    if w.count(anchor) != 1:
        raise SystemExit(f"expected one signed-field source regression anchor, found {w.count(anchor)}")
    w = w.replace(anchor, addition, 1)
workflow.write_text(w, encoding="utf-8")
