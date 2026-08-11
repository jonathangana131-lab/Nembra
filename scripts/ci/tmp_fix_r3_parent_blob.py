#!/usr/bin/env python3
from pathlib import Path
import textwrap

R3 = Path("scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py")
source = R3.read_text(encoding="utf-8")
constant = 'PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_final_go.py"\n'
if source.count(constant) != 1:
    raise SystemExit("R3 parent module constant seam drifted")
source = source.replace(
    constant,
    constant + 'PARENT_MODULE_BLOB_OID = "b0664c734004c2265b05d23ec58756806ff62f2c"\n',
    1,
)
start = source.index("def _accepted_parent_module_bytes(")
end = source.index("\n\ndef _load_base_module()", start)
replacement = textwrap.dedent('''\
def _accepted_parent_module_bytes(root: Path, blob_oid: str) -> bytes:
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", blob_oid):
        raise GeneratedSubjectGoError("accepted parent module Git blob identity is invalid")
    try:
        payload = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", blob_oid],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_parent_git_environment(),
        ).stdout
        verified = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "hash-object", "--stdin"],
            input=payload,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_parent_git_environment(),
        ).stdout.decode("ascii").strip().lower()
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        raise GeneratedSubjectGoError("accepted parent Final-GO Git custody failed") from error
    if (
        not payload
        or len(payload) > 4 * 1024 * 1024
        or verified != blob_oid
        or _git_blob_oid(payload, blob_oid) != blob_oid
    ):
        raise GeneratedSubjectGoError("accepted parent Final-GO execution bytes failed Git identity verification")
    return payload
''')
source = source[:start] + replacement + source[end:]
old_load = '    payload = _accepted_parent_module_bytes(root, PARENT_SOURCE_COMMIT)\n    filename = f"git:{PARENT_SOURCE_COMMIT}:{PARENT_MODULE_PATH}"\n'
new_load = '    payload = _accepted_parent_module_bytes(root, PARENT_MODULE_BLOB_OID)\n    filename = f"git-blob:{PARENT_MODULE_BLOB_OID}:{PARENT_MODULE_PATH}"\n'
if source.count(old_load) != 1:
    raise SystemExit("R3 load-base seam drifted")
source = source.replace(old_load, new_load, 1)
R3.write_text(source, encoding="utf-8")

unit = Path("scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py")
tests = unit.read_text(encoding="utf-8")
old_parent = 'PARENT = "2" * 40\n'
if tests.count(old_parent) != 1:
    raise SystemExit("R3 synthetic parent fixture seam drifted")
tests = tests.replace(old_parent, "PARENT = MODULE.PARENT_SOURCE_COMMIT\n", 1)
unit.write_text(tests, encoding="utf-8")

custody = Path("scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py")
regression = custody.read_text(encoding="utf-8")
old_override = "                module.PARENT_SOURCE_COMMIT = accepted_source\n"
if regression.count(old_override) != 1:
    raise SystemExit("R3 custody fixture override seam drifted")
regression = regression.replace(old_override, "                module.PARENT_MODULE_BLOB_OID = accepted_blob\n", 1)
custody.write_text(regression, encoding="utf-8")
