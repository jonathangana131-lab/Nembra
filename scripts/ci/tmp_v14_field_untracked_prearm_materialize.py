#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

GUARD = Path("Scripts/capture_tuya_private_input_build_guard.py")
source = GUARD.read_text(encoding="utf-8")

insert_anchor = "\n\ndef _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:\n"
if source.count(insert_anchor) != 1:
    raise SystemExit("tracked-source helper insertion anchor drifted")

helper = r'''


def _accepted_source_field_allowlist(inputs: object, repository_root: Path) -> tuple[set[str], set[str]]:
    """Return only the separately authenticated field-input roots admitted beside Git source."""

    authority_root = _lexical_absolute(repository_root)
    allowed_directories: set[str] = set()
    allowed_files: set[str] = set()

    def relative_if_inside(value: object) -> PurePosixPath | None:
        if value is None:
            return None
        candidate = _lexical_absolute(Path(value))
        try:
            relative = candidate.relative_to(authority_root)
        except ValueError:
            return None
        if not relative.parts:
            return None
        return PurePosixPath(*relative.parts)

    generated_pods = relative_if_inside(getattr(inputs, "generated_pods", None))
    if generated_pods is not None and generated_pods.as_posix() == "Pods":
        allowed_directories.add("Pods")

    generated_workspace = relative_if_inside(getattr(inputs, "generated_workspace", None))
    if generated_workspace is not None and generated_workspace.as_posix() == "NembraCapture.xcworkspace":
        allowed_directories.add("NembraCapture.xcworkspace")

    for attribute in (
        "security_podspec",
        "security_build",
        "identity_podspec",
        "identity_sources",
    ):
        private_subject = relative_if_inside(getattr(inputs, attribute, None))
        if private_subject is not None and private_subject.parts[0] == "LocalSecrets":
            allowed_directories.add("LocalSecrets")

    lockfile = relative_if_inside(getattr(inputs, "lockfile", None))
    if lockfile is not None and lockfile.as_posix() == "Podfile.lock":
        allowed_files.add("Podfile.lock")

    return allowed_directories, allowed_files


def _verify_accepted_source_physical_tree(
    inputs: object,
    manifest: Sequence[AcceptedTrackedSource],
    repository_root: Path,
) -> None:
    """Reject pre-armed unexpected checkout paths while vnode custody is already active.

    The outer field installer performs the same ignore-independent raw-tree policy before
    entering this process. This in-guard replay is intentionally later: all accepted
    tracked directory ancestry is already under vnode custody, so an unexpected source
    that existed before watcher registration is caught by inventory while any concurrent
    create/remove/rename is caught by the queued directory event before xcodebuild can be
    accepted.
    """

    authority_root = _lexical_absolute(repository_root)
    tracked_files: set[str] = set()
    tracked_directories: set[str] = set()
    for item in manifest:
        try:
            relative_path = item.path.relative_to(authority_root)
        except ValueError as error:
            raise BuildGuardError("accepted tracked source escaped raw-tree authority") from error
        relative = PurePosixPath(*relative_path.parts)
        if not relative.parts:
            raise BuildGuardError("accepted tracked source has an empty raw-tree path")
        relative_text = relative.as_posix()
        tracked_files.add(relative_text)
        for depth in range(1, len(relative.parts)):
            tracked_directories.add(PurePosixPath(*relative.parts[:depth]).as_posix())

    allowed_directories, allowed_files = _accepted_source_field_allowlist(inputs, authority_root)
    for relative in sorted(allowed_directories):
        candidate = authority_root / relative
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise BuildGuardError(
                f"accepted field-input directory disappeared during raw-tree admission: {relative}"
            ) from error
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(
                f"accepted field-input allowlist root is not one real directory: {relative}"
            )

    for relative in sorted(allowed_files):
        candidate = authority_root / relative
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise BuildGuardError(
                f"accepted field-input file disappeared during raw-tree admission: {relative}"
            ) from error
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(
                f"accepted field-input allowlist file is not one real regular file: {relative}"
            )

    seen_tracked_files: set[str] = set()
    seen_tracked_directories: set[str] = set()
    try:
        walk = os.walk(authority_root, topdown=True, followlinks=False)
        for current_raw, directories, files in walk:
            current = Path(current_raw)
            current_metadata = current.lstat()
            if not stat.S_ISDIR(current_metadata.st_mode) or stat.S_ISLNK(current_metadata.st_mode):
                raise BuildGuardError(
                    f"accepted source directory changed type during raw-tree admission: {current}"
                )
            current_relative_path = current.relative_to(authority_root)
            current_relative = PurePosixPath(*current_relative_path.parts)
            if current_relative.parts and current_relative.parts[0] in allowed_directories:
                directories[:] = []
                continue

            for name in list(directories):
                if not current_relative.parts and name == ".git":
                    directories.remove(name)
                    continue
                if not current_relative.parts and name in allowed_directories:
                    directories.remove(name)
                    continue
                candidate = current / name
                relative = candidate.relative_to(authority_root).as_posix()
                metadata = candidate.lstat()
                if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                    directories.remove(name)
                    raise BuildGuardError(
                        f"unexpected/non-directory accepted-source path before xcodebuild: {relative}"
                    )
                if relative not in tracked_directories:
                    directories.remove(name)
                    raise BuildGuardError(
                        f"untracked accepted-source path outside field-input allowlist before xcodebuild: {relative}"
                    )
                seen_tracked_directories.add(relative)

            for name in files:
                candidate = current / name
                relative = candidate.relative_to(authority_root).as_posix()
                metadata = candidate.lstat()
                if relative in tracked_files:
                    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                        raise BuildGuardError(
                            f"accepted tracked source changed type during raw-tree admission: {relative}"
                        )
                    seen_tracked_files.add(relative)
                    continue
                if relative in allowed_files:
                    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                        raise BuildGuardError(
                            f"accepted field-input file changed type during raw-tree admission: {relative}"
                        )
                    continue
                raise BuildGuardError(
                    f"untracked accepted-source path outside field-input allowlist before xcodebuild: {relative}"
                )
    except OSError as error:
        raise BuildGuardError("accepted source raw physical-tree admission could not complete") from error

    if seen_tracked_files != tracked_files:
        missing = sorted(tracked_files - seen_tracked_files)
        raise BuildGuardError(
            "accepted source raw-tree admission did not observe every tracked file: "
            + ", ".join(missing[:8])
        )
    if seen_tracked_directories != tracked_directories:
        missing = sorted(tracked_directories - seen_tracked_directories)
        raise BuildGuardError(
            "accepted source raw-tree admission did not observe every tracked directory: "
            + ", ".join(missing[:8])
        )
'''
source = source.replace(insert_anchor, helper + insert_anchor, 1)

armed_anchor = """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n        armed_snapshot = inputs.generation_snapshot()\n"""
if source.count(armed_anchor) != 1:
    raise SystemExit("armed tracked-manifest verification anchor drifted")
source = source.replace(
    armed_anchor,
    """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n            _verify_accepted_source_physical_tree(\n                inputs, tracked_manifest, inputs.accepted_source_root  # type: ignore[arg-type]\n            )\n        armed_snapshot = inputs.generation_snapshot()\n""",
    1,
)

final_anchor = """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n        final_snapshot = inputs.generation_snapshot()\n"""
if source.count(final_anchor) != 1:
    raise SystemExit("final tracked-manifest verification anchor drifted")
source = source.replace(
    final_anchor,
    """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n            _verify_accepted_source_physical_tree(\n                inputs, tracked_manifest, inputs.accepted_source_root  # type: ignore[arg-type]\n            )\n        final_snapshot = inputs.generation_snapshot()\n""",
    1,
)

GUARD.write_text(source, encoding="utf-8")
