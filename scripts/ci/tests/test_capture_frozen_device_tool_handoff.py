#!/usr/bin/env python3
"""Portable regression for post-build selected-Xcode device-tool custody."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


def load():
    spec = importlib.util.spec_from_file_location("nembra_frozen_device_tool_handoff", ORCHESTRATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureFrozenDeviceToolHandoffTests(unittest.TestCase):
    def test_returned_device_tools_must_remain_inside_frozen_developer_tree(self) -> None:
        helper = load()
        developer = Path("/Library/NembraSelectedXcodeFreeze.test/Xcode.app/Contents/Developer")
        xctrace = developer / "usr/bin/xctrace"
        devicectl = developer / "usr/bin/devicectl"
        self.assertEqual(helper._require_frozen_tool({"xctrace": xctrace}, "xctrace", developer), xctrace)
        self.assertEqual(helper._require_frozen_tool({"devicectl": devicectl}, "devicectl", developer), devicectl)
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._require_frozen_tool({"devicectl": Path("/usr/bin/devicectl")}, "devicectl", developer)

    def test_main_serializes_exact_five_field_handoff(self) -> None:
        helper = load()
        expected = (
            Path("/private/tmp/nembra-authenticated-capture-install.fixture"),
            "b" * 64,
            Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"),
            Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer/usr/bin/xctrace"),
            Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer/usr/bin/devicectl"),
        )
        args = mock.Mock(
            field_pid=4242,
            source_sha="a" * 40,
            freeze_launcher_base64="launcher",
            freeze_launcher_blob="a" * 40,
            freeze_helper_base64="freeze",
            freeze_helper_blob="b" * 40,
            build_origin_base64="origin",
            build_origin_blob="c" * 40,
            install_custody_base64="install",
            install_custody_blob="d" * 40,
            command=["/usr/bin/xcodebuild"],
        )
        with (
            mock.patch.object(helper, "_parse", return_value=args),
            mock.patch.object(helper, "orchestrate", return_value=expected),
            mock.patch.object(helper.sys, "stdout") as stdout,
        ):
            self.assertEqual(helper.main([]), 0)
        stdout.write.assert_called_once_with("\t".join(str(value) for value in expected) + "\n")

    def test_installer_uses_only_frozen_device_tools(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        syntax = subprocess.run(
            ["/bin/bash", "-n", str(INSTALLER)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        for fragment in (
            "IFS=$'\\t' read -r APP_INSTALL_STAGE_ROOT STAGED_APP_TREE_SHA256 SELECTED_XCODE_DEVELOPER_DIR SELECTED_XCTRACE SELECTED_DEVICECTL RESULT_EXTRA",
            '[[ "$SELECTED_XCTRACE" == "$SELECTED_XCODE_DEVELOPER_DIR"/* && -x "$SELECTED_XCTRACE" ]]',
            '[[ "$SELECTED_DEVICECTL" == "$SELECTED_XCODE_DEVELOPER_DIR"/* && -x "$SELECTED_DEVICECTL" ]]',
            '/usr/bin/env -i',
            'DEVELOPER_DIR="$SELECTED_XCODE_DEVELOPER_DIR"',
            'run_frozen_xcode_tool "$SELECTED_XCTRACE" list devices',
            'run_frozen_xcode_tool "$SELECTED_DEVICECTL" list devices --hide-headers',
            'run_frozen_xcode_tool "$SELECTED_DEVICECTL" device install app',
            'run_frozen_xcode_tool "$SELECTED_DEVICECTL" device process launch',
        ):
            self.assertIn(fragment, source)
        for forbidden in ("xcrun xctrace", "xcrun devicectl", "open -a Xcode", "command -v xcrun"):
            self.assertNotIn(forbidden, source)

    def test_frozen_device_tool_wrapper_scrubs_hostile_caller_environment(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        start = source.index("run_frozen_xcode_tool() {")
        end = source.index("\n}\n\n# Both privileged layers", start) + len("\n}\n")
        function_source = source[start:end]

        with tempfile.TemporaryDirectory(prefix="nembra-frozen-device-tools-") as temporary:
            root = Path(temporary)
            developer = root / "Xcode.app/Contents/Developer"
            tools = developer / "usr/bin"
            tools.mkdir(parents=True)
            xctrace = tools / "xctrace"
            devicectl = tools / "devicectl"
            probe = """#!/bin/bash
printf 'DEVELOPER_DIR=%s\\n' "${DEVELOPER_DIR-<unset>}"
printf 'HOME=%s\\n' "${HOME-<unset>}"
printf 'TMPDIR=%s\\n' "${TMPDIR-<unset>}"
printf 'LANG=%s\\n' "${LANG-<unset>}"
printf 'LC_ALL=%s\\n' "${LC_ALL-<unset>}"
printf 'TOOLCHAINS=%s\\n' "${TOOLCHAINS-<unset>}"
printf 'DYLD_INSERT_LIBRARIES=%s\\n' "${DYLD_INSERT_LIBRARIES-<unset>}"
printf 'SDKROOT=%s\\n' "${SDKROOT-<unset>}"
"""
            for tool in (xctrace, devicectl):
                tool.write_text(probe, encoding="utf-8")
                tool.chmod(0o755)

            wrapper = root / "wrapper.sh"
            wrapper.write_text(
                "#!/bin/bash\nset -euo pipefail\n"
                "die() { printf 'ERROR: %s\\n' \"$*\" >&2; exit 77; }\n"
                f"SELECTED_XCODE_DEVELOPER_DIR={str(developer)!r}\n"
                f"SELECTED_XCTRACE={str(xctrace)!r}\n"
                f"SELECTED_DEVICECTL={str(devicectl)!r}\n"
                + function_source
                + "tool=\"$1\"\nshift\nrun_frozen_xcode_tool \"$tool\" \"$@\"\n",
                encoding="utf-8",
            )
            wrapper.chmod(0o755)
            hostile = dict(os.environ)
            hostile.update(
                {
                    "DEVELOPER_DIR": "/Applications/AttackerXcode.app/Contents/Developer",
                    "TOOLCHAINS": "attacker.toolchain",
                    "DYLD_INSERT_LIBRARIES": "/tmp/attacker.dylib",
                    "SDKROOT": "/tmp/attacker.sdk",
                    "HOME": "/tmp/attacker-home",
                    "TMPDIR": "/tmp/attacker-tmp",
                    "LANG": "zz_ZZ.UTF-8",
                    "LC_ALL": "zz_ZZ.UTF-8",
                }
            )
            completed = subprocess.run(
                ["/bin/bash", str(wrapper), str(devicectl), "device", "list"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=hostile,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            observed = dict(line.split("=", 1) for line in completed.stdout.splitlines() if "=" in line)
            self.assertEqual(observed["DEVELOPER_DIR"], str(developer))
            self.assertEqual(observed["HOME"], "/tmp")
            self.assertEqual(observed["TMPDIR"], "/tmp")
            self.assertEqual(observed["LANG"], "C")
            self.assertEqual(observed["LC_ALL"], "C")
            self.assertEqual(observed["TOOLCHAINS"], "<unset>")
            self.assertEqual(observed["DYLD_INSERT_LIBRARIES"], "<unset>")
            self.assertEqual(observed["SDKROOT"], "<unset>")

            rejected = subprocess.run(
                ["/bin/bash", str(wrapper), str(root / "attacker-devicectl")],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=hostile,
                check=False,
            )
            self.assertEqual(rejected.returncode, 77)
            self.assertIn("unadmitted Xcode device tool", rejected.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
