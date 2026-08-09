#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOUNDATION = ROOT / "scripts/ci/_es80_today_final_go_foundation_impl.py"
TRUSTED = ROOT / "scripts/ci/es80_today_trusted_capture_xcode_subject.py"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def replace_span(text: str, start_marker: str, end_marker: str, replacement: str, label: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"{label}: missing start marker")
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"{label}: missing end marker")
    return text[:start] + replacement + text[end:]


foundation = FOUNDATION.read_text(encoding="utf-8")
new_regular = '''def _regular(path: Path, label: str) -> bytes:\n    nofollow = getattr(os, "O_NOFOLLOW", None)\n    if nofollow is None:\n        raise FinalGoError(f"{label} custody requires O_NOFOLLOW support")\n    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)\n    fd = -1\n    try:\n        fd = os.open(path, flags)\n        before = os.fstat(fd)\n        if not stat.S_ISREG(before.st_mode) or before.st_size <= 0:\n            raise FinalGoError(f"{label} must be one non-empty regular non-symlink file: {path}")\n        chunks: list[bytes] = []\n        while True:\n            chunk = os.read(fd, 1024 * 1024)\n            if not chunk:\n                break\n            chunks.append(chunk)\n        after = os.fstat(fd)\n        identity_before = (\n            before.st_dev,\n            before.st_ino,\n            before.st_size,\n            before.st_mtime_ns,\n            before.st_ctime_ns,\n        )\n        identity_after = (\n            after.st_dev,\n            after.st_ino,\n            after.st_size,\n            after.st_mtime_ns,\n            after.st_ctime_ns,\n        )\n        raw = b"".join(chunks)\n        if identity_after != identity_before or len(raw) != before.st_size:\n            raise FinalGoError(f"{label} changed while reading")\n        return raw\n    except FinalGoError:\n        raise\n    except OSError as error:\n        raise FinalGoError(f"{label} is unavailable or unreadable: {path}") from error\n    finally:\n        if fd >= 0:\n            os.close(fd)\n\n\n'''
foundation = replace_span(
    foundation,
    "def _regular(path: Path, label: str) -> bytes:\n",
    "def _sha_file(path: Path, label: str) -> tuple[str, int]:\n",
    new_regular,
    "foundation descriptor-bound regular reader",
)
FOUNDATION.write_text(foundation, encoding="utf-8")

trusted = TRUSTED.read_text(encoding="utf-8")
trusted = replace_once(trusted, "import hashlib\nimport json\n", "import hashlib\nimport io\nimport json\nimport os\n", "trusted imports")
trusted = replace_once(trusted, "import re\nfrom typing import Any, Callable\nimport zipfile\n", "import re\nimport stat\nfrom typing import Any, Callable\nimport zipfile\n", "trusted stat import")

new_archive_reader = '''def _read_exact_archive(path: Path) -> bytes:\n    nofollow = getattr(os, "O_NOFOLLOW", None)\n    if nofollow is None:\n        raise TrustedCaptureXcodeError("trusted Xcode artifact custody requires O_NOFOLLOW support")\n    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)\n    fd = -1\n    try:\n        fd = os.open(path, flags)\n        before = os.fstat(fd)\n        _require(\n            stat.S_ISREG(before.st_mode) and before.st_size > 0,\n            "trusted Xcode artifact archive must be one non-empty regular non-symlink file",\n        )\n        chunks: list[bytes] = []\n        while True:\n            chunk = os.read(fd, 1024 * 1024)\n            if not chunk:\n                break\n            chunks.append(chunk)\n        after = os.fstat(fd)\n        raw = b"".join(chunks)\n        before_identity = (\n            before.st_dev,\n            before.st_ino,\n            before.st_size,\n            before.st_mtime_ns,\n            before.st_ctime_ns,\n        )\n        after_identity = (\n            after.st_dev,\n            after.st_ino,\n            after.st_size,\n            after.st_mtime_ns,\n            after.st_ctime_ns,\n        )\n        _require(\n            before_identity == after_identity and len(raw) == before.st_size,\n            "trusted Xcode artifact archive changed while reading",\n        )\n        return raw\n    except TrustedCaptureXcodeError:\n        raise\n    except OSError as error:\n        raise TrustedCaptureXcodeError(\n            "trusted Xcode artifact archive is unavailable or unreadable"\n        ) from error\n    finally:\n        if fd >= 0:\n            os.close(fd)\n\n\ndef _single_external_record(archive_raw: bytes, source: str) -> dict[str, Any]:\n'''
trusted = replace_span(
    trusted,
    "def _sha256_file(path: Path) -> str:\n",
    "    _require(archive_path.is_file(), \"trusted Xcode artifact archive is missing\")\n",
    new_archive_reader,
    "trusted archive snapshot reader",
)
trusted = replace_once(
    trusted,
    "    _require(archive_path.is_file(), \"trusted Xcode artifact archive is missing\")\n",
    "",
    "remove pathname archive precheck",
)
trusted = replace_once(
    trusted,
    '        with zipfile.ZipFile(archive_path, "r") as archive:\n',
    '        with zipfile.ZipFile(io.BytesIO(archive_raw), "r") as archive:\n',
    "inspect immutable archive bytes",
)
old_admission = '''    archive_sha = _sha256_file(artifact_archive_path)\n    server_digest = artifact.get("digest")\n    _require(\n        isinstance(server_digest, str)\n        and server_digest.lower() == f"sha256:{archive_sha}",\n        "trusted Xcode artifact archive digest mismatch",\n    )\n    _require(\n        artifact.get("size_in_bytes") == artifact_archive_path.stat().st_size,\n        "trusted Xcode artifact archive size mismatch",\n    )\n'''
new_admission = '''    archive_raw = _read_exact_archive(artifact_archive_path)\n    archive_sha = hashlib.sha256(archive_raw).hexdigest()\n    archive_size = len(archive_raw)\n    server_digest = artifact.get("digest")\n    _require(\n        isinstance(server_digest, str)\n        and server_digest.lower() == f"sha256:{archive_sha}",\n        "trusted Xcode artifact archive digest mismatch",\n    )\n    _require(\n        artifact.get("size_in_bytes") == archive_size,\n        "trusted Xcode artifact archive size mismatch",\n    )\n'''
trusted = replace_once(trusted, old_admission, new_admission, "server artifact snapshot admission")
trusted = replace_once(
    trusted,
    "    external_record = _single_external_record(artifact_archive_path, source)\n",
    "    external_record = _single_external_record(archive_raw, source)\n",
    "embedded record from snapshot",
)
trusted = replace_once(
    trusted,
    '        "artifactArchiveByteCount": artifact_archive_path.stat().st_size,\n',
    '        "artifactArchiveByteCount": archive_size,\n',
    "snapshot byte count",
)
TRUSTED.write_text(trusted, encoding="utf-8")
