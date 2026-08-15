#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

INSTALLER = Path("scripts/field/install_one_time_capture.command")
HANDOFF_TEST = Path("scripts/ci/tests/test_capture_frozen_device_tool_handoff.py")


def transform_installer() -> None:
    lines = INSTALLER.read_text(encoding="utf-8").splitlines(keepends=True)
    marker = "    /usr/bin/env -i \\\n"
    matches = [index for index, line in enumerate(lines) if line == marker]
    if len(matches) != 1:
        raise SystemExit(f"installer frozen-tool trampoline count changed: {len(matches)}")
    index = matches[0]
    expected_tail = [
        "        PATH=/usr/bin:/bin:/usr/sbin:/sbin \\\n",
        "        HOME=/tmp \\\n",
        "        TMPDIR=/tmp \\\n",
        "        LANG=C \\\n",
        "        LC_ALL=C \\\n",
        "        DEVELOPER_DIR=\"$SELECTED_XCODE_DEVELOPER_DIR\" \\\n",
        "        \"$tool\" \"$@\"\n",
    ]
    actual_tail = lines[index + 1 : index + 1 + len(expected_tail)]
    if actual_tail != expected_tail:
        raise SystemExit("installer frozen-tool trampoline body changed")
    replacement = [
        "    (\n",
        "        # Bash builtin `exec -c` clears inherited environment before the first\n",
        "        # dynamically linked external image is loaded, so hostile DYLD_*\n",
        "        # selectors cannot influence /usr/bin/env itself.\n",
        "        exec -c /usr/bin/env -i \\\n",
    ]
    replacement.extend("    " + line for line in expected_tail)
    replacement.append("    )\n")
    lines[index : index + 1 + len(expected_tail)] = replacement
    INSTALLER.write_text("".join(lines), encoding="utf-8")


def transform_regression() -> None:
    source = HANDOFF_TEST.read_text(encoding="utf-8")
    old = '            "/usr/bin/env -i",\n'
    new = '            "exec -c /usr/bin/env -i",\n'
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"frozen-tool source regression seam count changed: {count}")
    HANDOFF_TEST.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    transform_installer()
    transform_regression()


if __name__ == "__main__":
    main()
