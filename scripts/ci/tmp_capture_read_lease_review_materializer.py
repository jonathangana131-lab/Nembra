#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OWNED_WORKFLOW = ROOT / ".github/workflows/capture-read-lease-held-descriptor-materialize.yml"
HELPER = ROOT / "scripts/ci/capture_selected_xcode_build_orchestrator.py"
TEST = ROOT / "scripts/ci/tests/test_capture_private_read_lease_component_walk.py"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def apply_owned_transform() -> None:
    workflow = OWNED_WORKFLOW.read_text(encoding="utf-8")
    start_marker = "      - name: Materialize descriptor-custodied planning and grant\n        shell: bash\n        run: |\n"
    end_marker = "\n      - name: Run focused portable authority regressions\n"
    if workflow.count(start_marker) != 1 or workflow.count(end_marker) != 1:
        raise SystemExit("owned materializer transform markers are not unique")
    body = workflow.split(start_marker, 1)[1].split(end_marker, 1)[0]
    lines = body.splitlines()
    if any(line and not line.startswith("          ") for line in lines):
        raise SystemExit("owned materializer indentation changed")
    script = "\n".join(line[10:] if line else "" for line in lines) + "\n"
    completed = subprocess.run(
        ["/bin/bash"],
        input=script,
        text=True,
        cwd=ROOT,
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit(f"owned materializer transform failed: {completed.returncode}")


def harden_symlink_custody() -> None:
    source = HELPER.read_text(encoding="utf-8")

    source = replace_once(
        source,
        """    held: dict[Path, int] = {}
    selected: set[Path] = set()
    plan: list[dict[str, object]] = []
""",
        """    held: dict[Path, int] = {}
    selected: set[Path] = set()
    symlink_targets: dict[Path, str] = {}
    plan: list[dict[str, object]] = []
""",
        "held-plan state",
    )

    source = replace_once(
        source,
        """                if stat.S_ISLNK(metadata.st_mode):
                    # Symlinks receive no ACL authority themselves.  Preserve the
                    # existing internal-only policy; every real target that needs
                    # lease authority is independently descriptor-opened in this tree.
                    _validate_internal_symlink(candidate, subject)
                    continue
""",
        """                if stat.S_ISLNK(metadata.st_mode):
                    # Bind the exact link text to the same held directory generation.
                    # Path.resolve() would re-resolve mutable ancestry and could
                    # validate a different link generation than the plan observed.
                    try:
                        target = os.readlink(name, dir_fd=directory_descriptor)
                    except OSError as error:
                        raise SelectedXcodeBuildOrchestratorError(
                            f"private read-lease symlink could not be read from held ancestry: {candidate}"
                        ) from error
                    if not target or os.path.isabs(target):
                        raise SelectedXcodeBuildOrchestratorError(
                            f"private read-lease symlink escaped its admitted subject: {candidate}"
                        )
                    symlink_targets[candidate] = target
                    continue
""",
        "pathname symlink validation",
    )

    subject_marker = "        for raw_subject in subjects:\n"
    validator = """        def validate_held_symlinks(subject: Path) -> None:
            \"\"\"Resolve the finite symlink graph inside the exact held subject generation.\"\"\"
            relevant = {
                path: target
                for path, target in symlink_targets.items()
                if path == subject or subject in path.parents
            }
            for origin in relevant:
                try:
                    pending = list(origin.parent.relative_to(subject).parts)
                except ValueError as error:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease symlink escaped its admitted subject: {origin}"
                    ) from error
                pending.extend(Path(relevant[origin]).parts)
                resolved_parts: list[str] = []
                visited: set[Path] = set()
                while pending:
                    component = pending.pop(0)
                    if component in (\"\", \".\"):
                        continue
                    if component == \"..\":
                        if not resolved_parts:
                            raise SelectedXcodeBuildOrchestratorError(
                                f"private read-lease symlink escaped its admitted subject: {origin}"
                            )
                        resolved_parts.pop()
                        continue
                    candidate = subject.joinpath(*resolved_parts, component)
                    target = relevant.get(candidate)
                    if target is None:
                        resolved_parts.append(component)
                        continue
                    if candidate in visited:
                        raise SelectedXcodeBuildOrchestratorError(
                            f"private read-lease symlink cycle is not admissible: {origin}"
                        )
                    visited.add(candidate)
                    if not target or os.path.isabs(target):
                        raise SelectedXcodeBuildOrchestratorError(
                            f"private read-lease symlink escaped its admitted subject: {origin}"
                        )
                    pending = list(Path(target).parts) + pending
                terminal = subject.joinpath(*resolved_parts)
                descriptor = held.get(terminal)
                if descriptor is None:
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease symlink is broken or leaves the held subject: {origin}"
                    )
                mode = os.fstat(descriptor).st_mode
                if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
                    raise SelectedXcodeBuildOrchestratorError(
                        f"private read-lease symlink target has unsupported type: {origin}"
                    )

"""
    source = replace_once(source, subject_marker, validator + subject_marker, "subject loop")

    source = replace_once(
        source,
        """            if stat.S_ISDIR(mode):
                walk_directory(subject, cursor_descriptor, subject)
            elif not stat.S_ISREG(mode):
""",
        """            if stat.S_ISDIR(mode):
                walk_directory(subject, cursor_descriptor, subject)
                validate_held_symlinks(subject)
            elif not stat.S_ISREG(mode):
""",
        "held symlink validation call",
    )
    HELPER.write_text(source, encoding="utf-8")


def add_regression() -> None:
    tests = TEST.read_text(encoding="utf-8")
    tests = replace_once(
        tests,
        "import unittest\n",
        "import unittest\nfrom unittest import mock\n",
        "unittest import",
    )
    marker = "    def test_real_directory_and_regular_file_path_opener_still_work(self) -> None:\n"
    regression = """    def test_symlink_validation_cannot_switch_to_a_different_path_generation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix=\"nembra-held-symlink-generation-\") as raw:
            outer = Path(raw)
            repo = outer / \"repo\"
            subject = repo / \"LocalSecrets/TuyaSDK/Build\"
            subject.mkdir(parents=True)
            outside = repo / \"LocalSecrets/outside.bin\"
            outside.write_bytes(b\"outside\")
            (subject / \"escape\").symlink_to(\"../../outside.bin\")
            original_stat = helper.os.stat
            swapped = False

            def stat_then_swap(path, *args, **kwargs):
                nonlocal swapped
                metadata = original_stat(path, *args, **kwargs)
                if path == \"escape\" and kwargs.get(\"dir_fd\") is not None and not swapped:
                    swapped = True
                    detached = subject.with_name(\"Build.held\")
                    subject.rename(detached)
                    subject.mkdir()
                    (subject / \"inside.bin\").write_bytes(b\"inside\")
                    (subject / \"escape\").symlink_to(\"inside.bin\")
                return metadata

            with mock.patch.object(helper.os, \"stat\", side_effect=stat_then_swap):
                with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                    helper._lease_descriptor_plan((subject,), repo)
            self.assertTrue(swapped)

        source = inspect.getsource(helper._lease_descriptor_plan)
        self.assertIn(\"os.readlink(name, dir_fd=directory_descriptor)\", source)
        self.assertNotIn(\"_validate_internal_symlink(candidate, subject)\", source)

"""
    tests = replace_once(tests, marker, regression + marker, "regression insertion")
    TEST.write_text(tests, encoding="utf-8")


def main() -> None:
    apply_owned_transform()
    harden_symlink_custody()
    add_regression()


if __name__ == "__main__":
    main()
