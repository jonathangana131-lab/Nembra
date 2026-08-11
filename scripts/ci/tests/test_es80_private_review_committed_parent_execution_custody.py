#!/usr/bin/env python3
"""Prove committed descendant parent bytes cannot replace the exact accepted Final-GO parent."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
CHILD_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
FIXTURE_CHILD_RELATIVE = "scripts/ci/private_review_child_fixture.py"
PARENT_RELATIVE = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"


class PrivateReviewCommittedParentExecutionCustodyTests(unittest.TestCase):
    def test_committed_descendant_parent_replacement_never_executes(self) -> None:
        child_source = CHILD_SOURCE.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory(prefix="nembra-private-parent-descendant-") as temporary:
            root = Path(temporary).resolve(strict=True)
            parent = root / PARENT_RELATIVE
            fixture_child = root / FIXTURE_CHILD_RELATIVE
            sentinel = root / "committed-attacker-parent-executed"
            parent.parent.mkdir(parents=True, exist_ok=True)

            # The accepted historical parent exposes the metadata/symbol shape
            # the current child reads while importing, but performs no side
            # effects. The current vnode adapter may inspect the historical
            # generated-parent contract without ever executing descendant bytes.
            parent.write_text(
                "#!/usr/bin/env python3\n"
                "import types\n"
                "def fixture_candidate(*args, **kwargs): return {}\n"
                "generated = types.SimpleNamespace(\n"
                "    GENERATED_BUILD_WORKFLOW='Capture CocoaPods Build Subject Authority',\n"
                "    GENERATED_BUILD_WORKFLOW_PATH='.github/workflows/capture-cocoapods-build-subject-redteam.yml',\n"
                "    VNODE_WORKFLOW='Capture CocoaPods Vnode Attribute Convergence',\n"
                "    VNODE_WORKFLOW_PATH='.github/workflows/capture-cocoapods-vnode-attribute-convergence.yml',\n"
                "    GENERATED_ACCEPTANCE_WORKFLOWS=((\n"
                "        'Capture CocoaPods Build Subject Authority',\n"
                "        '.github/workflows/capture-cocoapods-build-subject-redteam.yml'\n"
                "    ), (\n"
                "        'Capture CocoaPods Vnode Attribute Convergence',\n"
                "        '.github/workflows/capture-cocoapods-vnode-attribute-convergence.yml'\n"
                "    )),\n"
                "    GENERATED_AUTHORITY_PATHS=(\n"
                "        '.github/workflows/capture-cocoapods-vnode-attribute-convergence.yml',\n"
                "    ),\n"
                "    candidate_generated_authority=fixture_candidate,\n"
                ")\n"
                "class PrivateReviewGoError(RuntimeError): pass\n"
                "REPO='fixture/repo'\nOWNER='fixture'\nPARENT_BRANCH='fixture-parent'\n"
                "WORKFLOW_NAME='fixture-workflow'\nWORKFLOW_PATH='fixture.yml'\n"
                "REVIEW_AUTHORITY='fixture-review'\nFINAL_AUTHORITY='fixture-final'\n"
                "PRIVATE_CONTROL_EXTENSION='fixture-extension'\n"
                "PRIVATE_REVIEW_COMMITMENT_KEY='private'\nPRIVATE_REVIEW_HELPER_KEY='private-helper'\n"
                "PROVENANCE_HELPER_KEY='provenance-helper'\nGENERATED_HELPER_KEY='generated-helper'\n"
                "PRIVATE_REVIEW_ENV='PRIVATE_ENV'\nPRIVATE_REVIEW_HELPER_ENV='PRIVATE_HELPER_ENV'\n"
                "PROVENANCE_HELPER_ENV='PROVENANCE_ENV'\nGENERATED_HELPER_ENV='GENERATED_ENV'\n"
                "PRIVATE_REVIEW_HELPER_PATH='private.py'\nPROVENANCE_HELPER_PATH='provenance.py'\n"
                "PRIVATE_REVIEW_DOMAIN='fixture-domain'\nCHILD_AUTHORITY_PATHS=()\nPARENT_PINNED_PATHS=()\n"
                "PARENT_GENERATED_MODULE_GIT_BLOB='0'*40\n"
                "def review_v5(*args, **kwargs): return {}\n"
                "def private_control_plane(*args, **kwargs): return {}\n"
                "def candidate_private_authority(*args, **kwargs): return {}\n"
                "def _private_environment_adapter(*args, **kwargs): return None\n"
                "def _generated_extensions(*args, **kwargs): return None\n"
                "def build(*args, **kwargs): return {}\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", PARENT_RELATIVE], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted private-review parent"], check=True)
            accepted_source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
            ).strip().lower()
            accepted_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", f"{accepted_source}:{PARENT_RELATIVE}"], text=True
            ).strip().lower()

            patched_child = child_source.replace(
                'PARENT_SOURCE = "3c8711f8520b93e2647ec9e3b52d50894193bc30"',
                f'PARENT_SOURCE = "{accepted_source}"',
                1,
            ).replace(
                'PARENT_MODULE_GIT_BLOB = "c6c0b68ad9c2af7cd3378c721752fbca7d4ed9e9"',
                f'PARENT_MODULE_GIT_BLOB = "{accepted_blob}"',
                1,
            )
            self.assertIn(f'PARENT_SOURCE = "{accepted_source}"', patched_child)
            self.assertIn(f'PARENT_MODULE_GIT_BLOB = "{accepted_blob}"', patched_child)
            fixture_child.parent.mkdir(parents=True, exist_ok=True)
            fixture_child.write_text(patched_child, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", FIXTURE_CHILD_RELATIVE], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted child fixture"], check=True)

            # Commit attacker-controlled descendant bytes at the parent's path.
            # The child must still execute only accepted_source:accepted_blob.
            parent.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", PARENT_RELATIVE], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "attacker replaces private parent"], check=True)

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("private_review_committed_parent_fixture", fixture_child)
                if spec is None or spec.loader is None:
                    self.fail("could not load private-review fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "committed descendant parent bytes executed instead of exact accepted historical parent",
            )
            self.assertEqual(module._parent.__nembra_accepted_control_source__, accepted_source)
            self.assertEqual(module._parent.__nembra_accepted_control_blob__, accepted_blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)
