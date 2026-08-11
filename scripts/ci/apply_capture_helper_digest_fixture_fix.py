from pathlib import Path


TARGETS = (
    Path("scripts/ci/tests/test_capture_private_review_commitment.py"),
    Path("scripts/ci/tests/test_capture_private_review_helper_execution_custody.py"),
)

OLD = "scripts / SUBJECT_HELPER.name"
NEW = "scripts / GENERATED.name"


def main() -> None:
    for path in TARGETS:
        text = path.read_text(encoding="utf-8")
        count = text.count(OLD)
        if count != 1:
            raise SystemExit(f"{path}: expected one stale generated-helper symbol, found {count}")
        path.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")


if __name__ == "__main__":
    main()
