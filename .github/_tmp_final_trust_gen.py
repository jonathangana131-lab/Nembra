from __future__ import annotations

import base64
import json
import os
import subprocess
from pathlib import Path
from urllib.request import Request, urlopen

root = Path(".")
workflow_path = root / ".github/workflows/capture-xcode27-trusted-command.yml"
workflow = workflow_path.read_text()

loop_marker = '          for relative, expected_blob in expected.items():\n'
if workflow.count(loop_marker) != 1:
    raise SystemExit(f"expected one build-graph hash loop, found {workflow.count(loop_marker)}")

selector_guard_marker = "trusted build graph forbids source-controlled Xcode user data"
if selector_guard_marker not in workflow:
    selector_guard = '''          project_root = root / "Nembra.xcodeproj"
          source_controlled_user_data = sorted(
              str(path.relative_to(root))
              for path in project_root.rglob("*")
              if path.name.casefold() == "xcuserdata"
          )
          if source_controlled_user_data:
              raise SystemExit(
                  "trusted build graph forbids source-controlled Xcode user data: "
                  + ", ".join(source_controlled_user_data)
              )

          nembra_schemes = sorted(
              str(path.relative_to(root))
              for path in project_root.rglob("*")
              if path.is_file() and path.name.casefold() == "nembra.xcscheme"
          )
          expected_nembra_schemes = ["Nembra.xcodeproj/xcshareddata/xcschemes/Nembra.xcscheme"]
          if nembra_schemes != expected_nembra_schemes:
              raise SystemExit(
                  "trusted build graph requires exactly the reviewed shared Nembra scheme: "
                  + repr(nembra_schemes)
              )

          for package_relative in (
              "Packages/NembraCore",
              "Packages/NembraBluetoothCapture",
          ):
              package_root = root / package_relative
              alternate_manifests = sorted(
                  str(path.relative_to(root))
                  for path in package_root.glob("Package@swift-*.swift")
              )
              if alternate_manifests:
                  raise SystemExit(
                      "trusted build graph forbids version-specific SwiftPM manifests: "
                      + ", ".join(alternate_manifests)
                  )

'''
    workflow = workflow.replace(loop_marker, selector_guard + loop_marker, 1)

run_identity_segment = '''              PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
              HOME=/tmp \\
              LC_ALL=C \\
              GIT_DIR="$GITHUB_WORKSPACE/.git" \\
'''
run_identity_replacement = '''              PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
              HOME=/tmp \\
              LC_ALL=C \\
              GITHUB_RUN_ID="${{ github.run_id }}" \\
              GITHUB_RUN_ATTEMPT="${{ github.run_attempt }}" \\
              GIT_DIR="$GITHUB_WORKSPACE/.git" \\
'''
if workflow.count(run_identity_segment) != 1:
    raise SystemExit(f"expected one closed producer execution env, found {workflow.count(run_identity_segment)}")
workflow = workflow.replace(run_identity_segment, run_identity_replacement, 1)
workflow_path.write_text(workflow)

build_graph_test_path = root / "scripts/ci/tests/test_capture_trusted_xcode_build_graph_custody.py"
build_test = build_graph_test_path.read_text()
candidate_test_marker = '    def test_candidate_prevalidation_does_not_share_authority_runner(self) -> None:\n'
if build_test.count(candidate_test_marker) != 1:
    raise SystemExit("expected one candidate prevalidation test marker")
if "test_authority_rejects_unpinned_user_scheme_selectors" not in build_test:
    methods = '''    def _custody_step(self) -> str:
        authority = self.workflow.index("  capture-simulator-qa:\\n")
        authority_block = self.workflow[authority:]
        custody = authority_block.index("- name: Verify trusted build graph custody")
        build = authority_block.index("- name: Build, test, and capture Simulator states")
        self.assertLess(custody, build)
        return authority_block[custody:build]

    def test_authority_rejects_unpinned_user_scheme_selectors(self) -> None:
        step = self._custody_step()
        self.assertIn('path.name.casefold() == "xcuserdata"', step)
        self.assertIn('path.name.casefold() == "nembra.xcscheme"', step)
        self.assertIn(
            'expected_nembra_schemes = ["Nembra.xcodeproj/xcshareddata/xcschemes/Nembra.xcscheme"]',
            step,
        )
        self.assertIn("trusted build graph forbids source-controlled Xcode user data", step)

    def test_authority_rejects_unpinned_version_specific_package_manifests(self) -> None:
        step = self._custody_step()
        self.assertIn('package_root.glob("Package@swift-*.swift")', step)
        self.assertIn('"Packages/NembraCore"', step)
        self.assertIn('"Packages/NembraBluetoothCapture"', step)
        self.assertIn("trusted build graph forbids version-specific SwiftPM manifests", step)

'''
    build_test = build_test.replace(candidate_test_marker, methods + candidate_test_marker, 1)
    build_graph_test_path.write_text(build_test)

bash_test_path = root / "scripts/ci/tests/test_capture_trusted_xcode_bash_environment_custody.py"
bash_test = bash_test_path.read_text()
bash_test = bash_test.replace(
    "pinned producer or its retained-evidence verifier.\n",
    "pinned producer or its retained-evidence verifier. The clean inner environment must still receive\n"
    "the trusted GitHub run identity that the frozen producer records as retained provenance.\n",
    1,
)
constants_marker = 'WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"\n'
constants = (
    'WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"\n'
    'TRUSTED_PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"\n'
    'TRUSTED_PRODUCER_BLOB_SHA = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"\n'
)
if "TRUSTED_PRODUCER_PATH" not in bash_test:
    if bash_test.count(constants_marker) != 1:
        raise SystemExit("expected workflow constant marker")
    bash_test = bash_test.replace(constants_marker, constants, 1)

old_closed = r'''        closed_bash = re.compile(
            r"\|\s*/usr/bin/env\s+-i\b(?:(?!^      - name: ).){0,1200}?/bin/bash\b",
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(
            closed_bash.search(step),
            "authority-producing Bash must run behind an absolute env -i boundary",
        )

'''
new_closed = r'''        closed_bash = re.compile(
            r"builtin printf '%s' \"\$producer_bytes\" \|\s*/usr/bin/env\s+-i\b"
            r"(?:(?!builtin printf).)*?GITHUB_RUN_ID=\"\$\{\{ github\.run_id \}\}\""
            r"(?:(?!builtin printf).)*?/bin/bash\s+--noprofile\s+--norc\s+-p\s+-c\s+"
            r"'source /dev/stdin'",
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(
            closed_bash.search(step),
            "authority-producing Bash must consume pinned producer bytes behind the closed env -i boundary",
        )

    def test_clean_inner_environment_preserves_trusted_run_identity_for_pinned_producer(self) -> None:
        custody_step = self._step("Verify trusted Simulator evidence-producer custody")
        build_step = self._step("Build, test, and capture Simulator states")
        expected_path = f'producer_path="{TRUSTED_PRODUCER_PATH}"'
        expected_blob = f'expected_blob="{TRUSTED_PRODUCER_BLOB_SHA}"'

        self.assertIn(expected_path, custody_step)
        self.assertIn(expected_blob, custody_step)
        self.assertIn('/usr/bin/git rev-parse --verify "HEAD:${producer_path}"', custody_step)
        self.assertIn('test "$actual_blob" = "$expected_blob"', custody_step)

        self.assertIn(expected_path, build_step)
        self.assertIn(expected_blob, build_step)
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', build_step)
        self.assertIn('test "$materialized_blob" = "$expected_blob"', build_step)
        self.assertIn('GITHUB_RUN_ID="${{ github.run_id }}"', build_step)
        self.assertIn('GITHUB_RUN_ATTEMPT="${{ github.run_attempt }}"', build_step)
        self.assertNotIn('GITHUB_RUN_ID="$GITHUB_RUN_ID"', build_step)
        self.assertNotIn('GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT"', build_step)

'''
if "test_clean_inner_environment_preserves_trusted_run_identity_for_pinned_producer" not in bash_test:
    if bash_test.count(old_closed) != 1:
        raise SystemExit("expected one old closed-bash test body")
    bash_test = bash_test.replace(old_closed, new_closed, 1)
bash_test_path.write_text(bash_test)

final_workflow_blob = subprocess.check_output(
    ["git", "hash-object", str(workflow_path)],
    text=True,
).strip()
old_workflow_blob = "524b011c6147142281c3fed62d3bb402c7f2be63"
print(f"FINAL_TRUSTED_WORKFLOW_BLOB {final_workflow_blob}")

subject_path = root / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"
subject = subject_path.read_text()
if subject.count(old_workflow_blob) != 1:
    raise SystemExit(f"expected one old workflow pin in subject, found {subject.count(old_workflow_blob)}")
subject_path.write_text(subject.replace(old_workflow_blob, final_workflow_blob, 1))

for qa_relative in (
    ".github/workflows/capture-today-final-go-qa.yml",
    ".github/workflows/capture-today-trusted-default-xcode-subject-qa.yml",
):
    qa_path = root / qa_relative
    qa = qa_path.read_text()
    if qa.count(old_workflow_blob) != 1:
        raise SystemExit(f"expected one old workflow pin in {qa_relative}, found {qa.count(old_workflow_blob)}")
    qa = qa.replace(old_workflow_blob, final_workflow_blob, 1)
    qa = qa.replace(
        "- name: Preserve closed Bash startup custody\n",
        "- name: Preserve closed Bash startup custody and run provenance\n",
        1,
    )
    grep_anchor = '          grep -Fq \'test "$materialized_blob" = "$expected_blob"\' .github/workflows/capture-xcode27-trusted-command.yml\n'
    if qa.count(grep_anchor) != 1:
        raise SystemExit(f"expected one producer materialization grep in {qa_relative}")
    provenance_greps = (
        "          grep -Fq 'GITHUB_RUN_ID=\"$''{{ github.run_id }}\"' .github/workflows/capture-xcode27-trusted-command.yml\n"
        "          grep -Fq 'GITHUB_RUN_ATTEMPT=\"$''{{ github.run_attempt }}\"' .github/workflows/capture-xcode27-trusted-command.yml\n"
    )
    if "GITHUB_RUN_ID=" not in qa:
        qa = qa.replace(grep_anchor, grep_anchor + provenance_greps, 1)
    qa_path.write_text(qa)

commands = [
    ["python3", "scripts/ci/tests/test_capture_trusted_xcode_build_graph_custody.py", "-v"],
    ["python3", "scripts/ci/tests/test_capture_trusted_xcode_prevalidation_process_custody.py", "-v"],
    ["python3", "scripts/ci/tests/test_capture_trusted_xcode_bash_environment_custody.py", "-v"],
    ["python3", "scripts/ci/tests/test_es80_today_trusted_capture_xcode_subject.py", "-v"],
]
for command in commands:
    subprocess.run(command, check=True)

grep = subprocess.run(
    ["git", "grep", "-n", old_workflow_blob, "--", ".github", "scripts/ci"],
    text=True,
    capture_output=True,
)
if grep.returncode == 0:
    raise SystemExit("old trusted workflow pin remains:\n" + grep.stdout)

subprocess.run(["git", "diff", "--check"], check=True)

paths = [
    ".github/workflows/capture-xcode27-trusted-command.yml",
    ".github/workflows/capture-today-final-go-qa.yml",
    ".github/workflows/capture-today-trusted-default-xcode-subject-qa.yml",
    "scripts/ci/es80_today_trusted_capture_xcode_subject.py",
    "scripts/ci/tests/test_capture_trusted_xcode_build_graph_custody.py",
    "scripts/ci/tests/test_capture_trusted_xcode_bash_environment_custody.py",
]
token = os.environ["GH_TOKEN"]
repository = os.environ["REPOSITORY"]
endpoint = f"https://api.github.com/repos/{repository}/git/blobs"
for relative in paths:
    data = (root / relative).read_bytes()
    request = Request(
        endpoint,
        data=json.dumps({
            "content": base64.b64encode(data).decode("ascii"),
            "encoding": "base64",
        }).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    with urlopen(request, timeout=30) as response:
        payload = json.load(response)
    print(f"FINAL_TRUST_BLOB {relative} {payload['sha']}")
