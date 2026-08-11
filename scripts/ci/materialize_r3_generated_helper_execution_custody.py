#!/usr/bin/env python3
from pathlib import Path

ISSUER = Path("scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py")
WORKFLOW = Path(".github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml")
TEST = "scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py"

text = ISSUER.read_text(encoding="utf-8")
if "import hashlib\n" not in text:
    anchor = "import contextlib\n"
    if text.count(anchor) != 1:
        raise SystemExit("hashlib import anchor drifted")
    text = text.replace(anchor, anchor + "import hashlib\n", 1)

start = text.index("def _current_generated_subject(root: Path) -> str:\n")
end = text.index("\ndef candidate_generated_authority(\n", start)
replacement = r'''def _accepted_candidate_blob_bytes(
    root: Path,
    source: str,
    relative: str,
    accepted_blob: str,
    *,
    base: Any,
) -> bytes:
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_blob):
        raise GeneratedSubjectGoError(f"generated build authority Git blob invalid: {relative}")
    source_blob = base.git(root, "rev-parse", f"{source}:{relative}").lower()
    if source_blob != accepted_blob:
        raise GeneratedSubjectGoError(f"generated build authority blob is not owned by exact source: {relative}")
    raw = base.git_bytes(root, "cat-file", "blob", accepted_blob)
    digest = hashlib.sha1() if len(accepted_blob) == 40 else hashlib.sha256()
    digest.update(f"blob {len(raw)}\0".encode("ascii"))
    digest.update(raw)
    if digest.hexdigest() != accepted_blob:
        raise GeneratedSubjectGoError(f"generated build authority Git blob bytes failed identity verification: {relative}")
    return raw


_HELPER_STDIN_LOADER = (
    "import sys\n"
    "filename=sys.argv[1]\n"
    "sys.argv=[filename,*sys.argv[2:]]\n"
    "source=sys.stdin.buffer.read()\n"
    "namespace={'__name__':'__main__','__file__':filename,'__package__':None}\n"
    "exec(compile(source,filename,'exec'),namespace)\n"
)


def _current_generated_subject(root: Path, *, helper_source: bytes | None = None) -> str:
    if not isinstance(helper_source, bytes) or not helper_source:
        raise GeneratedSubjectGoError("accepted generated-subject helper Git blob bytes are required")
    filename = f"git:{GENERATED_HELPER_PATH}"
    try:
        process = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-B",
                "-c",
                _HELPER_STDIN_LOADER,
                filename,
                "--lockfile",
                str(root / "Podfile.lock"),
                "--pods",
                str(root / "Pods"),
                "--workspace",
                str(root / "NembraCapture.xcworkspace"),
            ],
            cwd=root,
            env={"PATH": "/usr/bin:/bin"},
            input=helper_source,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise GeneratedSubjectGoError("accepted generated CocoaPods build-subject helper could not run") from error
    try:
        value = process.stdout.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise GeneratedSubjectGoError("generated CocoaPods build-subject helper output was not UTF-8") from error
    if process.returncode != 0 or not HEX64.fullmatch(value) or value != value.lower():
        raise GeneratedSubjectGoError("generated CocoaPods build subject could not be re-derived exactly")
    return value
'''
text = text[:start] + replacement + text[end:]

old_loop = '''    blobs: dict[str, str] = {}\n    texts: dict[str, str] = {}\n    for relative in GENERATED_AUTHORITY_PATHS:\n'''
new_loop = '''    blobs: dict[str, str] = {}\n    sources: dict[str, bytes] = {}\n    texts: dict[str, str] = {}\n    for relative in GENERATED_AUTHORITY_PATHS:\n'''
if text.count(old_loop) != 1:
    raise SystemExit("candidate source map anchor drifted")
text = text.replace(old_loop, new_loop, 1)

old_read = '''        blobs[relative] = blob\n        texts[relative] = path.read_text(encoding="utf-8")\n'''
new_read = '''        blobs[relative] = blob\n        raw = _accepted_candidate_blob_bytes(root, source, relative, blob, base=base)\n        sources[relative] = raw\n        try:\n            texts[relative] = raw.decode("utf-8")\n        except UnicodeDecodeError as error:\n            raise GeneratedSubjectGoError(f"generated build authority Git blob is not UTF-8 source: {relative}") from error\n'''
if text.count(old_read) != 1:
    raise SystemExit("candidate worktree text anchor drifted")
text = text.replace(old_read, new_read, 1)

old_derive = '''    current = derive_subject(root)\n    if current != accepted_digest:\n'''
new_derive = '''    if derive_subject is _current_generated_subject:\n        current = _current_generated_subject(\n            root,\n            helper_source=sources[GENERATED_HELPER_PATH],\n        )\n    else:\n        current = derive_subject(root)\n    if current != accepted_digest:\n'''
if text.count(old_derive) != 1:
    raise SystemExit("generated subject derivation anchor drifted")
text = text.replace(old_derive, new_derive, 1)
ISSUER.write_text(text, encoding="utf-8")

workflow = WORKFLOW.read_text(encoding="utf-8")
path_anchor = "      - scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py\n"
if workflow.count(path_anchor) != 2:
    raise SystemExit("workflow path anchors drifted")
workflow = workflow.replace(path_anchor, path_anchor + f"      - {TEST}\n")
compile_anchor = "            scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py\n"
if workflow.count(compile_anchor) != 1:
    raise SystemExit("workflow compile anchor drifted")
workflow = workflow.replace(
    compile_anchor,
    compile_anchor[:-1] + " \\\n" + f"            {TEST}\n",
    1,
)
run_anchor = "          python3 scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py\n"
if workflow.count(run_anchor) != 1:
    raise SystemExit("workflow run anchor drifted")
workflow = workflow.replace(
    run_anchor,
    run_anchor + f"          python3 {TEST}\n",
    1,
)
WORKFLOW.write_text(workflow, encoding="utf-8")
