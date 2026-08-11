#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

GUARD = Path("Scripts/capture_tuya_private_input_build_guard.py")
TEST = Path("scripts/ci/tests/test_capture_field_untracked_prearm_injection_red_team.py")

source = GUARD.read_text(encoding="utf-8")
old_signature = "def _accepted_source_field_allowlist(inputs: object, repository_root: Path) -> tuple[set[str], set[str]]:"
new_signature = "def _accepted_source_field_allowlist(inputs: object, repository_root: Path) -> tuple[set[str], set[str], set[str]]:"
if source.count(old_signature) != 1:
    raise SystemExit("allowlist signature anchor drifted")
source = source.replace(old_signature, new_signature, 1)

old_private = '''    for attribute in (\n        "security_podspec",\n        "security_build",\n        "identity_podspec",\n        "identity_sources",\n    ):\n        private_subject = relative_if_inside(getattr(inputs, attribute, None))\n        if private_subject is not None and private_subject.parts[0] == "LocalSecrets":\n            allowed_directories.add("LocalSecrets")\n\n    lockfile = relative_if_inside(getattr(inputs, "lockfile", None))\n'''
new_private = '''    private_roots: set[str] = set()\n    for attribute in (\n        "security_podspec",\n        "security_build",\n        "identity_podspec",\n        "identity_sources",\n    ):\n        private_subject = relative_if_inside(getattr(inputs, attribute, None))\n        if (\n            private_subject is not None\n            and len(private_subject.parts) >= 2\n            and private_subject.parts[0] == "LocalSecrets"\n        ):\n            private_roots.add(PurePosixPath(*private_subject.parts[:2]).as_posix())\n    allowed_directories.update(private_roots)\n\n    allowed_directory_ancestors: set[str] = set()\n    for relative in allowed_directories:\n        pure = PurePosixPath(relative)\n        for depth in range(1, len(pure.parts)):\n            allowed_directory_ancestors.add(PurePosixPath(*pure.parts[:depth]).as_posix())\n\n    lockfile = relative_if_inside(getattr(inputs, "lockfile", None))\n'''
if source.count(old_private) != 1:
    raise SystemExit("private allowlist body anchor drifted")
source = source.replace(old_private, new_private, 1)

old_return = "    return allowed_directories, allowed_files\n\n\ndef _verify_accepted_source_physical_tree("
new_return = "    return allowed_directories, allowed_directory_ancestors, allowed_files\n\n\ndef _verify_accepted_source_physical_tree("
if source.count(old_return) != 1:
    raise SystemExit("allowlist return anchor drifted")
source = source.replace(old_return, new_return, 1)

old_unpack = "    allowed_directories, allowed_files = _accepted_source_field_allowlist(inputs, authority_root)\n"
new_unpack = "    allowed_directories, allowed_directory_ancestors, allowed_files = _accepted_source_field_allowlist(inputs, authority_root)\n"
if source.count(old_unpack) != 1:
    raise SystemExit("allowlist unpack anchor drifted")
source = source.replace(old_unpack, new_unpack, 1)

old_dir_loop = '''                if not current_relative.parts and name in allowed_directories:\n                    directories.remove(name)\n                    continue\n                candidate = current / name\n                relative = candidate.relative_to(authority_root).as_posix()\n                metadata = candidate.lstat()\n                if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):\n                    directories.remove(name)\n                    raise BuildGuardError(\n                        f"unexpected/non-directory accepted-source path before xcodebuild: {relative}"\n                    )\n                if relative not in tracked_directories:\n                    directories.remove(name)\n                    raise BuildGuardError(\n                        f"untracked accepted-source path outside field-input allowlist before xcodebuild: {relative}"\n                    )\n                seen_tracked_directories.add(relative)\n'''
new_dir_loop = '''                candidate = current / name\n                relative = candidate.relative_to(authority_root).as_posix()\n                if relative in allowed_directories:\n                    directories.remove(name)\n                    continue\n                metadata = candidate.lstat()\n                if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):\n                    directories.remove(name)\n                    raise BuildGuardError(\n                        f"unexpected/non-directory accepted-source path before xcodebuild: {relative}"\n                    )\n                if relative in allowed_directory_ancestors:\n                    continue\n                if relative not in tracked_directories:\n                    directories.remove(name)\n                    raise BuildGuardError(\n                        f"untracked accepted-source path outside field-input allowlist before xcodebuild: {relative}"\n                    )\n                seen_tracked_directories.add(relative)\n'''
if source.count(old_dir_loop) != 1:
    raise SystemExit("raw tree directory loop anchor drifted")
source = source.replace(old_dir_loop, new_dir_loop, 1)
GUARD.write_text(source, encoding="utf-8")

text = TEST.read_text(encoding="utf-8")
old_shape_assertion = "allowed_directories, allowed_files = _accepted_source_field_allowlist"
new_shape_assertion = "allowed_directories, allowed_directory_ancestors, allowed_files = _accepted_source_field_allowlist"
if text.count(old_shape_assertion) != 1:
    raise SystemExit("canonical allowlist source-shape assertion drifted")
text = text.replace(old_shape_assertion, new_shape_assertion, 1)

anchor = '''    def test_untracked_source_inserted_between_endpoint_audit_and_vnode_arming_is_rejected(self) -> None:\n'''
if text.count(anchor) != 1:
    raise SystemExit("canonical red-team class anchor drifted")
extra_test = r'''    def test_private_allowlist_does_not_hide_unrelated_local_secrets_content(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-private-root-narrow-") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            git(repo, "init", "-q")
            git(repo, "config", "user.name", "Nembra Test")
            git(repo, "config", "user.email", "nembra-test@example.invalid")
            tracked = repo / "NembraApp" / "App" / "Tracked.swift"
            tracked.parent.mkdir(parents=True)
            tracked.write_text('let authority = "accepted"\n', encoding="utf-8")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "accepted")
            accepted_sha = git(repo, "rev-parse", "HEAD")
            manifest = guard._accepted_tracked_source_manifest(repo, accepted_sha)

            sdk = repo / "LocalSecrets" / "TuyaSDK"
            runtime = repo / "LocalSecrets" / "TuyaRuntime"
            (sdk / "Build").mkdir(parents=True)
            (sdk / "ThingSmartCryption.podspec").write_text("accepted-security", encoding="utf-8")
            identity_sources = runtime / "Sources" / "NembraTuyaPrivateConfig"
            identity_sources.mkdir(parents=True)
            (runtime / "NembraTuyaPrivateConfig.podspec").write_text("accepted-identity", encoding="utf-8")
            (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text("accepted-private", encoding="utf-8")

            class PrivateShape:
                generated_pods = None
                generated_workspace = None
                lockfile = repo / "missing-lock-for-this-isolated-shape"
                security_podspec = sdk / "ThingSmartCryption.podspec"
                security_build = sdk / "Build"
                identity_podspec = runtime / "NembraTuyaPrivateConfig.podspec"
                identity_sources = identity_sources

            # The two exact local-pod roots are separately authenticated by the
            # production provenance contract and therefore may coexist with the
            # accepted Git tree.
            guard._verify_accepted_source_physical_tree(PrivateShape(), manifest, repo)

            rogue = repo / "LocalSecrets" / "Injected.swift"
            rogue.write_text('let attacker = "outside accepted private pods"\n', encoding="utf-8")
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_accepted_source_physical_tree(PrivateShape(), manifest, repo)

'''
text = text.replace(anchor, extra_test + anchor, 1)
TEST.write_text(text, encoding="utf-8")
