#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
TEST = ROOT / "scripts/ci/tests/test_capture_field_tracked_source_window_authority.py"
PARENT_SHA = "d0b134ca2a49edc029f114660dfb8e216ece682e"
DIAGNOSTIC_BRANCH = "adversarial/v14-field-prearmed-untracked-window-sol-20260811"
DIAGNOSTIC_SHA = "c57e9bf0a168c66075faecf007ec7d43eb6a21c5"
DIAGNOSTIC_TEST_BLOB = "e28912b8b05576fbf10f85714ae30cb1248849be"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def materialize_diagnostic() -> None:
    subprocess.run(
        ["git", "fetch", "--no-tags", "origin", DIAGNOSTIC_BRANCH],
        cwd=ROOT,
        check=True,
    )
    fetched = git("rev-parse", "FETCH_HEAD")
    require(fetched == DIAGNOSTIC_SHA, f"diagnostic branch moved: {fetched}")
    payload = subprocess.check_output(
        ["git", "show", f"{DIAGNOSTIC_SHA}:{TEST.relative_to(ROOT).as_posix()}"],
        cwd=ROOT,
    )
    TEST.write_bytes(payload)
    require(git("hash-object", TEST.relative_to(ROOT).as_posix()) == DIAGNOSTIC_TEST_BLOB, "diagnostic test blob mismatch")


def repair_guard() -> None:
    source = GUARD.read_text(encoding="utf-8")
    require("def _verify_no_unaccepted_build_visible_paths(" not in source, "repair already present")

    helper = r'''

def _verify_no_unaccepted_build_visible_paths(
    root: Path,
    manifest: Sequence[AcceptedTrackedSource],
) -> None:
    """Reject build-visible checkout entries not admitted by Git or field-input custody.

    This audit runs only after vnode custody is armed. Tracked file bytes/modes are
    still authorized by the retained Git manifest; this check closes the distinct
    pre-armed-untracked window by requiring the physical tree shape to contain
    only tracked paths plus the already-established private/generated field roots.
    Any concurrent tree mutation remains observable by the armed parent-directory
    vnode descriptors and is rejected by the queued-event check before xcodebuild.
    """

    authority_root = _lexical_absolute(root)
    tracked_files: set[Path] = set()
    tracked_directories: set[Path] = {Path(".")}
    for item in manifest:
        admitted = _require_real_checkout_ancestry(
            item.path,
            authority_root,
            label="accepted tracked source physical-tree subject",
        )
        relative = admitted.relative_to(authority_root)
        tracked_files.add(relative)
        parent = relative.parent
        while parent != Path("."):
            tracked_directories.add(parent)
            parent = parent.parent

    # These are the same narrow non-Git inputs admitted by the field installer.
    # Their contents are independently authenticated/watched by the existing
    # private/generated custody contracts; this tree-shape audit must not redefine
    # those byte authorities.
    allowed_subtrees = {
        Path(".git"),
        Path("LocalSecrets"),
        Path("Pods"),
        Path("NembraCapture.xcworkspace"),
    }
    allowed_files = {Path("Podfile.lock")}

    for relative in allowed_subtrees:
        candidate = authority_root / relative
        try:
            metadata = candidate.lstat()
        except FileNotFoundError:
            continue
        except OSError as error:
            raise BuildGuardError(
                f"field build allowlisted subtree could not be inspected: {relative.as_posix()}"
            ) from error
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(
                f"field build allowlisted subtree is not one real directory: {relative.as_posix()}"
            )

    for relative in allowed_files:
        candidate = authority_root / relative
        try:
            metadata = candidate.lstat()
        except FileNotFoundError:
            continue
        except OSError as error:
            raise BuildGuardError(
                f"field build allowlisted file could not be inspected: {relative.as_posix()}"
            ) from error
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(
                f"field build allowlisted file is not one real regular file: {relative.as_posix()}"
            )

    for current_raw, directory_names, file_names in os.walk(
        authority_root,
        topdown=True,
        followlinks=False,
    ):
        current = Path(current_raw)
        current_relative = current.relative_to(authority_root)
        kept_directories: list[str] = []

        for name in directory_names:
            relative = Path(name) if current_relative == Path(".") else current_relative / name
            candidate = authority_root / relative
            try:
                metadata = candidate.lstat()
            except OSError as error:
                raise BuildGuardError(
                    f"build-visible directory changed during physical-tree admission: {relative.as_posix()}"
                ) from error
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise BuildGuardError(
                    f"build-visible directory is not one real admitted directory: {relative.as_posix()}"
                )
            if relative in allowed_subtrees:
                # Contents are separately authenticated/watched and intentionally
                # outside the accepted Git tree. Do not reinterpret their bytes.
                continue
            if relative not in tracked_directories:
                raise BuildGuardError(
                    f"unaccepted build-visible directory present before xcodebuild: {relative.as_posix()}"
                )
            kept_directories.append(name)

        directory_names[:] = kept_directories

        for name in file_names:
            relative = Path(name) if current_relative == Path(".") else current_relative / name
            candidate = authority_root / relative
            if relative in tracked_files:
                continue
            if relative in allowed_files:
                try:
                    metadata = candidate.lstat()
                except OSError as error:
                    raise BuildGuardError(
                        f"field build allowlisted file changed during physical-tree admission: {relative.as_posix()}"
                    ) from error
                if stat.S_ISREG(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
                    continue
            raise BuildGuardError(
                f"unaccepted build-visible file present before xcodebuild: {relative.as_posix()}"
            )
'''

    anchor = "\ndef _tracked_source_watch_paths(\n"
    require(source.count(anchor) == 1, "tracked-source watch anchor changed")
    source = source.replace(anchor, helper + anchor, 1)

    before = '''        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n        armed_snapshot = inputs.generation_snapshot()\n'''
    after = '''        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n            _verify_no_unaccepted_build_visible_paths(\n                inputs.accepted_source_root, tracked_manifest  # type: ignore[arg-type]\n            )\n        armed_snapshot = inputs.generation_snapshot()\n'''
    require(source.count(before) == 1, "guard admission anchor changed")
    source = source.replace(before, after, 1)
    GUARD.write_text(source, encoding="utf-8")


def main() -> None:
    require(git("merge-base", "--is-ancestor", PARENT_SHA, "HEAD") == "", "unexpected parent lineage")
    materialize_diagnostic()
    repair_guard()


if __name__ == "__main__":
    main()
