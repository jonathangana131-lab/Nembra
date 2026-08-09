#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

START_WORKFLOW_BLOB = "a8250ffd683db129d85010fb227ea1c7439eacab"
PRODUCER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one seam, found {count}")
    return text.replace(old, new, 1)


def git_blob(path: Path) -> str:
    return subprocess.check_output(["git", "hash-object", str(path)], text=True).strip()


workflow_path = Path(".github/workflows/capture-xcode27-trusted-command.yml")
if git_blob(workflow_path) != START_WORKFLOW_BLOB:
    raise SystemExit("starting trusted workflow bytes moved; refuse stale composition")
workflow = workflow_path.read_text(encoding="utf-8")

selector_needle = '''          if nembra_schemes != expected_nembra_schemes:
              raise SystemExit(
                  "trusted build graph requires exactly the reviewed shared Nembra scheme: "
                  + repr(nembra_schemes)
              )
          for relative, expected_blob in expected.items():
'''
selector_replacement = '''          if nembra_schemes != expected_nembra_schemes:
              raise SystemExit(
                  "trusted build graph requires exactly the reviewed shared Nembra scheme: "
                  + repr(nembra_schemes)
              )
          reviewed_package_roots = (
              root / "Packages/NembraCore",
              root / "Packages/NembraBluetoothCapture",
          )
          alternate_package_manifests = sorted(
              str(path.relative_to(root))
              for package_root in reviewed_package_roots
              for path in package_root.glob("*")
              if path.name.casefold().startswith("package@swift-")
              and path.name.casefold().endswith(".swift")
          )
          if alternate_package_manifests:
              raise SystemExit(
                  "trusted build graph forbids unreviewed Package@swift-* selectors: "
                  + ", ".join(alternate_package_manifests)
              )
          for relative, expected_blob in expected.items():
'''
workflow = replace_once(workflow, selector_needle, selector_replacement, "SwiftPM selector custody")

provenance_needle = '''          builtin printf '%s' "$producer_bytes" |
            /usr/bin/env -i \\
              PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
              HOME=/tmp \\
              LC_ALL=C \\
              GIT_DIR="$GITHUB_WORKSPACE/.git" \\
'''
provenance_replacement = '''          builtin printf '%s' "$producer_bytes" |
            /usr/bin/env -i \\
              PATH=/usr/bin:/bin:/usr/sbin:/sbin \\
              HOME=/tmp \\
              LC_ALL=C \\
              GITHUB_RUN_ID="${{ github.run_id }}" \\
              GITHUB_RUN_ATTEMPT="${{ github.run_attempt }}" \\
              GIT_DIR="$GITHUB_WORKSPACE/.git" \\
'''
workflow = replace_once(workflow, provenance_needle, provenance_replacement, "trusted run provenance")
workflow_path.write_text(workflow, encoding="utf-8")
new_workflow_blob = git_blob(workflow_path)
if not new_workflow_blob or new_workflow_blob == START_WORKFLOW_BLOB:
    raise SystemExit("trusted workflow blob did not rotate")

# Absorb the stronger selector regression over the exact #1718 scheme guard.
graph_test_path = Path("scripts/ci/tests/test_capture_trusted_xcode_build_graph_custody.py")
graph_test = graph_test_path.read_text(encoding="utf-8")
graph_anchor = '''    def test_candidate_prevalidation_does_not_share_authority_runner(self) -> None:
'''
graph_method = '''    def test_authority_rejects_version_specific_package_manifest_selectors(self) -> None:
        authority = self.workflow.index("  capture-simulator-qa:\\n")
        authority_block = self.workflow[authority:]
        custody = authority_block.index("- name: Verify trusted build graph custody")
        build = authority_block.index("- name: Build, test, and capture Simulator states")
        between = authority_block[custody:build]
        self.assertIn('root / "Packages/NembraCore"', between)
        self.assertIn('root / "Packages/NembraBluetoothCapture"', between)
        self.assertIn('package_root.glob("*")', between)
        self.assertIn('package@swift-', between)
        self.assertIn('alternate_package_manifests', between)
        self.assertIn('trusted build graph forbids unreviewed Package@swift-* selectors', between)

    def test_candidate_prevalidation_does_not_share_authority_runner(self) -> None:
'''
graph_test_path.write_text(
    replace_once(graph_test, graph_anchor, graph_method, "build graph selector regression"),
    encoding="utf-8",
)

# Preserve only GitHub context-expanded run identity inside the already closed env-i boundary.
bash_test_path = Path("scripts/ci/tests/test_capture_trusted_xcode_bash_environment_custody.py")
bash_test = bash_test_path.read_text(encoding="utf-8")
bash_doc_old = '''BASH_ENV, ENV, exported shell functions, or GITHUB_PATH command substitution cannot run before the
pinned producer or its retained-evidence verifier.
'''
bash_doc_new = '''BASH_ENV, ENV, exported shell functions, or GITHUB_PATH command substitution cannot run before the
pinned producer or its retained-evidence verifier. The clean inner environment must still receive
the trusted GitHub run identity that the frozen producer records as retained provenance.
'''
bash_test = replace_once(bash_test, bash_doc_old, bash_doc_new, "Bash custody documentation")
constants_old = '''ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
PRIVILEGED_SHELL = 'shell: "/bin/bash --noprofile --norc -p -e -o pipefail {0}"'
'''
constants_new = f'''ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
TRUSTED_PRODUCER_PATH = "scripts/ci/xcode27_simulator_capture.sh"
TRUSTED_PRODUCER_BLOB_SHA = "{PRODUCER_BLOB}"
PRIVILEGED_SHELL = 'shell: "/bin/bash --noprofile --norc -p -e -o pipefail {{0}}"'
'''
bash_test = replace_once(bash_test, constants_old, constants_new, "Bash custody constants")
method_anchor = '''    def test_retained_evidence_step_cannot_reopen_candidate_bash_startup_authority(self) -> None:
'''
method = '''    def test_clean_inner_environment_preserves_trusted_run_identity_for_pinned_producer(self) -> None:
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

    def test_retained_evidence_step_cannot_reopen_candidate_bash_startup_authority(self) -> None:
'''
bash_test_path.write_text(
    replace_once(bash_test, method_anchor, method, "run provenance regression"),
    encoding="utf-8",
)

# Rotate all current default-subject consumers exactly once, and make the hosted wrappers pin the
# two new source-level authority boundaries in addition to executing their semantic tests.
pin_paths = (
    Path("scripts/ci/es80_today_trusted_capture_xcode_subject.py"),
    Path(".github/workflows/capture-today-final-go-qa.yml"),
    Path(".github/workflows/capture-today-trusted-default-xcode-subject-qa.yml"),
)
for path in pin_paths:
    text = path.read_text(encoding="utf-8")
    text = replace_once(text, START_WORKFLOW_BLOB, new_workflow_blob, f"{path} trusted workflow pin")
    if path.suffix == ".yml":
        text = replace_once(
            text,
            "      - name: Preserve closed Bash startup custody\n",
            "      - name: Preserve closed Bash startup custody and run provenance\n",
            f"{path} run-provenance step label",
        )
        grep_anchor = '''          grep -Fq 'test "$materialized_blob" = "$expected_blob"' .github/workflows/capture-xcode27-trusted-command.yml
'''
        grep_extra = grep_anchor + '''          grep -Fq 'Package@swift-' .github/workflows/capture-xcode27-trusted-command.yml
          grep -Fq 'GITHUB_RUN_ID="$''{{ github.run_id }}"' .github/workflows/capture-xcode27-trusted-command.yml
          grep -Fq 'GITHUB_RUN_ATTEMPT="$''{{ github.run_attempt }}"' .github/workflows/capture-xcode27-trusted-command.yml
'''
        text = replace_once(text, grep_anchor, grep_extra, f"{path} authority grep seam")
    path.write_text(text, encoding="utf-8")

print(new_workflow_blob)
