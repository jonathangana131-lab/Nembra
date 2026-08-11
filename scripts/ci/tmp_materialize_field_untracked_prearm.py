#!/usr/bin/env python3
from pathlib import Path

path = Path("Scripts/capture_tuya_private_input_build_guard.py")
source = path.read_text(encoding="utf-8")

function_anchor = "\n\ndef _tracked_source_watch_paths(\n"
if source.count(function_anchor) != 1:
    raise SystemExit("tracked-source watch anchor drifted")

function = '''


def _verify_accepted_source_inventory(
    manifest: Sequence[AcceptedTrackedSource],
    repository_root: Path,
    inputs: object,
) -> None:
    """Reject build-visible checkout additions after vnode custody is armed.

    The field installer performs an independent raw accepted-tree audit before it
    enters this guard. A file created after that audit but before directory vnode
    descriptors are registered has no historical kqueue event. Re-scan the raw
    physical checkout only after those descriptors are armed, using the retained
    accepted tracked manifest plus the same narrow field-input roots. Any race
    during this scan is then covered by the already-armed directory watchers and
    is drained before xcodebuild admission.
    """

    authority_root = _lexical_absolute(repository_root)
    tracked_files: set[str] = set()
    tracked_directories: set[str] = set()
    for item in manifest:
        try:
            relative = item.path.relative_to(authority_root)
        except ValueError as error:
            raise BuildGuardError("accepted tracked source inventory escaped the checkout root") from error
        pure = PurePosixPath(relative.as_posix())
        if not pure.parts or any(part in {"", ".", ".."} for part in pure.parts):
            raise BuildGuardError("accepted tracked source inventory contains an unsafe path")
        tracked_files.add(pure.as_posix())
        for depth in range(1, len(pure.parts)):
            tracked_directories.add(PurePosixPath(*pure.parts[:depth]).as_posix())

    allowed_directory_roots: set[str] = set()
    for attribute in (
        "security_build",
        "identity_sources",
        "generated_pods",
        "generated_workspace",
    ):
        value = getattr(inputs, attribute, None)
        if value is None:
            continue
        candidate = _lexical_absolute(Path(value))
        try:
            relative = candidate.relative_to(authority_root)
        except ValueError as error:
            raise BuildGuardError("field-input allowlist escaped the accepted checkout root") from error
        if not relative.parts:
            raise BuildGuardError("field-input allowlist cannot admit the whole accepted checkout")
        allowed_directory_roots.add(relative.parts[0])

    allowed_files: set[str] = set()
    lockfile = getattr(inputs, "lockfile", None)
    if lockfile is not None:
        candidate = _lexical_absolute(Path(lockfile))
        try:
            relative = candidate.relative_to(authority_root)
        except ValueError as error:
            raise BuildGuardError("field-input lockfile escaped the accepted checkout root") from error
        if not relative.parts:
            raise BuildGuardError("field-input lockfile path is invalid")
        allowed_files.add(relative.as_posix())

    def walk_error(error: OSError) -> None:
        raise BuildGuardError("accepted source inventory changed during post-arm raw audit") from error

    for current_raw, directories, files in os.walk(
        authority_root,
        topdown=True,
        followlinks=False,
        onerror=walk_error,
    ):
        current = Path(current_raw)
        current_relative = current.relative_to(authority_root)
        if current_relative.parts and current_relative.parts[0] in allowed_directory_roots:
            directories[:] = []
            continue
        if not current_relative.parts:
            directories[:] = [
                name
                for name in directories
                if name != ".git" and name not in allowed_directory_roots
            ]

        for name in list(directories):
            candidate = current / name
            relative = candidate.relative_to(authority_root).as_posix()
            try:
                metadata = candidate.lstat()
            except OSError as error:
                raise BuildGuardError(
                    f"accepted source directory changed during post-arm raw audit: {relative}"
                ) from error
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                directories.remove(name)
                raise BuildGuardError(
                    f"untracked accepted-source path outside field-input allowlist: {relative}"
                )
            if relative not in tracked_directories:
                directories.remove(name)
                raise BuildGuardError(
                    f"untracked accepted-source path outside field-input allowlist: {relative}"
                )

        for name in files:
            candidate = current / name
            relative = candidate.relative_to(authority_root).as_posix()
            if relative in tracked_files or relative in allowed_files:
                continue
            raise BuildGuardError(
                f"untracked accepted-source path outside field-input allowlist: {relative}"
            )
'''
source = source.replace(function_anchor, function + function_anchor, 1)

admission_anchor = """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n        armed_snapshot = inputs.generation_snapshot()\n"""
admission_replacement = """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n            _verify_accepted_source_inventory(\n                tracked_manifest,\n                inputs.accepted_source_root,  # type: ignore[arg-type]\n                inputs,\n            )\n        armed_snapshot = inputs.generation_snapshot()\n"""
if source.count(admission_anchor) != 1:
    raise SystemExit("post-arm admission anchor drifted")
source = source.replace(admission_anchor, admission_replacement, 1)

final_anchor = """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n        final_snapshot = inputs.generation_snapshot()\n"""
final_replacement = """        if tracked_manifest:\n            _verify_tracked_source_manifest(tracked_manifest)\n            _verify_accepted_source_inventory(\n                tracked_manifest,\n                inputs.accepted_source_root,  # type: ignore[arg-type]\n                inputs,\n            )\n        final_snapshot = inputs.generation_snapshot()\n"""
if source.count(final_anchor) != 1:
    raise SystemExit("final source verification anchor drifted")
source = source.replace(final_anchor, final_replacement, 1)

path.write_text(source, encoding="utf-8")
