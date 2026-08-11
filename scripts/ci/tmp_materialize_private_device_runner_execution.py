#!/usr/bin/env python3
from pathlib import Path

installer = Path("scripts/field/install_one_time_capture.command")
workflow = Path(".github/workflows/capture-signed-app-install-custody.yml")
source = installer.read_text(encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


old_preamble = '''PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
[[ -f "$PRIVATE_DEVICE_RUNNER" ]] || die "Private intended-device reader is missing from the accepted source."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
'''
new_preamble = '''PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE" 2>/dev/null)" || \\
    die "Private intended-device reader is missing from the exact accepted Git tree."
[[ "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Private intended-device reader Git blob identity is malformed."
PRIVATE_DEVICE_RUNNER_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" | /usr/bin/base64)" || \\
    die "Could not capture the private intended-device reader from the accepted Git object."
[[ -n "$PRIVATE_DEVICE_RUNNER_BASE64" ]] || die "Captured private intended-device reader is empty."
[[ "$(printf '%s' "$PRIVATE_DEVICE_RUNNER_BASE64" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --stdin)" == "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" ]] || \\
    die "Decoded private intended-device reader bytes do not match the accepted Git blob."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER_BASE64" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
'''
source = replace_once(source, old_preamble, new_preamble, "runner preamble")
source = replace_once(source, "import importlib.util\n", "import base64\n", "runner import")
old_loader = '''runner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)
if spec is None or spec.loader is None:
    raise RuntimeError("private intended-device reader could not be loaded")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
'''
new_loader = '''runner_source = base64.b64decode(sys.argv[1], validate=True)
runner_namespace = {
    "__name__": "nembra_private_device_reader",
    "__file__": "<accepted-private-device-runner>",
}
exec(
    compile(runner_source, "<accepted-private-device-runner>", "exec", dont_inherit=True),
    runner_namespace,
)
reader = runner_namespace.get("read_private_identifier")
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose read_private_identifier")
value = reader(Path(sys.argv[2]), Path(sys.argv[3]))
'''
source = replace_once(source, old_loader, new_loader, "runner loader")
source = replace_once(
    source,
    'unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 || true\nsay "Private intended-device admission validated against Final GO digest"',
    'unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 PRIVATE_DEVICE_RUNNER_BASE64 PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB PRIVATE_DEVICE_RUNNER_RELATIVE || true\nsay "Private intended-device admission validated against Final GO digest"',
    "runner cleanup",
)
installer.write_text(source, encoding="utf-8")

text = workflow.read_text(encoding="utf-8")
text = replace_once(
    text,
    '''      - scripts/ci/tests/test_capture_signed_app_install_custody.py
      - .github/workflows/capture-signed-app-install-custody.yml
''',
    '''      - scripts/ci/tests/test_capture_signed_app_install_custody.py
      - scripts/ci/tests/test_capture_private_device_runner_execution_subject.py
      - .github/workflows/capture-signed-app-install-custody.yml
''',
    "workflow path trigger",
)
text = replace_once(
    text,
    '''          /usr/bin/python3 -m py_compile scripts/ci/capture_signed_app_install_custody.py scripts/ci/tests/test_capture_signed_app_install_custody.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_signed_app_install_custody.py
''',
    '''          /usr/bin/python3 -m py_compile scripts/ci/capture_signed_app_install_custody.py scripts/ci/tests/test_capture_signed_app_install_custody.py scripts/ci/tests/test_capture_private_device_runner_execution_subject.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_signed_app_install_custody.py
          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_device_runner_execution_subject.py
''',
    "workflow regression execution",
)
workflow.write_text(text, encoding="utf-8")
