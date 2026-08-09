#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_DIR = Path(__file__).resolve().parents[1]
MODULE_PATH = MODULE_DIR / "es80_today_final_go_hardened.py"
SPEC = importlib.util.spec_from_file_location("nembra_hardened_crosscheck_test", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load hardened Final GO entrypoint")
hardened = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hardened)


class FinalGoCrosscheckExecutionCustodyTests(unittest.TestCase):
    def _receipt(self, prefix: str) -> dict[str, object]:
        return {key: f"{prefix}-{key}" for key in hardened.foundation.CROSSCHECK_KEYS}

    def test_retained_receipt_must_equal_fresh_pinned_producer_result(self) -> None:
        recomputed = self._receipt("fresh")
        supplied = dict(recomputed)
        supplied["status"] = "PASS_NOT_FINAL_GO"

        with tempfile.TemporaryDirectory(prefix="nembra-crosscheck-custody-test-") as temporary:
            receipt_path = Path(temporary) / "receipt.json"
            receipt_path.write_text(json.dumps(supplied), encoding="utf-8")
            with mock.patch.object(
                hardened,
                "_recompute_pinned_crosscheck_receipt",
                return_value=recomputed,
            ):
                with self.assertRaisesRegex(
                    hardened.FinalGoError,
                    "not reproduced by the exact pinned producer",
                ):
                    hardened._require_pinned_crosscheck_execution(
                        candidate_root=Path(temporary),
                        expected_source_sha="a" * 40,
                        independent_crosscheck_receipt=receipt_path,
                        tooling_repo=Path(temporary),
                    )

    def test_recompute_executes_materialized_pinned_source_in_isolated_python(self) -> None:
        expected = self._receipt("computed")
        source = (
            "#!/usr/bin/env python3\n"
            "import json\n"
            f"print(json.dumps({expected!r}, sort_keys=True))\n"
        ).encode("utf-8")
        with tempfile.TemporaryDirectory(prefix="nembra-crosscheck-subprocess-test-") as temporary:
            with mock.patch.object(hardened, "_pinned_crosscheck_source", return_value=source):
                actual = hardened._recompute_pinned_crosscheck_receipt(
                    candidate_root=Path(temporary),
                    expected_source_sha="b" * 40,
                    tooling_repo=Path(temporary),
                )
        self.assertEqual(actual, expected)

    def test_hardened_source_keeps_closed_producer_execution_contract_visible(self) -> None:
        source = MODULE_PATH.read_text(encoding="utf-8")
        for required in (
            '["/usr/bin/git", "cat-file", "blob", expected_blob]',
            'hashlib.sha1(b"blob "',
            '"/usr/bin/python3",',
            '"-I",',
            '"--candidate-dir",',
            '"--expected-source-sha",',
            "independent crosscheck receipt was not reproduced by the exact pinned producer",
        ):
            self.assertIn(required, source)


if __name__ == "__main__":
    unittest.main()
