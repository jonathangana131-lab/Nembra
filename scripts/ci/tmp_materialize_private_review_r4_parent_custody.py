#!/usr/bin/env python3
from pathlib import Path
import textwrap

path = Path("scripts/ci/es80_authenticated_stationary_private_review_final_go.py")
source = path.read_text(encoding="utf-8")

old_imports = "import contextlib\nimport importlib.util\nimport json\nimport re\n"
new_imports = "import contextlib\nimport json\nimport re\nimport subprocess\nimport types\n"
if source.count(old_imports) != 1:
    raise SystemExit("private-review import seam drifted")
source = source.replace(old_imports, new_imports, 1)

parent_line = 'PARENT_BRANCH = "control/v14-auth-stationary-generated-subject-r3-sol"\n'
if source.count(parent_line) != 1:
    raise SystemExit("private-review parent constant seam drifted")
source = source.replace(
    parent_line,
    parent_line
    + 'GENERATED_PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"\n'
    + 'GENERATED_PARENT_MODULE_GIT_BLOB = "13720f812498d86f55c0f1ca4e98b873f0793cb9"\n',
    1,
)

old_loader = textwrap.dedent('''\
def _load_generated_module():
    path = Path(__file__).with_name("es80_authenticated_stationary_generated_subject_final_go.py")
    spec = importlib.util.spec_from_file_location("nembra_generated_subject_final_go_parent", path)
    if spec is None or spec.loader is None:
        raise PrivateReviewGoError("generated-subject Final-GO parent could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
''')
new_loader = textwrap.dedent('''\
def _load_generated_module():
    root = Path(__file__).resolve().parents[2]
    environment = {"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"}
    try:
        source = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.strip().lower()
        accepted_blob = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"{source}:{GENERATED_PARENT_MODULE_PATH}"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout.strip().lower()
        payload = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", accepted_blob],
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
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        raise PrivateReviewGoError("generated-subject Final-GO parent Git custody failed") from error
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", source):
        raise PrivateReviewGoError("private-review control source is invalid")
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_blob):
        raise PrivateReviewGoError("generated-subject Final-GO parent Git blob is invalid")
    if accepted_blob != GENERATED_PARENT_MODULE_GIT_BLOB:
        raise PrivateReviewGoError(
            "generated-subject Final-GO parent Git blob does not match exact accepted R3 authority"
        )
    if not payload or verified != accepted_blob:
        raise PrivateReviewGoError("generated-subject Final-GO parent Git bytes failed identity verification")
    filename = f"git:{source}:{GENERATED_PARENT_MODULE_PATH}"
    module = types.ModuleType("nembra_generated_subject_final_go_parent")
    module.__file__ = filename
    module.__nembra_accepted_control_source__ = source
    module.__nembra_accepted_control_blob__ = accepted_blob
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise PrivateReviewGoError("accepted generated-subject Final-GO parent could not execute") from error
    return module
''')
if source.count(old_loader) != 1:
    raise SystemExit("mutable generated-parent loader seam drifted")
source = source.replace(old_loader, new_loader, 1)
path.write_text(source, encoding="utf-8")

Path("scripts/ci/tmp_materialize_private_review_r4_parent_custody.py").unlink()
