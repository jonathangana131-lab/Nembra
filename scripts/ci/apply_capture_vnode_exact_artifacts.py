from pathlib import Path


GUARD = Path("Scripts/capture_tuya_private_input_build_guard.py")
FIELD = Path(".github/workflows/capture-field-build-provenance.yml")
TEST_PATH = "scripts/ci/tests/test_capture_cocoapods_vnode_attribute_custody.py"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def patch_guard() -> None:
    text = GUARD.read_text(encoding="utf-8")
    text = replace_once(
        text,
        '            "KQ_NOTE_EXTEND",\n            "KQ_NOTE_LINK",\n',
        '            "KQ_NOTE_EXTEND",\n            "KQ_NOTE_ATTRIB",\n            "KQ_NOTE_LINK",\n',
        "required kqueue attribute capability",
    )
    text = replace_once(
        text,
        "            | select.KQ_NOTE_EXTEND\n            | select.KQ_NOTE_LINK\n",
        "            | select.KQ_NOTE_EXTEND\n            | select.KQ_NOTE_ATTRIB\n            | select.KQ_NOTE_LINK\n",
        "vnode attribute subscription",
    )
    if text.count("KQ_NOTE_ATTRIB") != 2:
        raise SystemExit(f"expected exactly two production KQ_NOTE_ATTRIB references, found {text.count('KQ_NOTE_ATTRIB')}")
    GUARD.write_text(text, encoding="utf-8")


def patch_field() -> None:
    text = FIELD.read_text(encoding="utf-8")
    trigger = "      - scripts/ci/tests/test_capture_field_accepted_source_path_contract.py\n"
    text = replace_once(
        text,
        trigger,
        trigger + f"      - {TEST_PATH}\n",
        "vnode regression pull-request trigger",
    )
    anchor = "      - name: Verify source contract\n"
    step = (
        "      - name: Validate compiler-window vnode attribute custody\n"
        "        shell: bash\n"
        "        run: |\n"
        "          set -euo pipefail\n"
        f"          /usr/bin/python3 -m py_compile {TEST_PATH}\n"
        f"          /usr/bin/python3 {TEST_PATH}\n\n"
    )
    text = replace_once(text, anchor, step + anchor, "xcode-27 vnode evidence step")
    if text.count(TEST_PATH) != 3:
        raise SystemExit(f"expected vnode regression path three times, found {text.count(TEST_PATH)}")
    FIELD.write_text(text, encoding="utf-8")


def main() -> None:
    patch_guard()
    patch_field()


if __name__ == "__main__":
    main()
