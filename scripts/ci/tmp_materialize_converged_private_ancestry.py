#!/usr/bin/env python3
from pathlib import Path

path=Path('Scripts/capture_tuya_private_input_build_guard.py')
text=path.read_text()
anchor='def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:\n'
helpers='''def _lexical_absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path.expanduser())))


def _require_real_checkout_ancestry(path: Path, root: Path, *, label: str) -> Path:
    candidate = _lexical_absolute(path)
    authority_root = _lexical_absolute(root)
    try:
        relative = candidate.relative_to(authority_root)
    except ValueError as error:
        raise BuildGuardError(f"{label} must remain inside the accepted checkout root") from error
    try:
        root_metadata = authority_root.lstat()
    except OSError as error:
        raise BuildGuardError("accepted checkout root disappeared before build-window custody") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise BuildGuardError("accepted checkout root must be one real directory")
    current = authority_root
    for component in relative.parts:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise BuildGuardError(f"{label} path ancestry disappeared before build-window custody: {current}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(f"{label} path ancestry must not contain symlinks: {current}")
    return candidate


def _add_private_ancestor_watch_paths(paths: set[Path], path: Path, root: Path) -> None:
    current = path.parent
    while current != root:
        if root not in current.parents:
            raise BuildGuardError("private build-input ancestry escaped accepted checkout root")
        paths.add(current)
        current = current.parent


'''
if anchor not in text or '_require_real_checkout_ancestry' in text: raise SystemExit('helper anchor missing/already transformed')
text=text.replace(anchor,helpers+anchor,1)
old='''    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
    for root in (
'''
new='''    authority_root = inputs.lockfile.parent
    private_paths = (
        (inputs.security_podspec, "private security podspec"),
        (inputs.security_build, "private security build tree"),
        (inputs.identity_podspec, "private identity podspec"),
        (inputs.identity_sources, "private identity source tree"),
    )
    for private_path, label in private_paths:
        _require_real_checkout_ancestry(private_path, authority_root, label=label)

    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
    for private_path, _ in private_paths:
        _add_private_ancestor_watch_paths(paths, private_path, authority_root)
    for root in (
'''
if old not in text: raise SystemExit('watch anchor missing')
text=text.replace(old,new,1)
old='''    return (
        PrivateInputs(
            lockfile=args.lockfile.resolve(),
            security_podspec=args.security_podspec.resolve(),
            security_build=args.security_build.resolve(),
            identity_podspec=args.identity_podspec.resolve(),
            identity_sources=args.identity_sources.resolve(),
            accepted_generated_subject_sha256=os.environ.get(
                "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
            ),
        ),
        command,
    )
'''
new='''    lockfile = _lexical_absolute(args.lockfile)
    authority_root = lockfile.parent
    lockfile = _require_real_checkout_ancestry(lockfile, authority_root, label="dependency lock")
    security_podspec = _require_real_checkout_ancestry(args.security_podspec, authority_root, label="private security podspec")
    security_build = _require_real_checkout_ancestry(args.security_build, authority_root, label="private security build tree")
    identity_podspec = _require_real_checkout_ancestry(args.identity_podspec, authority_root, label="private identity podspec")
    identity_sources = _require_real_checkout_ancestry(args.identity_sources, authority_root, label="private identity source tree")
    return (
        PrivateInputs(
            lockfile=lockfile,
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
            accepted_generated_subject_sha256=os.environ.get(
                "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"
            ),
        ),
        command,
    )
'''
if old not in text: raise SystemExit('parse anchor missing')
path.write_text(text.replace(old,new,1))
