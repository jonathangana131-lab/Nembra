#!/usr/bin/env python3
from pathlib import Path
import subprocess
import textwrap

BRANCH = "repair/v14-final-go-signed-device-descriptor-custody-sol"
BASE = "7557c5502c25cbcd0c44984eb19e8c62145d8435"
SELF = Path(".github/materializers/v14_signed_device_descriptor_custody.py")
WORKFLOW = Path(".github/workflows/tmp-v14-signed-device-descriptor-custody.yml")
SIGNED = Path("scripts/ci/es80_authenticated_stationary_signed_artifact.py")
TESTS = Path("scripts/ci/tests/test_es80_authenticated_stationary_signed_artifact.py")


def run(*args: str) -> str:
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise SystemExit(f"command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}")
    return result.stdout.strip()


head = run("git", "rev-parse", "HEAD")
run("git", "merge-base", "--is-ancestor", BASE, head)
initial = set(filter(None, run("git", "diff", "--name-only", BASE, head).splitlines()))
if initial != {str(SELF), str(WORKFLOW)}:
    raise SystemExit(f"unexpected pre-repair diff: {sorted(initial)}")

old_reader = textwrap.dedent('''\
def _read_intended_device(path: Path, repository_root: Path) -> str:
    expanded = path.expanduser()
    try:
        resolved = expanded.resolve(strict=True)
    except OSError as error:
        raise SignedArtifactError(
            "private intended-device identifier cannot be resolved"
        ) from error
    repository = repository_root.resolve(strict=True)
    try:
        resolved.relative_to(repository)
    except ValueError:
        pass
    else:
        raise SignedArtifactError(
            "private intended-device identifier must remain outside repository"
        )
    metadata = expanded.lstat()
    if (
        expanded.is_symlink()
        or not stat.S_ISREG(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != 0o600
        or metadata.st_uid != os.getuid()
        or metadata.st_nlink != 1
    ):
        raise SignedArtifactError("private intended-device identifier custody is invalid")
    raw = expanded.read_bytes()
    try:
        value = raw.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise SignedArtifactError(
            "private intended-device identifier is not UTF-8"
        ) from error
    if not value or len(value) > 160 or any(character.isspace() for character in value):
        raise SignedArtifactError("private intended-device identifier is malformed")
    return value
''')

new_reader = textwrap.dedent('''\
def _private_file_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _repository_directory_identity(repository_root: Path) -> tuple[int, int]:
    try:
        repository = repository_root.expanduser().resolve(strict=True)
        metadata = os.stat(repository)
    except OSError as error:
        raise SignedArtifactError("candidate repository privacy boundary is unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode):
        raise SignedArtifactError("candidate repository privacy boundary is not a directory")
    return metadata.st_dev, metadata.st_ino


def _open_private_identifier_without_symlink_components(path: Path, repository_root: Path) -> int:
    if (
        not hasattr(os, "O_NOFOLLOW")
        or not hasattr(os, "O_DIRECTORY")
        or os.open not in os.supports_dir_fd
    ):
        raise SignedArtifactError("platform cannot enforce component-wise private-device custody")

    expanded = path.expanduser()
    if (
        not expanded.is_absolute()
        or expanded.anchor != os.sep
        or not expanded.parts[1:]
        or any(component in ("", ".", "..") for component in expanded.parts[1:])
    ):
        raise SignedArtifactError("private intended-device path must be canonical absolute")

    repository_identity = _repository_directory_identity(repository_root)
    close_on_exec = getattr(os, "O_CLOEXEC", 0)
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | close_on_exec
    file_flags = os.O_RDONLY | os.O_NOFOLLOW | close_on_exec

    try:
        parent_descriptor = os.open(os.sep, directory_flags)
    except OSError as error:
        raise SignedArtifactError("private intended-device path root is unavailable") from error

    try:
        root_metadata = os.fstat(parent_descriptor)
        if (root_metadata.st_dev, root_metadata.st_ino) == repository_identity:
            raise SignedArtifactError("private intended-device identifier must remain outside repository")

        for component in expanded.parts[1:-1]:
            try:
                next_descriptor = os.open(component, directory_flags, dir_fd=parent_descriptor)
            except OSError as error:
                raise SignedArtifactError(
                    "private intended-device path contains an unsafe directory component"
                ) from error
            next_metadata = os.fstat(next_descriptor)
            if (next_metadata.st_dev, next_metadata.st_ino) == repository_identity:
                os.close(next_descriptor)
                raise SignedArtifactError(
                    "private intended-device identifier must remain outside repository"
                )
            os.close(parent_descriptor)
            parent_descriptor = next_descriptor

        try:
            return os.open(expanded.parts[-1], file_flags, dir_fd=parent_descriptor)
        except OSError as error:
            raise SignedArtifactError(
                "private intended-device identifier is not a readable non-symlink file"
            ) from error
    finally:
        os.close(parent_descriptor)


def _read_intended_device(path: Path, repository_root: Path) -> str:
    descriptor = _open_private_identifier_without_symlink_components(path, repository_root)
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or stat.S_IMODE(before.st_mode) != 0o600
            or before.st_uid != os.getuid()
            or before.st_nlink != 1
            or before.st_size < 1
            or before.st_size > 160
        ):
            raise SignedArtifactError("private intended-device identifier custody is invalid")

        chunks: list[bytes] = []
        remaining = 161
        while remaining > 0:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
        if len(raw) != before.st_size or _private_file_identity(after) != _private_file_identity(before):
            raise SignedArtifactError("private intended-device identifier changed while reading")
    finally:
        os.close(descriptor)

    try:
        value = raw.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise SignedArtifactError(
            "private intended-device identifier is not UTF-8"
        ) from error
    if not value or len(value) > 160 or any(character.isspace() for character in value):
        raise SignedArtifactError("private intended-device identifier is malformed")
    return value
''')

text = SIGNED.read_text()
if text.count(old_reader) != 1:
    raise SystemExit("signed-artifact private reader source no longer matches reviewed parent")
SIGNED.write_text(text.replace(old_reader, new_reader, 1))

test_text = TESTS.read_text()
marker = textwrap.dedent('''\
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(inside, self.repo)

    def test_pre_and_post_retained_tree_mismatch_is_rejected(self) -> None:
''')
replacement = textwrap.dedent('''\
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(inside, self.repo)

        private_parent = self.root / "private-parent"
        private_parent.mkdir()
        private_device = private_parent / "device.udid"
        private_device.write_text(DEVICE, encoding="utf-8")
        os.chmod(private_device, 0o600)
        alias = self.root / "private-alias"
        alias.symlink_to(private_parent, target_is_directory=True)
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(alias / "device.udid", self.repo)

        hardlink = self.root / "device-hardlink"
        os.link(self.device, hardlink)
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(self.device, self.repo)
        hardlink.unlink()

    def test_private_device_read_stays_bound_to_opened_ancestor_descriptors(self) -> None:
        admitted = self.root / "admitted"
        admitted.mkdir()
        admitted_device = admitted / "device.udid"
        admitted_device.write_text(DEVICE, encoding="utf-8")
        os.chmod(admitted_device, 0o600)

        replacement = self.root / "replacement"
        replacement.mkdir()
        replacement_device = replacement / "device.udid"
        replacement_device.write_text("00008101-0099999999999999", encoding="utf-8")
        os.chmod(replacement_device, 0o600)
        moved = self.root / "admitted-original"
        original_open = os.open
        swapped = False

        def retarget_before_final_open(path: object, flags: int, *args: object, **kwargs: object) -> int:
            nonlocal swapped
            if path == "device.udid" and kwargs.get("dir_fd") is not None and not swapped:
                os.rename(admitted, moved)
                os.rename(replacement, admitted)
                swapped = True
            return original_open(path, flags, *args, **kwargs)

        with mock.patch.object(signed.os, "open", side_effect=retarget_before_final_open):
            value = signed._read_intended_device(admitted_device, self.repo)
        self.assertTrue(swapped)
        self.assertEqual(value, DEVICE)
        self.assertEqual((admitted / "device.udid").read_text(encoding="utf-8"), "00008101-0099999999999999")

    def test_pre_and_post_retained_tree_mismatch_is_rejected(self) -> None:
''')
if test_text.count(marker) != 1:
    raise SystemExit("signed-artifact custody-test insertion marker no longer matches reviewed parent")
TESTS.write_text(test_text.replace(marker, replacement, 1))

run("python3", "-m", "py_compile", str(SIGNED), str(TESTS))
run("python3", str(TESTS))
run("git", "diff", "--check")

SELF.unlink()
WORKFLOW.unlink()
expected = {str(SELF), str(WORKFLOW), str(SIGNED), str(TESTS)}
actual = {line[3:] for line in run("git", "status", "--porcelain=v1").splitlines() if line}
if actual != expected:
    raise SystemExit(f"unexpected materialized path set: {sorted(actual)}")

run("git", "config", "user.name", "github-actions[bot]")
run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
run("git", "add", "-A")
run("git", "commit", "-m", "fix(capture): bind signed-artifact device reads to descriptors")
run("git", "fetch", "origin", BRANCH)
if run("git", "rev-parse", "FETCH_HEAD") != head:
    raise SystemExit("repair branch moved during materialization")
run("git", "push", "origin", f"HEAD:{BRANCH}")
