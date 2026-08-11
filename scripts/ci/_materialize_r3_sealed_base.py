#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path('scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py')
TESTS = Path('scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py')
WORKFLOW = Path('.github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml')


def one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one anchor, found {count}')
    return text.replace(old, new, 1)


source = SOURCE.read_text()
source = one(
    source,
    'import json\nimport re\nimport subprocess\nimport sys\nimport types\n',
    'import json\nimport os\nimport re\nimport subprocess\nimport sys\nimport types\nimport urllib.request\n',
    'imports',
)
source = one(
    source,
    'PARENT_BRANCH = "control/v14-auth-stationary-final-go-sol"\n',
    'PARENT_BRANCH = "control/v14-auth-stationary-final-go-sol"\n'
    'BASE_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_final_go.py"\n'
    'PARENT_WORKFLOW_NAME = "Capture Authenticated Stationary Final GO"\n'
    'PARENT_WORKFLOW_PATH = ".github/workflows/capture-authenticated-stationary-final-go.yml"\n',
    'constants',
)
old_loader = '''def _load_base_module():
    path = Path(__file__).with_name("es80_authenticated_stationary_final_go.py")
    spec = importlib.util.spec_from_file_location("nembra_authenticated_stationary_final_go", path)
    if spec is None or spec.loader is None:
        raise GeneratedSubjectGoError("authenticated-stationary Final-GO parent could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
'''
new_loader = '''def _duplicate_safe_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise GeneratedSubjectGoError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _control_api(path: str):
    url = f"https://api.github.com/repos/{REPO}{path}"
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "Nembra-V14-Generated-Subject-Control",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.getenv("GITHUB_TOKEN", "").strip()
    if token:
        headers["Authorization"] = "Bearer " + token
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as response:
            if response.geturl().split("?", 1)[0] != url:
                raise GeneratedSubjectGoError("GitHub API redirected")
            raw = response.read()
    except OSError as error:
        raise GeneratedSubjectGoError("GitHub API unavailable") from error
    try:
        value = json.loads(raw, object_pairs_hook=_duplicate_safe_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GeneratedSubjectGoError("GitHub API returned invalid JSON") from error
    if not isinstance(value, dict):
        raise GeneratedSubjectGoError("GitHub API response must be an object")
    return raw, value


def _control_git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_OPTIONAL_LOCKS": "0",
        "LC_ALL": "C",
    }


class _ControlPrimitives:
    AUTH_WORKFLOW_NAME = PARENT_WORKFLOW_NAME
    AUTH_WORKFLOW_PATH = PARENT_WORKFLOW_PATH

    @staticmethod
    def pos(value, label):
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise GeneratedSubjectGoError(f"{label} is not a positive integer")
        return value

    @staticmethod
    def canon(value, label):
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", value):
            raise GeneratedSubjectGoError(f"{label} is not canonical 40-hex")
        return value.lower()

    @staticmethod
    def git(repo: Path, *args: str) -> str:
        try:
            return subprocess.run(
                ["/usr/bin/git", "-C", str(repo), *args],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=_control_git_environment(),
            ).stdout.strip()
        except (OSError, subprocess.CalledProcessError) as error:
            raise GeneratedSubjectGoError("pre-execution control Git custody failed") from error

    @staticmethod
    def git_bytes(repo: Path, *args: str) -> bytes:
        try:
            return subprocess.run(
                ["/usr/bin/git", "-C", str(repo), *args],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=_control_git_environment(),
            ).stdout
        except (OSError, subprocess.CalledProcessError) as error:
            raise GeneratedSubjectGoError("pre-execution control Git byte custody failed") from error


def _load_base_module(authority_repo: Path, control: dict[str, Any], primitives: Any = _ControlPrimitives):
    root = authority_repo.expanduser().resolve(strict=True)
    parent_source = primitives.canon(control.get("parentSourceCommitSHA"), "accepted parent source")
    blobs = control.get("gitBlobs")
    if not isinstance(blobs, dict):
        raise GeneratedSubjectGoError("accepted generated control record lacks Git blobs")
    accepted_blob = blobs.get(BASE_MODULE_PATH)
    if not isinstance(accepted_blob, str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_blob):
        raise GeneratedSubjectGoError("accepted parent module Git blob identity is invalid")
    parent_blob = primitives.git(root, "rev-parse", f"{parent_source}:{BASE_MODULE_PATH}").lower()
    if parent_blob != accepted_blob:
        raise GeneratedSubjectGoError("accepted child control does not pin the exact parent module blob")
    payload = primitives.git_bytes(root, "show", f"{parent_source}:{BASE_MODULE_PATH}")
    if not isinstance(payload, bytes) or not payload or len(payload) > 4 * 1024 * 1024:
        raise GeneratedSubjectGoError("accepted parent module Git blob has invalid bounded bytes")
    if _git_blob_oid(payload, accepted_blob) != accepted_blob:
        raise GeneratedSubjectGoError("authenticated-stationary parent execution bytes do not match accepted Git blob")
    module = types.ModuleType("nembra_authenticated_stationary_final_go")
    module.__file__ = f"git:{parent_source}:{BASE_MODULE_PATH}"
    module.__package__ = ""
    try:
        code = compile(payload, module.__file__, "exec", dont_inherit=True)
        exec(code, module.__dict__)
    except Exception as error:
        raise GeneratedSubjectGoError("accepted authenticated-stationary parent Git blob could not be evaluated") from error
    return module
'''
source = one(source, old_loader, new_loader, 'base loader')
source = one(
    source,
    '    base = base_module or _load_base_module()\n    get = get or base.api\n    source = base.canon(source, "source")\n',
    '''    pre_control = None
    if base_module is None:
        control_get = get or _control_api
        pre_control = generated_control_plane(
            authority_repo,
            authority_pr,
            authority_run,
            parent_pr=parent_authority_pr,
            parent_run_id=parent_authority_run,
            get=control_get,
            base=_ControlPrimitives,
        )
        base = _load_base_module(authority_repo, pre_control, _ControlPrimitives)
        get = control_get
    else:
        base = base_module
        get = get or base.api
    source = base.canon(source, "source")
''',
    'build pre-control',
)
old_adapter = '''    def control_adapter(repo: Path, control_pr: int, control_run: int, callback_get: Any = get):
        return generated_control_plane(
            repo,
            control_pr,
            control_run,
            parent_pr=parent_authority_pr,
            parent_run_id=parent_authority_run,
            get=callback_get,
            base=base,
        )
'''
new_adapter = '''    def control_adapter(repo: Path, control_pr: int, control_run: int, callback_get: Any = get):
        current = generated_control_plane(
            repo,
            control_pr,
            control_run,
            parent_pr=parent_authority_pr,
            parent_run_id=parent_authority_run,
            get=callback_get,
            base=base,
        )
        if pre_control is not None and current != pre_control:
            raise GeneratedSubjectGoError("generated control authority changed after sealed parent load")
        return current
'''
source = one(source, old_adapter, new_adapter, 'control adapter')
source = one(
    source,
    'def _parse_workflows(values: list[str], *, base: Any) -> dict[str, int]:\n',
    'def _parse_workflows(values: list[str]) -> dict[str, int]:\n',
    'workflow parser signature',
)
source = one(
    source,
    '        runs[name] = base.pos(int(identifier), name)\n',
    '        runs[name] = _ControlPrimitives.pos(int(identifier), name)\n',
    'workflow parser value',
)
source = one(source, '    base = _load_base_module()\n    try:\n', '    try:\n', 'main eager loader')
source = one(
    source,
    '            runs=_parse_workflows(arguments.workflow, base=base),\n',
    '            runs=_parse_workflows(arguments.workflow),\n',
    'main workflow parser call',
)
source = one(
    source,
    '        raw = (json.dumps(record, indent=2, sort_keys=True) + "\\n").encode()\n        publication = base.publication(\n',
    '        raw = (json.dumps(record, indent=2, sort_keys=True) + "\\n").encode()\n        base = _load_base_module(arguments.authority_repo, record["finalGOControlPlane"], _ControlPrimitives)\n        publication = base.publication(\n',
    'main sealed publication loader',
)
source = one(
    source,
    '    except (GeneratedSubjectGoError, base.GoError, OSError, ValueError) as error:\n',
    '    except (GeneratedSubjectGoError, OSError, ValueError, RuntimeError) as error:\n',
    'main error tuple',
)
SOURCE.write_text(source)

# Unit tests that only inspect parent API shape import the parent directly inside test code;
# physical authority tests exercise the production sealed loader separately.
tests = TESTS.read_text()
helper = '''\n\ndef _unit_parent_module():\n    parent = SCRIPT.with_name("es80_authenticated_stationary_final_go.py")\n    spec = importlib.util.spec_from_file_location("unit_authenticated_stationary_final_go", parent)\n    if spec is None or spec.loader is None:\n        raise RuntimeError("could not load unit parent module")\n    module = importlib.util.module_from_spec(spec)\n    spec.loader.exec_module(module)\n    return module\n'''
tests = one(tests, 'SOURCE = "1" * 40\n', helper + '\nSOURCE = "1" * 40\n', 'test unit loader helper')
tests = tests.replace('base = MODULE._load_base_module()', 'base = _unit_parent_module()')
TESTS.write_text(tests)

workflow = WORKFLOW.read_text()
workflow = one(
    workflow,
    '      - scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n      - .github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml\n',
    '      - scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n      - scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py\n      - .github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml\n',
    'workflow pull/push first path anchor',
)
# Same anchor appears a second time for pull_request after first replacement.
workflow = one(
    workflow,
    '      - scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n      - .github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml\n',
    '      - scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n      - scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py\n      - .github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml\n',
    'workflow pull/push second path anchor',
)
workflow = one(
    workflow,
    '            scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n',
    '            scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py \\\n            scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py\n',
    'workflow compile list',
)
workflow = one(
    workflow,
    '      - name: Prove generated helper executes from accepted Git bytes\n        shell: bash\n        run: |\n          set -euo pipefail\n          python3 scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n',
    '      - name: Prove generated helper executes from accepted Git bytes\n        shell: bash\n        run: |\n          set -euo pipefail\n          python3 scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n\n      - name: Prove authenticated-stationary parent executes from accepted Git bytes\n        shell: bash\n        run: |\n          set -euo pipefail\n          python3 scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py\n',
    'workflow execution test step',
)
WORKFLOW.write_text(workflow)
