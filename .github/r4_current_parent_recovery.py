#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CURRENT_R3_HEAD = "b4a2172cd799d363cb503a1ecb3d15bc7382e36f"
GENERATED_PARENT_BLOB = "13720f812498d86f55c0f1ca4e98b873f0793cb9"
R4_SOURCE_REF = "refs/remotes/origin/r4-source"
R4_RED_REF = "refs/remotes/origin/r4-red"


def run(*args: str) -> None:
    subprocess.run(list(args), cwd=ROOT, check=True)


def output(*args: str) -> str:
    return subprocess.check_output(list(args), cwd=ROOT, text=True).strip()


def show(ref: str, path: str) -> str:
    return subprocess.check_output(["/usr/bin/git", "show", f"{ref}:{path}"], cwd=ROOT, text=True)


run("/usr/bin/git", "fetch", "--no-tags", "origin", "control/v14-auth-stationary-generated-subject-r3-sol:refs/remotes/origin/current-r3")
if output("/usr/bin/git", "rev-parse", "refs/remotes/origin/current-r3") != CURRENT_R3_HEAD:
    raise SystemExit("current R3 parent moved; recovery must re-anchor before publication")
run("/usr/bin/git", "fetch", "--no-tags", "origin", "control/v14-auth-stationary-private-review-r4-sol:refs/remotes/origin/r4-source")
run("/usr/bin/git", "fetch", "--no-tags", "origin", "adversarial/v14-private-review-parent-module-exec-sol:refs/remotes/origin/r4-red")

source_path = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
primary_test_path = ROOT / "scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py"
red_test_path = ROOT / "scripts/ci/tests/test_es80_private_review_parent_module_execution_custody.py"
workflow_path = ROOT / ".github/workflows/capture-authenticated-stationary-private-review-final-go.yml"

source_path.write_text(show(R4_SOURCE_REF, "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"), encoding="utf-8")
primary_test_path.write_text(show(R4_SOURCE_REF, "scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py"), encoding="utf-8")
workflow_path.write_text(show(R4_SOURCE_REF, ".github/workflows/capture-authenticated-stationary-private-review-final-go.yml"), encoding="utf-8")
red_test_path.write_text(show(R4_RED_REF, "scripts/ci/tests/test_es80_private_review_parent_module_execution_custody.py"), encoding="utf-8")

text = source_path.read_text(encoding="utf-8")
if text.count("import importlib.util\n") != 1:
    raise SystemExit("R4 mutable-loader import anchor drifted")
text = text.replace("import importlib.util\n", "import subprocess\nimport types\n", 1)
start = text.index("def _load_generated_module():\n")
end = text.index("\n\ngenerated = _load_generated_module()", start)
replacement = f'''GENERATED_PARENT_PATH = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
GENERATED_PARENT_GIT_BLOB = "{GENERATED_PARENT_BLOB}"


def _load_generated_module():
    root = Path(__file__).resolve().parents[2]
    environment = {{"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"}}
    try:
        source = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.strip().lower()
        blob = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"{{source}}:{{GENERATED_PARENT_PATH}}"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.strip().lower()
        if blob != GENERATED_PARENT_GIT_BLOB:
            raise PrivateReviewGoError(
                "generated-subject Final-GO parent does not match exact accepted parent authority"
            )
        payload = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", blob],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout
        verified = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "hash-object", "--stdin"],
            input=payload,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.decode("ascii").strip().lower()
    except PrivateReviewGoError:
        raise
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        raise PrivateReviewGoError("generated-subject Final-GO parent Git custody failed") from error
    if not re.fullmatch(r"[0-9a-f]{{40}}|[0-9a-f]{{64}}", source):
        raise PrivateReviewGoError("private-review control source is invalid")
    if (
        not re.fullmatch(r"[0-9a-f]{{40}}|[0-9a-f]{{64}}", blob)
        or verified != blob
        or not payload
    ):
        raise PrivateReviewGoError(
            "generated-subject Final-GO parent Git bytes failed identity verification"
        )
    filename = f"git:{{source}}:{{GENERATED_PARENT_PATH}}"
    module = types.ModuleType("nembra_generated_subject_final_go_parent")
    module.__file__ = filename
    module.__nembra_accepted_control_source__ = source
    module.__nembra_accepted_control_blob__ = blob
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise PrivateReviewGoError(
            "accepted generated-subject Final-GO parent could not execute"
        ) from error
    return module'''
text = text[:start] + replacement + text[end:]
source_path.write_text(text, encoding="utf-8")

text = red_test_path.read_text(encoding="utf-8")
if text.count("import importlib.util\n") != 1:
    raise SystemExit("R4 red-team import anchor drifted")
text = text.replace("import importlib.util\n", "import importlib.util\nimport re\n", 1)
anchor = '            subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)\n'
if text.count(anchor) != 1:
    raise SystemExit("R4 red-team fixture anchor drifted")
insertion = (
    '            accepted_fixture_blob = subprocess.check_output(\n'
    '                ["/usr/bin/git", "-C", str(root), "hash-object", "--", PARENT_RELATIVE],\n'
    '                text=True,\n'
    '            ).strip()\n'
    '            child_text = child.read_text(encoding="utf-8")\n'
    '            child_text, replacements = re.subn(\n'
    '                r\'GENERATED_PARENT_GIT_BLOB = "[0-9a-f]{{40,64}}"\',\n'
    '                f\'GENERATED_PARENT_GIT_BLOB = "{accepted_fixture_blob}"\',\n'
    '                child_text,\n'
    '                count=1,\n'
    '            )\n'
    '            self.assertEqual(\n'
    '                replacements, 1,\n'
    '                "fixture could not bind child to its committed safe parent blob",\n'
    '            )\n'
    '            child.write_text(child_text, encoding="utf-8")\n'
)
text = text.replace(anchor, insertion + anchor, 1)
red_test_path.write_text(text, encoding="utf-8")

text = workflow_path.read_text(encoding="utf-8")
text = text.replace(
    "control/v14-auth-stationary-private-review-r4-sol",
    "repair/v14-r4-private-review-current-parent-exec-sol-20260811",
)
trigger = "      - scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py\n"
if text.count(trigger) != 2:
    raise SystemExit(f"R4 workflow trigger anchor drifted: {text.count(trigger)}")
text = text.replace(
    trigger,
    trigger + "      - scripts/ci/tests/test_es80_private_review_parent_module_execution_custody.py\n",
)
compile_line = "            scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py\n"
if text.count(compile_line) != 1:
    raise SystemExit("R4 workflow compile anchor drifted")
text = text.replace(
    compile_line,
    "            scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py \\\n"
    "            scripts/ci/tests/test_es80_private_review_parent_module_execution_custody.py\n",
    1,
)
run_line = "          python3 scripts/ci/tests/test_es80_authenticated_stationary_private_review_final_go.py\n"
if text.count(run_line) != 1:
    raise SystemExit("R4 workflow run anchor drifted")
text = text.replace(
    run_line,
    run_line + "          python3 scripts/ci/tests/test_es80_private_review_parent_module_execution_custody.py\n",
    1,
)
text = text.replace("uses: actions/checkout@v4", "uses: actions/checkout@v6")
workflow_path.write_text(text, encoding="utf-8")
