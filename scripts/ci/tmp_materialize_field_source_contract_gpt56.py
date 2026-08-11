#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[2]
INTENDED = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift"
ORDERING = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerSourceCustodyOrderingSourceTests.swift"
PROVENANCE = ROOT / "scripts/ci/tests/test_capture_tuya_private_input_provenance.py"
TEMP_SCRIPT = ROOT / "scripts/ci/tmp_materialize_field_source_contract_gpt56.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-field-source-contract-gpt56.yml"

EXPECTED_BLOBS = {
    INTENDED: "553023a6a749845b5ef18ce6f349b119cd300881",
    ORDERING: "67a51e93b43412069aa2757d541bacad3b9dd0cd",
    PROVENANCE: "a074b9957770c8ed536cff89a275fcd8df62b5ba",
}


def git_blob(path: Path) -> str:
    payload = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def replace_section(source: str, start: str, end: str, replacement: str, label: str) -> str:
    start_index = source.find(start)
    if start_index < 0:
        raise SystemExit(f"{label}: start marker missing")
    end_index = source.find(end, start_index + len(start))
    if end_index < 0:
        raise SystemExit(f"{label}: end marker missing")
    return source[:start_index] + replacement + source[end_index:]


for path, expected in EXPECTED_BLOBS.items():
    actual = git_blob(path)
    if actual != expected:
        raise SystemExit(f"{path.relative_to(ROOT)} moved: expected {expected}, got {actual}")

# 1) Align the intended-device/source guard regression with the new independent
# fresh-index + raw-byte accepted-checkout authority. Preserve the explicit
# narrow field-input allowlist and make the test reject a return to Git-ignore
# based untracked authority.
source = INTENDED.read_text(encoding="utf-8")
source = replace_once(
    source,
    '''        #expect(installer.components(separatedBy: "git status --porcelain=v1 --untracked-files=all").count >= 3)\n        #expect(installer.contains("Private workspace bootstrap changed tracked or unignored accepted-source inputs"))\n        #expect(installer.contains("Accepted-source inputs changed while the field build was compiling"))\n''',
    '''        #expect(installer.contains("verify_accepted_checkout_source()"))\n        #expect(installer.contains("status --porcelain=v1 --untracked-files=no"))\n        #expect(installer.contains("[\\\"/usr/bin/git\\\", \\\"ls-tree\\\", \\\"-r\\\", \\\"-z\\\", source_sha]"))\n        #expect(installer.contains("field_input_directories = (\\\"LocalSecrets\\\", \\\"Pods\\\", \\\"NembraCapture.xcworkspace\\\")"))\n        #expect(installer.contains("relative == \\\"Podfile.lock\\\""))\n        #expect(installer.contains("untracked accepted-source path outside field-input allowlist"))\n        #expect(installer.contains("verify_accepted_checkout_source \\\"Private workspace bootstrap changed accepted-source inputs.\\\""))\n        #expect(installer.contains("verify_accepted_checkout_source \\\"Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart.\\\""))\n''',
    "field allowlist authority expectations",
)
source = replace_once(
    source,
    '''        #expect(installer.contains("Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA"))\n        #expect(installer.contains("Repository HEAD changed during private workspace bootstrap"))\n        #expect(installer.contains("Private workspace bootstrap changed tracked or unignored accepted-source inputs"))\n        #expect(installer.contains("Repository HEAD changed while the accepted field build was compiling"))\n        #expect(installer.contains("Accepted-source inputs changed while the field build was compiling"))\n''',
    '''        #expect(installer.contains("Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA"))\n        #expect(installer.contains("Repository HEAD no longer matches the accepted source."))\n        #expect(installer.contains("Tracked source differs from the accepted commit."))\n        #expect(installer.contains("Raw accepted-source byte audit failed."))\n        #expect(installer.contains("verify_accepted_checkout_source \\\"Private workspace bootstrap changed accepted-source inputs.\\\""))\n        #expect(installer.contains("verify_accepted_checkout_source \\\"Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart.\\\""))\n''',
    "field source recheck messages",
)
INTENDED.write_text(source, encoding="utf-8")

# 2) The ordering suite previously required raw ambient `git rev-parse/status`
# and direct execution of the mutable bootstrap pathname. Bind it instead to the
# isolated authority helper, accepted-source audit, accepted Git-object bootstrap
# execution, guarded xcodebuild, and the two post-boundary source reproofs.
source = ORDERING.read_text(encoding="utf-8")
first_start = '    @Test("exact requested source is canonical and clean before private field admission")\n'
second_start = '    @Test("source custody survives private workspace bootstrap build and built-app readback before install")\n'
third_start = '    @Test("built app identity rendezvous is exact rather than label-only")\n'
first_replacement = '''    @Test("exact requested source is canonical and clean before private field admission")\n    func exactSourcePrecedesPrivateAdmission() throws {\n        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")\n\n        guard let input = installer.range(of: "EXPECTED_SOURCE_SHA=\\\"${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}\\\""),\n              let shape = installer.range(of: "[[ \\\"$EXPECTED_SOURCE_SHA\\\" =~ ^[0-9A-Fa-f]{40}$ ]]", range: input.upperBound..<installer.endIndex),\n              let normalize = installer.range(of: "EXPECTED_SOURCE_SHA=\\\"$(printf '%s' \\\"$EXPECTED_SOURCE_SHA\\\" | tr '[:upper:]' '[:lower:]')\\\"", range: shape.upperBound..<installer.endIndex),\n              let gitDirectory = installer.range(of: "AUTHORITY_GIT_DIR=\\\"$ROOT/.git\\\"", range: normalize.upperBound..<installer.endIndex),\n              let authority = installer.range(of: "run_authority_git() {", range: gitDirectory.upperBound..<installer.endIndex),\n              let head = installer.range(of: "SOURCE_SHA=\\\"$(run_authority_git rev-parse --verify 'HEAD^{commit}' | tr '[:upper:]' '[:lower:]')\\\"", range: authority.upperBound..<installer.endIndex),\n              let equality = installer.range(of: "[[ \\\"$SOURCE_SHA\\\" == \\\"$EXPECTED_SOURCE_SHA\\\" ]]", range: head.upperBound..<installer.endIndex),\n              let sourceAudit = installer.range(of: "verify_accepted_checkout_source \\\"Current checkout is not the exact accepted Capture source.\\\"", range: equality.upperBound..<installer.endIndex),\n              let requestedMessage = installer.range(of: "say \\\"Exact requested Capture source matched under isolated Git + raw-byte authority: $SOURCE_SHA\\\"", range: sourceAudit.upperBound..<installer.endIndex),\n              let privateAdmission = installer.range(of: "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true", range: requestedMessage.upperBound..<installer.endIndex) else {\n            Issue.record("The field installer must canonicalize and prove one clean exact requested source before it can admit private intended-device input.")\n            throw SourceContractError.sectionMissing\n        }\n\n        #expect(input.lowerBound < shape.lowerBound)\n        #expect(shape.lowerBound < normalize.lowerBound)\n        #expect(normalize.lowerBound < gitDirectory.lowerBound)\n        #expect(gitDirectory.lowerBound < authority.lowerBound)\n        #expect(authority.lowerBound < head.lowerBound)\n        #expect(head.lowerBound < equality.lowerBound)\n        #expect(equality.lowerBound < sourceAudit.lowerBound)\n        #expect(sourceAudit.lowerBound < requestedMessage.lowerBound)\n        #expect(requestedMessage.lowerBound < privateAdmission.lowerBound)\n        #expect(installer.contains("GIT_NO_REPLACE_OBJECTS=1"))\n        #expect(installer.contains("GIT_CONFIG_NOSYSTEM=1"))\n        #expect(installer.contains("GIT_CONFIG_GLOBAL=/dev/null"))\n        #expect(installer.contains("[\\\"/usr/bin/git\\\", \\\"ls-tree\\\", \\\"-r\\\", \\\"-z\\\", source_sha]"))\n        #expect(!installer.contains("Exact accepted Capture source: $SOURCE_SHA"))\n        #expect(!installer.contains("Switch to capture/one-time-ble-dump-gpt56 first"))\n    }\n\n'''
source = replace_section(source, first_start, second_start, first_replacement, "exact-source ordering test")
second_replacement = '''    @Test("source custody survives private workspace bootstrap build and built-app readback before install")\n    func sourceCustodyEnclosesBuildAndReadback() throws {\n        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")\n\n        guard let initialAudit = installer.range(of: "verify_accepted_checkout_source \\\"Current checkout is not the exact accepted Capture source.\\\""),\n              let privateAdmission = installer.range(of: "unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true", range: initialAudit.upperBound..<installer.endIndex),\n              let bootstrap = installer.range(of: "run_accepted_source_bash \\\"Scripts/bootstrap_capture_tuya_sdk.sh\\\"", range: privateAdmission.upperBound..<installer.endIndex),\n              let postBootstrapAudit = installer.range(of: "verify_accepted_checkout_source \\\"Private workspace bootstrap changed accepted-source inputs.\\\"", range: bootstrap.upperBound..<installer.endIndex),\n              let baseline = installer.range(of: "say \\\"Intended baseline proven: iPhone 12 / iOS $DEVICE_OS_VERSION\\\"", range: postBootstrapAudit.upperBound..<installer.endIndex),\n              let buildStage = installer.range(of: "say \\\"Building SDK-integrated Nembra Capture for the intended iPhone\\\"", range: baseline.upperBound..<installer.endIndex),\n              let guardedBuild = installer.range(of: "run_accepted_source_python \\\"$TUYA_BUILD_WINDOW_GUARD_RELATIVE\\\"", range: buildStage.upperBound..<installer.endIndex),\n              let postBuildAudit = installer.range(of: "verify_accepted_checkout_source \\\"Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart.\\\"", range: guardedBuild.upperBound..<installer.endIndex),\n              let appReadback = installer.range(of: "APP_INFO_PLIST=\\\"$APP/Info.plist\\\"", range: postBuildAudit.upperBound..<installer.endIndex),\n              let builtSource = installer.range(of: "[[ \\\"$BUILT_SOURCE_SHA\\\" == \\\"$SOURCE_SHA\\\" ]]", range: appReadback.upperBound..<installer.endIndex),\n              let install = installer.range(of: "say \\\"Installing SDK-integrated Capture on the intended iPhone\\\"", range: builtSource.upperBound..<installer.endIndex) else {\n            Issue.record("The field build must remain inside exact-source custody from private bootstrap through built-app provenance readback before installation.")\n            throw SourceContractError.sectionMissing\n        }\n\n        #expect(initialAudit.lowerBound < privateAdmission.lowerBound)\n        #expect(privateAdmission.lowerBound < bootstrap.lowerBound)\n        #expect(bootstrap.lowerBound < postBootstrapAudit.lowerBound)\n        #expect(postBootstrapAudit.lowerBound < baseline.lowerBound)\n        #expect(baseline.lowerBound < buildStage.lowerBound)\n        #expect(buildStage.lowerBound < guardedBuild.lowerBound)\n        #expect(guardedBuild.lowerBound < postBuildAudit.lowerBound)\n        #expect(postBuildAudit.lowerBound < appReadback.lowerBound)\n        #expect(appReadback.lowerBound < builtSource.lowerBound)\n        #expect(builtSource.lowerBound < install.lowerBound)\n        #expect(installer.contains("run_authority_git show \\\"$SOURCE_SHA:$relative_path\\\""))\n        #expect(installer.contains("/bin/bash --noprofile --norc -p -c 'source /dev/stdin'"))\n    }\n\n'''
source = replace_section(source, second_start, third_start, second_replacement, "build source-custody ordering test")
ORDERING.write_text(source, encoding="utf-8")

# 3) Field Build Provenance's portable Python contract must require the new
# accepted-object bootstrap execution and the now-fixed absolute xcodebuild tool,
# rather than requiring the mutable worktree path that #2876 deliberately removed.
source = PROVENANCE.read_text(encoding="utf-8")
source = replace_once(
    source,
    '''        bootstrap_call = '\"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh\"'\n        build_call = "-- xcodebuild"\n''',
    '''        bootstrap_call = 'run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"'\n        build_call = "-- /usr/bin/xcodebuild"\n''',
    "provenance bootstrap/build call contract",
)
source = replace_once(
    source,
    '''        self.assertIn(bootstrap_call, installer)\n        self.assertIn(build_call, installer)\n        self.assertLess(installer.index(bootstrap_call), installer.index(build_call))\n''',
    '''        self.assertIn("run_accepted_source_bash() {", installer)\n        self.assertIn('run_authority_git show "$SOURCE_SHA:$relative_path"', installer)\n        self.assertIn("/bin/bash --noprofile --norc -p -c 'source /dev/stdin'", installer)\n        self.assertIn(bootstrap_call, installer)\n        self.assertNotIn('\\n"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\\n', installer)\n        self.assertIn(build_call, installer)\n        self.assertLess(installer.index(bootstrap_call), installer.index(build_call))\n''',
    "provenance accepted bootstrap assertions",
)
PROVENANCE.write_text(source, encoding="utf-8")

# Materializers are construction-only. Delete them before the publish commit so
# the branch tree contains only durable source-contract repairs.
for temporary in (TEMP_SCRIPT, TEMP_WORKFLOW):
    if temporary.exists():
        temporary.unlink()
