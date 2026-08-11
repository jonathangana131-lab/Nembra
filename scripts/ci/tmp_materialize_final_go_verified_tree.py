#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/es80_authenticated_stationary_private_review_final_go.py")
source = path.read_text(encoding="utf-8")
start_marker = "def _tree_entries(root: Path, source: str) -> dict[str, tuple[bytes, str]]:\n"
end_marker = "def _stable_stat(metadata: os.stat_result) -> tuple[int, ...]:\n"
start = source.index(start_marker)
end = source.index(end_marker, start)

replacement = r'''def _git_object_oid(payload: bytes, object_type: str, accepted_oid: str) -> str:
    if object_type not in {"commit", "tree", "blob"}:
        raise RuntimeError("candidate Git object type is outside the verified allowlist")
    header = object_type.encode("ascii") + b" " + str(len(payload)).encode("ascii") + b"\0"
    if len(accepted_oid) == 40:
        return hashlib.sha1(header + payload).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(header + payload).hexdigest()
    raise RuntimeError("candidate accepted Git object has unsupported width")


def _verified_git_object_payload(root: Path, object_type: str, oid: str) -> bytes:
    oid = oid.lower()
    if not OID.fullmatch(oid):
        raise RuntimeError("candidate accepted Git object has invalid identity")
    payload = _object_git_bytes(root, "cat-file", object_type, oid)
    actual = _git_object_oid(payload, object_type, oid)
    if actual != oid:
        raise RuntimeError(
            f"candidate {object_type} bytes do not match the accepted Git object identity"
        )
    return payload


def _verified_commit_tree_oid(root: Path, source: str) -> str:
    source = source.lower()
    if not OID.fullmatch(source):
        raise RuntimeError("candidate source is not a canonical Git object ID")
    commit = _verified_git_object_payload(root, "commit", source)
    header = commit.split(b"\n\n", 1)[0]
    tree_lines = [line for line in header.splitlines() if line.startswith(b"tree ")]
    if len(tree_lines) != 1:
        raise RuntimeError("candidate accepted commit does not contain one canonical tree identity")
    try:
        tree_oid = tree_lines[0][5:].decode("ascii").lower()
    except UnicodeDecodeError as error:
        raise RuntimeError("candidate accepted commit tree identity is not ASCII") from error
    if not OID.fullmatch(tree_oid) or len(tree_oid) != len(source):
        raise RuntimeError("candidate accepted commit tree identity is invalid")
    return tree_oid


def _tree_entries(root: Path, source: str) -> dict[str, tuple[bytes, str]]:
    """Derive tracked paths only from independently verified commit/tree bytes.

    Ordinary ``git ls-tree`` output is not authority here: a same-UID actor can
    corrupt a local pack index so an accepted OID string resolves to unrelated
    packed bytes. Each returned commit/tree payload is therefore re-hashed with
    canonical Git object framing before any mapping inside it is trusted.
    """
    root_tree = _verified_commit_tree_oid(root, source)
    entries: dict[str, tuple[bytes, str]] = {}
    active_trees: set[str] = set()

    def walk(tree_oid: str, prefix: tuple[str, ...]) -> None:
        if tree_oid in active_trees:
            raise RuntimeError("candidate accepted tree contains recursive object ancestry")
        active_trees.add(tree_oid)
        try:
            raw = _verified_git_object_payload(root, "tree", tree_oid)
            oid_width = len(tree_oid) // 2
            offset = 0
            while offset < len(raw):
                space = raw.find(b" ", offset)
                if space <= offset:
                    raise RuntimeError("candidate accepted binary tree mode is malformed")
                nul = raw.find(b"\0", space + 1)
                if nul <= space + 1:
                    raise RuntimeError("candidate accepted binary tree name is malformed")
                object_end = nul + 1 + oid_width
                if object_end > len(raw):
                    raise RuntimeError("candidate accepted binary tree object identity is truncated")

                mode = raw[offset:space]
                name_raw = raw[space + 1 : nul]
                oid = raw[nul + 1 : object_end].hex()
                offset = object_end

                if (
                    not name_raw
                    or b"/" in name_raw
                    or name_raw in {b".", b".."}
                    or b"\0" in name_raw
                    or not OID.fullmatch(oid)
                    or len(oid) != len(tree_oid)
                ):
                    raise RuntimeError("candidate accepted binary tree entry is unsafe")
                name = os.fsdecode(name_raw)
                relative_parts = (*prefix, name)
                relative = PurePosixPath(*relative_parts).as_posix()
                if (
                    not relative_parts
                    or relative.startswith("/")
                    or any(part in {"", ".", ".."} for part in PurePosixPath(relative).parts)
                ):
                    raise RuntimeError("candidate accepted tree contains unsafe tracked path")

                if mode == b"40000":
                    walk(oid, relative_parts)
                    continue
                if mode not in {b"100644", b"100755", b"120000"}:
                    raise RuntimeError("candidate accepted tree contains unsupported tracked object")
                if relative in entries:
                    raise RuntimeError("candidate accepted tree contains duplicate tracked path")
                entries[relative] = (mode, oid)

            if offset != len(raw):
                raise RuntimeError("candidate accepted binary tree has trailing malformed bytes")
        finally:
            active_trees.remove(tree_oid)

    walk(root_tree, ())
    if not entries:
        raise RuntimeError("candidate accepted tree contains no tracked blobs")
    return entries


'''

path.write_text(source[:start] + replacement + source[end:], encoding="utf-8")
print("materialized independently verified Final-GO commit/tree authority")
