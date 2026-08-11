#!/usr/bin/env python3
from pathlib import Path

module_path = Path("scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py")
source = module_path.read_text(encoding="utf-8")
old_function = '''def _current_generated_subject(root: Path) -> str:
    helper = root / GENERATED_HELPER_PATH
    try:
        process = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-B",
                str(helper),
                "--lockfile",
                str(root / "Podfile.lock"),
                "--pods",
                str(root / "Pods"),
                "--workspace",
                str(root / "NembraCapture.xcworkspace"),
            ],
            cwd=root,
            env={"PATH": "/usr/bin:/bin"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise GeneratedSubjectGoError("generated CocoaPods build-subject helper could not run") from error
    value = process.stdout.strip()
    if process.returncode != 0 or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError("generated CocoaPods build subject could not be re-derived exactly")
    return value
'''
new_function = '''def _accepted_helper_blob_bytes(root: Path, source: str, accepted_blob: str) -> bytes:
    source = source.lower()
    accepted_blob = accepted_blob.lower()
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise GeneratedSubjectGoError("generated helper source identity is not exact SHA-1 commit authority")
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_blob):
        raise GeneratedSubjectGoError("generated helper accepted Git blob identity is invalid")
    environment = {"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"}
    try:
        owned = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"{source}:{GENERATED_HELPER_PATH}"],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout.decode("ascii").strip().lower()
        if owned != accepted_blob:
            raise GeneratedSubjectGoError("generated helper blob is not owned by exact accepted source path")
        raw = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", accepted_blob],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout
        verified = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "hash-object", "--stdin"],
            env=environment,
            input=raw,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout.decode("ascii").strip().lower()
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        raise GeneratedSubjectGoError("generated helper accepted Git object could not be read exactly") from error
    if verified != accepted_blob:
        raise GeneratedSubjectGoError("generated helper Git-object bytes failed exact identity verification")
    return raw


def _current_generated_subject(root: Path, *, source: str, accepted_blob: str) -> str:
    helper_bytes = _accepted_helper_blob_bytes(root, source, accepted_blob)
    try:
        process = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-B",
                "-",
                "--lockfile",
                str(root / "Podfile.lock"),
                "--pods",
                str(root / "Pods"),
                "--workspace",
                str(root / "NembraCapture.xcworkspace"),
            ],
            cwd=root,
            env={"PATH": "/usr/bin:/bin"},
            input=helper_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise GeneratedSubjectGoError("generated CocoaPods build-subject accepted helper bytes could not run") from error
    try:
        value = process.stdout.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise GeneratedSubjectGoError("generated CocoaPods build-subject helper output is not UTF-8") from error
    if process.returncode != 0 or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError("generated CocoaPods build subject could not be re-derived exactly")
    return value
'''
if source.count(old_function) != 1:
    raise SystemExit("current R3 helper execution function did not match expected exact source")
source = source.replace(old_function, new_function, 1)
old_call = '''    current = derive_subject(root)
    if current != accepted_digest:
'''
new_call = '''    if derive_subject is _current_generated_subject:
        current = derive_subject(
            root,
            source=source,
            accepted_blob=blobs[GENERATED_HELPER_PATH],
        )
    else:
        current = derive_subject(root)
    if current != accepted_digest:
'''
if source.count(old_call) != 1:
    raise SystemExit("current R3 generated subject call did not match expected exact source")
source = source.replace(old_call, new_call, 1)
module_path.write_text(source, encoding="utf-8")

workflow_path = Path(".github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml")
workflow = workflow_path.read_text(encoding="utf-8")
path_marker = "      - scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py\n"
if workflow.count(path_marker) != 2:
    raise SystemExit("current R3 workflow path list shape changed")
workflow = workflow.replace(
    path_marker,
    path_marker + "      - scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n",
)
compile_marker = '''            scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py \\
            scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py
'''
compile_replacement = '''            scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py \\
            scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py \\
            scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py
'''
if workflow.count(compile_marker) != 1:
    raise SystemExit("current R3 compile block changed")
workflow = workflow.replace(compile_marker, compile_replacement, 1)
run_marker = '''      - name: Prove generated custody workflows are mandatory release authority
        shell: bash
        run: |
          set -euo pipefail
          python3 scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py
'''
run_replacement = run_marker + '''
      - name: Reject generated-helper swap restore at execution boundary
        shell: bash
        run: |
          set -euo pipefail
          python3 scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py
'''
if workflow.count(run_marker) != 1:
    raise SystemExit("current R3 workflow gate run block changed")
workflow = workflow.replace(run_marker, run_replacement, 1)
workflow_path.write_text(workflow, encoding="utf-8")
