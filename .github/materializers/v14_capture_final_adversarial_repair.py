#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import textwrap

BASE = "fcaf1b0f29f7b6e5a7e379cbe1b7df2b207caf13"
BRANCH = "agent/v14-capture-final-adversarial-repair-sol"
WORKFLOW = ".github/workflows/tmp-v14-capture-final-adversarial-repair-sol.yml"
SELF = ".github/materializers/v14_capture_final_adversarial_repair.py"


def run(*args: str, input_bytes: bytes | None = None) -> str:
    completed = subprocess.run(
        list(args),
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output = completed.stdout.decode(errors="replace")
    if completed.returncode != 0:
        raise SystemExit(f"command failed ({completed.returncode}): {' '.join(args)}\n{output}")
    return output.strip()


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected exactly one repair marker: {old!r}")
    file.write_text(text.replace(old, new, 1))


head = run("git", "rev-parse", "HEAD")
run("git", "merge-base", "--is-ancestor", BASE, head)
initial = set(filter(None, run("git", "diff", "--name-only", BASE, head).splitlines()))
expected_initial = {WORKFLOW, SELF}
if initial != expected_initial:
    raise SystemExit(f"unexpected pre-repair child diff: {sorted(initial)}")

replace_once(
    "scripts/field/install_one_time_capture.command",
    '/usr/bin/python3 -I - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT"',
    '/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT"',
)

replace_once(
    "NembraApp/Features/Research/TuyaAccountBridge.swift",
    textwrap.dedent(
        '''\
                    let rawEndpoint = result["endpoint"] as? String ?? ""
                    let endpoint = rawEndpoint.hasPrefix("http") ? rawEndpoint : "https://\\(rawEndpoint)"
                    guard !access.isEmpty, !refresh.isEmpty, !uid.isEmpty, !endpoint.isEmpty else {
                        throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
                    }
        '''
    ),
    textwrap.dedent(
        '''\
                    let rawEndpoint = result["endpoint"] as? String ?? ""
                    let trimmedEndpoint = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                    let endpointCandidate = trimmedEndpoint.contains("://") ? trimmedEndpoint : "https://\\(trimmedEndpoint)"
                    guard let endpointComponents = URLComponents(string: endpointCandidate),
                          endpointComponents.scheme?.lowercased() == "https",
                          let endpointHost = endpointComponents.host,
                          !endpointHost.isEmpty,
                          endpointComponents.user == nil,
                          endpointComponents.password == nil,
                          let endpointURL = endpointComponents.url else {
                        throw BridgeError.malformed("Tuya approval returned an insecure or invalid account endpoint.")
                    }
                    let endpoint = endpointURL.absoluteString
                    guard !access.isEmpty, !refresh.isEmpty, !uid.isEmpty else {
                        throw BridgeError.malformed("Tuya approval succeeded but the account session was incomplete.")
                    }
        '''
    ),
)

provisioner = Path("Scripts/provision_capture_tuya_identity.sh")
text = provisioner.read_text()
old_prelude = textwrap.dedent(
    '''\
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
    # The field path is fixed by default. A caller may override only the destination
    # directory so CI can exercise this generator with dummy credentials without
    # touching a developer's real ignored LocalSecrets/TuyaRuntime contents.
    DEST="${NEMBRA_TUYA_RUNTIME_DIR:-$ROOT/LocalSecrets/TuyaRuntime}"
    SOURCE_DIR="$DEST/Sources/NembraTuyaPrivateConfig"

    umask 077
    mkdir -p "$SOURCE_DIR"
    chmod 700 "$DEST" "$DEST/Sources" "$SOURCE_DIR" 2>/dev/null || true

    read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY
    '''
)
new_prelude = textwrap.dedent(
    '''\
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
    LOCAL_SECRETS="$ROOT/LocalSecrets"
    DEST="$LOCAL_SECRETS/TuyaRuntime"
    SOURCE_DIR="$DEST/Sources/NembraTuyaPrivateConfig"
    PODSPEC="$DEST/NembraTuyaPrivateConfig.podspec"
    IDENTITY_SWIFT="$SOURCE_DIR/NembraTuyaPrivateIdentity.swift"

    umask 077
    # Never let caller xtrace echo secret-bearing expansions below.
    set +x
    for directory in "$LOCAL_SECRETS" "$DEST" "$DEST/Sources" "$SOURCE_DIR"; do
      if [[ -L "$directory" ]]; then
        echo "ERROR: refusing symlinked private Tuya destination: $directory" >&2
        exit 4
      fi
      if [[ -e "$directory" && ! -d "$directory" ]]; then
        echo "ERROR: private Tuya destination component is not a directory: $directory" >&2
        exit 4
      fi
      mkdir -p "$directory"
      chmod 700 "$directory"
    done
    for output in "$PODSPEC" "$IDENTITY_SWIFT"; do
      if [[ -e "$output" || -L "$output" ]]; then
        echo "ERROR: refusing to overwrite existing private Tuya identity output: $output" >&2
        exit 4
      fi
    done
    # Fail rather than following/replacing a file created after the checks above.
    set -o noclobber

    read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY
    '''
)
if text.count(old_prelude) != 1:
    raise SystemExit("provisioner destination-custody prelude did not match reviewed source")
text = text.replace(old_prelude, new_prelude, 1)
for old_value, new_value in [
    (
        'APP_KEY_B64="$(printf \'%s\' "$APP_KEY" | base64 | tr -d \'\\r\\n\')"',
        'APP_KEY_B64="$(printf \'%s\' "$APP_KEY" | /usr/bin/base64 | /usr/bin/tr -d \'\\r\\n\')"',
    ),
    (
        'APP_SECRET_B64="$(printf \'%s\' "$APP_SECRET" | base64 | tr -d \'\\r\\n\')"',
        'APP_SECRET_B64="$(printf \'%s\' "$APP_SECRET" | /usr/bin/base64 | /usr/bin/tr -d \'\\r\\n\')"',
    ),
    ('cat > "$DEST/NembraTuyaPrivateConfig.podspec" <<\'RUBY\'', 'cat > "$PODSPEC" <<\'RUBY\''),
    ('cat > "$SOURCE_DIR/NembraTuyaPrivateIdentity.swift" <<SWIFT', 'cat > "$IDENTITY_SWIFT" <<SWIFT'),
    (
        'chmod 600 "$DEST/NembraTuyaPrivateConfig.podspec" "$SOURCE_DIR/NembraTuyaPrivateIdentity.swift"',
        'chmod 600 "$PODSPEC" "$IDENTITY_SWIFT"',
    ),
]:
    if text.count(old_value) != 1:
        raise SystemExit(f"provisioner transform expected exactly one marker: {old_value!r}")
    text = text.replace(old_value, new_value, 1)
provisioner.write_text(text)

workflow = Path(".github/workflows/capture-field-build-provenance.yml")
text = workflow.read_text()
for old_value, new_value in [
    (
        "      - scripts/ci/es80_signed_field_artifact_private_runner.py\n",
        "      - scripts/ci/es80_signed_field_artifact_private_runner.py\n      - scripts/ci/es80_signed_field_artifact_evidence.py\n",
    ),
    (
        "      - Scripts/bootstrap_capture_tuya_sdk.sh\n",
        "      - Scripts/bootstrap_capture_tuya_sdk.sh\n      - Scripts/provision_capture_tuya_identity.sh\n",
    ),
    (
        "      - scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n",
        "      - scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n      - scripts/ci/tests/test_capture_tuya_identity_provisioner.py\n",
    ),
    (
        "          /usr/bin/python3 scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n          bash -n Scripts/bootstrap_capture_tuya_sdk.sh\n",
        "          /usr/bin/python3 scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n          /usr/bin/python3 scripts/ci/tests/test_capture_tuya_identity_provisioner.py\n          bash -n Scripts/bootstrap_capture_tuya_sdk.sh\n          bash -n Scripts/provision_capture_tuya_identity.sh\n",
    ),
    (
        "          /usr/bin/python3 -I scripts/ci/es80_signed_field_artifact_private_runner.py --self-test\n          bash -n scripts/field/install_one_time_capture.command\n",
        "          /usr/bin/python3 -I scripts/ci/es80_signed_field_artifact_private_runner.py --self-test\n          /usr/bin/python3 -m py_compile scripts/ci/es80_signed_field_artifact_evidence.py\n          /usr/bin/python3 -I scripts/ci/es80_signed_field_artifact_evidence.py --self-test\n          bash -n scripts/field/install_one_time_capture.command\n",
    ),
]:
    if text.count(old_value) != 1:
        raise SystemExit(f"provenance workflow transform expected exactly one marker: {old_value!r}")
    text = text.replace(old_value, new_value, 1)
workflow.write_text(text)

Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureTuyaEndpointTransportSecuritySourceTests.swift").write_text(
    textwrap.dedent(
        '''\
        import Foundation
        import Testing
        @testable import NembraBluetoothCapture

        @Suite("Capture Tuya endpoint transport security")
        struct CaptureTuyaEndpointTransportSecuritySourceTests {
            @Test("approval endpoint requires HTTPS before session authority is stored")
            func approvalEndpointFailsClosedBeforeSessionConstruction() throws {
                let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

                #expect(!source.contains("rawEndpoint.hasPrefix(\\\"http\\\")"))
                #expect(source.contains("endpointComponents.scheme?.lowercased() == \\\"https\\\""))
                #expect(source.contains("let endpointHost = endpointComponents.host"))
                #expect(source.contains("!endpointHost.isEmpty"))
                #expect(source.contains("endpointComponents.user == nil"))
                #expect(source.contains("endpointComponents.password == nil"))
                #expect(source.contains("Tuya approval returned an insecure or invalid account endpoint."))

                let schemeGate = try requiredIndex(
                    of: "endpointComponents.scheme?.lowercased() == \\\"https\\\"",
                    in: source
                )
                let sessionConstruction = try requiredIndex(of: "session = Session(", in: source)
                #expect(schemeGate < sessionConstruction)
            }

            private func requiredIndex(of needle: String, in source: String) throws -> String.Index {
                guard let range = source.range(of: needle) else {
                    Issue.record("Expected source marker missing: \\(needle)")
                    throw SourceContractError.markerMissing
                }
                return range.lowerBound
            }

            private func readRepositoryFile(_ relativePath: String) throws -> String {
                let repositoryRoot = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent()
                return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
            }

            private enum SourceContractError: Error {
                case markerMissing
            }
        }
        '''
    )
)

Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldPrivateReaderBytecodeSourceTests.swift").write_text(
    textwrap.dedent(
        '''\
        import Foundation
        import Testing
        @testable import NembraBluetoothCapture

        @Suite("Capture field private-reader bytecode custody")
        struct TuyaFieldPrivateReaderBytecodeSourceTests {
            @Test("installer loads the private intended-device reader without writing pyc files")
            func installerDisablesBytecodeForPrivateReaderImport() throws {
                let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
                #expect(installer.contains("/usr/bin/python3 -I -B - \\\"$PRIVATE_DEVICE_RUNNER\\\""))
                #expect(!installer.contains("/usr/bin/python3 -I - \\\"$PRIVATE_DEVICE_RUNNER\\\""))
            }

            private func readRepositoryFile(_ relativePath: String) throws -> String {
                let repositoryRoot = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent()
                return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
            }
        }
        '''
    )
)

provisioner_test = Path("scripts/ci/tests/test_capture_tuya_identity_provisioner.py")
provisioner_test.write_text(
    textwrap.dedent(
        '''\
        #!/usr/bin/env python3
        """Portable regressions for the local-only Tuya identity provisioner."""

        from __future__ import annotations

        import base64
        import os
        from pathlib import Path
        import shutil
        import stat
        import subprocess
        import tempfile

        REPO = Path(__file__).resolve().parents[3]
        SOURCE = REPO / "Scripts" / "provision_capture_tuya_identity.sh"
        APP_KEY = "dummy-app-key"
        APP_SECRET = "dummy-app-secret"


        def invoke(script: Path, *, env: dict[str, str] | None = None, xtrace: bool = False) -> subprocess.CompletedProcess[bytes]:
            command = ["bash"]
            if xtrace:
                command.append("-x")
            command.append(str(script))
            merged = os.environ.copy()
            if env:
                merged.update(env)
            return subprocess.run(
                command,
                input=f"{APP_KEY}\\n{APP_SECRET}\\n".encode(),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=merged,
                check=False,
            )


        def assert_mode_600(path: Path) -> None:
            assert stat.S_IMODE(path.stat().st_mode) == 0o600


        def copy_into(raw: str) -> tuple[Path, Path]:
            sandbox = Path(raw) / "repo"
            scripts = sandbox / "Scripts"
            scripts.mkdir(parents=True)
            script = scripts / SOURCE.name
            shutil.copy2(SOURCE, script)
            return sandbox, script


        def main() -> None:
            with tempfile.TemporaryDirectory() as raw:
                sandbox, script = copy_into(raw)
                outside = Path(raw) / "outside-runtime"
                completed = invoke(
                    script,
                    env={"NEMBRA_TUYA_RUNTIME_DIR": str(outside)},
                    xtrace=True,
                )
                output = completed.stdout.decode(errors="replace")
                assert completed.returncode == 0, output
                assert APP_KEY not in output
                assert APP_SECRET not in output
                assert not outside.exists(), "caller environment must not redirect private output"

                runtime = sandbox / "LocalSecrets" / "TuyaRuntime"
                podspec = runtime / "NembraTuyaPrivateConfig.podspec"
                identity = runtime / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift"
                assert podspec.is_file()
                assert identity.is_file()
                assert_mode_600(podspec)
                assert_mode_600(identity)
                generated = podspec.read_text() + identity.read_text()
                assert APP_KEY not in generated
                assert APP_SECRET not in generated
                assert base64.b64encode(APP_KEY.encode()).decode() in generated
                assert base64.b64encode(APP_SECRET.encode()).decode() in generated

            with tempfile.TemporaryDirectory() as raw:
                sandbox, script = copy_into(raw)
                escape = Path(raw) / "escape"
                escape.mkdir()
                (sandbox / "LocalSecrets").symlink_to(escape, target_is_directory=True)
                completed = invoke(script)
                assert completed.returncode != 0
                assert not (escape / "TuyaRuntime").exists()

            with tempfile.TemporaryDirectory() as raw:
                sandbox, script = copy_into(raw)
                source_dir = sandbox / "LocalSecrets" / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig"
                source_dir.mkdir(parents=True)
                target = source_dir / "NembraTuyaPrivateIdentity.swift"
                escape_file = Path(raw) / "escape-secret.txt"
                escape_file.write_text("sentinel")
                target.symlink_to(escape_file)
                completed = invoke(script)
                assert completed.returncode != 0
                assert escape_file.read_text() == "sentinel"


        if __name__ == "__main__":
            main()
        '''
    )
)
provisioner_test.chmod(0o755)

# Portable validation before committing any materialized change.
run("bash", "-n", "scripts/field/install_one_time_capture.command")
run("bash", "-n", "Scripts/bootstrap_capture_tuya_sdk.sh")
run("bash", "-n", "Scripts/provision_capture_tuya_identity.sh")
run("python3", "-m", "py_compile", "scripts/ci/es80_signed_field_artifact_evidence.py")
run("python3", "-I", "scripts/ci/es80_signed_field_artifact_evidence.py", "--self-test")
run("python3", "-m", "py_compile", str(provisioner_test))
run("python3", str(provisioner_test))

installer = Path("scripts/field/install_one_time_capture.command").read_text()
if '/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER"' not in installer:
    raise SystemExit("installer -B repair missing")
if '/usr/bin/python3 -I - "$PRIVATE_DEVICE_RUNNER"' in installer:
    raise SystemExit("old bytecode-writing private-reader invocation survived")
bridge = Path("NembraApp/Features/Research/TuyaAccountBridge.swift").read_text()
if 'endpointComponents.scheme?.lowercased() == "https"' not in bridge:
    raise SystemExit("HTTPS endpoint gate missing")
if 'rawEndpoint.hasPrefix("http")' in bridge:
    raise SystemExit("insecure endpoint prefix admission survived")
provenance = workflow.read_text()
for marker in [
    "scripts/ci/es80_signed_field_artifact_evidence.py",
    "Scripts/provision_capture_tuya_identity.sh",
    "scripts/ci/tests/test_capture_tuya_identity_provisioner.py",
]:
    if marker not in provenance:
        raise SystemExit(f"field provenance coverage missing: {marker}")

Path(WORKFLOW).unlink()
Path(SELF).unlink()

expected_status = {
    ".github/materializers/v14_capture_final_adversarial_repair.py",
    ".github/workflows/capture-field-build-provenance.yml",
    ".github/workflows/tmp-v14-capture-final-adversarial-repair-sol.yml",
    "NembraApp/Features/Research/TuyaAccountBridge.swift",
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureTuyaEndpointTransportSecuritySourceTests.swift",
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldPrivateReaderBytecodeSourceTests.swift",
    "Scripts/provision_capture_tuya_identity.sh",
    "scripts/ci/tests/test_capture_tuya_identity_provisioner.py",
    "scripts/field/install_one_time_capture.command",
}
status_lines = run("git", "status", "--porcelain=v1").splitlines()
actual_status = {line[3:] for line in status_lines if line}
if actual_status != expected_status:
    raise SystemExit(f"unexpected materialized path set: {sorted(actual_status)}")
run("git", "diff", "--check")

run("git", "config", "user.name", "github-actions[bot]")
run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
run("git", "add", "-A")
run("git", "commit", "-m", "fix(capture): close final adversarial field blockers")
run("git", "fetch", "origin", BRANCH)
if run("git", "rev-parse", "FETCH_HEAD") != head:
    raise SystemExit("child branch moved during materialization; refusing to overwrite")
run("git", "push", "origin", f"HEAD:{BRANCH}")
