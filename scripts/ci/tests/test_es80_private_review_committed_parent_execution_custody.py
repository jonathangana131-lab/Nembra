#!/usr/bin/env python3
"""Prove descendant commits cannot replace any accepted Final-GO execution parent.

Current Final-GO is a sealed-handoff successor of the continuous-custody
predecessor, which is itself an exact successor of #2921 -> #2873. Build that
same execution chain in a temporary repository and then overwrite the reused
module pathname with committed attacker bytes. Every layer must still execute
only its previously accepted Git blob.
"""
from __future__ import annotations

import hashlib
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

PREDECESSOR_SOURCE = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
PREDECESSOR_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"
DIRECT_PARENT_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
DIRECT_PARENT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"
HISTORICAL_PARENT_SOURCE = "3c8711f8520b93e2647ec9e3b52d50894193bc30"
HISTORICAL_PARENT_BLOB = "c6c0b68ad9c2af7cd3378c721752fbca7d4ed9e9"


def _blob_oid(payload: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


def _accepted_blob_text(blob: str) -> str:
    payload = subprocess.check_output(
        ["/usr/bin/git", "-C", str(REPOSITORY), "cat-file", "blob", blob]
    )
    if _blob_oid(payload) != blob:
        raise RuntimeError("fixture Git lookup returned bytes outside accepted identity")
    return payload.decode("utf-8")


def _commit(root: Path, message: str) -> tuple[str, str]:
    subprocess.run(["/usr/bin/git", "-C", str(root), "add", PARENT_RELATIVE], check=True)
    subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", message], check=True)
    source = subprocess.check_output(
        ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip().lower()
    blob = subprocess.check_output(
        ["/usr/bin/git", "-C", str(root), "rev-parse", f"{source}:{PARENT_RELATIVE}"],
        text=True,
    ).strip().lower()
    return source, blob


def _replace_once(text: str, old: str, new: str) -> str:
    replaced = text.replace(old, new, 1)
    if replaced == text or new not in replaced:
        raise AssertionError(f"fixture pin was not replaced: {old}")
    return replaced


class PrivateReviewCommittedParentExecutionCustodyTests(unittest.TestCase):
    @staticmethod
    def _write_historical_parent(parent: Path) -> None:
        parent.write_text(
            "#!/usr/bin/env python3\n"
            "import contextlib\nimport types\n"
            "def fixture_candidate(*args, **kwargs): return {}\n"
            "generated = types.SimpleNamespace(\n"
            " GENERATED_BUILD_WORKFLOW='Capture CocoaPods Build Subject Authority',\n"
            " GENERATED_BUILD_WORKFLOW_PATH='.github/workflows/capture-cocoapods-build-subject-redteam.yml',\n"
            " VNODE_WORKFLOW='Capture CocoaPods Vnode Attribute Convergence',\n"
            " VNODE_WORKFLOW_PATH='.github/workflows/capture-cocoapods-vnode-attribute-convergence.yml',\n"
            " GENERATED_ACCEPTANCE_WORKFLOWS=((\n"
            "  'Capture CocoaPods Build Subject Authority',\n"
            "  '.github/workflows/capture-cocoapods-build-subject-redteam.yml'\n"
            " ), (\n"
            "  'Capture CocoaPods Vnode Attribute Convergence',\n"
            "  '.github/workflows/capture-cocoapods-vnode-attribute-convergence.yml'\n"
            " )),\n"
            " GENERATED_AUTHORITY_PATHS=(\n"
            "  '.github/workflows/capture-cocoapods-vnode-attribute-convergence.yml',\n"
            " ),\n"
            " candidate_generated_authority=fixture_candidate,\n"
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
            "def _private_environment_adapter(*args, **kwargs): return contextlib.nullcontext()\n"
            "def _generated_extensions(*args, **kwargs): return contextlib.nullcontext()\n"
            "def build(*args, **kwargs): return {}\n",
            encoding="utf-8",
        )

    def test_committed_descendant_parent_replacement_never_executes(self) -> None:
        child_source = CHILD_SOURCE.read_text(encoding="utf-8")
        source_2921 = _accepted_blob_text(DIRECT_PARENT_BLOB)
        source_continuous = _accepted_blob_text(PREDECESSOR_BLOB)

        with tempfile.TemporaryDirectory(prefix="nembra-parent-chain-") as temporary:
            root = Path(temporary).resolve(strict=True)
            parent = root / PARENT_RELATIVE
            fixture_child = root / FIXTURE_CHILD_RELATIVE
            sentinel = root / "committed-attacker-parent-executed"
            parent.parent.mkdir(parents=True, exist_ok=True)

            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"],
                check=True,
            )

            # Level 1: historical semantic parent.
            self._write_historical_parent(parent)
            historical_source, historical_blob = _commit(root, "accepted historical parent")

            # Level 2: exact #2921 with only its historical pins redirected.
            fixture_2921 = _replace_once(
                source_2921,
                f'PARENT_SOURCE = "{HISTORICAL_PARENT_SOURCE}"',
                f'PARENT_SOURCE = "{historical_source}"',
            )
            fixture_2921 = _replace_once(
                fixture_2921,
                f'PARENT_MODULE_GIT_BLOB = "{HISTORICAL_PARENT_BLOB}"',
                f'PARENT_MODULE_GIT_BLOB = "{historical_blob}"',
            )
            parent.write_text(fixture_2921, encoding="utf-8")
            direct_source, direct_blob = _commit(root, "accepted #2921 fixture")

            # Level 3: exact continuous-custody predecessor with only #2921 pins redirected.
            fixture_continuous = _replace_once(
                source_continuous,
                f'DIRECT_PARENT_SOURCE = "{DIRECT_PARENT_SOURCE}"',
                f'DIRECT_PARENT_SOURCE = "{direct_source}"',
            )
            fixture_continuous = _replace_once(
                fixture_continuous,
                f'DIRECT_PARENT_MODULE_GIT_BLOB = "{DIRECT_PARENT_BLOB}"',
                f'DIRECT_PARENT_MODULE_GIT_BLOB = "{direct_blob}"',
            )
            parent.write_text(fixture_continuous, encoding="utf-8")
            predecessor_source, predecessor_blob = _commit(root, "accepted continuous predecessor")

            # Current sealed-handoff child executes only the accepted predecessor blob.
            patched_child = _replace_once(
                child_source,
                f'PREDECESSOR_SOURCE = "{PREDECESSOR_SOURCE}"',
                f'PREDECESSOR_SOURCE = "{predecessor_source}"',
            )
            patched_child = _replace_once(
                patched_child,
                f'PREDECESSOR_MODULE_GIT_BLOB = "{PREDECESSOR_BLOB}"',
                f'PREDECESSOR_MODULE_GIT_BLOB = "{predecessor_blob}"',
            )
            fixture_child.parent.mkdir(parents=True, exist_ok=True)
            fixture_child.write_text(patched_child, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", FIXTURE_CHILD_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted current child fixture"],
                check=True,
            )

            # Replace the reused canonical parent pathname with committed attacker bytes.
            parent.write_text(
                "#!/usr/bin/env python3\nfrom pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n",
                encoding="utf-8",
            )
            _commit(root, "attacker replaces current parent path")

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location(
                    "private_review_committed_parent_fixture", fixture_child
                )
                if spec is None or spec.loader is None:
                    self.fail("could not load private-review fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "committed descendant bytes executed instead of accepted parent-chain blobs",
            )
            self.assertEqual(module._previous.__nembra_predecessor_source__, predecessor_source)
            self.assertEqual(module._previous.__nembra_predecessor_blob__, predecessor_blob)
            self.assertEqual(module._direct_parent.__nembra_direct_parent_source__, direct_source)
            self.assertEqual(module._direct_parent.__nembra_direct_parent_blob__, direct_blob)
            self.assertEqual(module._parent.__nembra_accepted_control_source__, historical_source)
            self.assertEqual(module._parent.__nembra_accepted_control_blob__, historical_blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)
