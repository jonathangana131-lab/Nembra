#!/usr/bin/env python3
from pathlib import Path

installer_path = Path("scripts/field/install_one_time_capture.command")
installer = installer_path.read_text()
marker = ': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute private mode-0600 file containing only the intended iPhone UDID.}"\n'
digest_guard = ''': "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256:?Final GO must provide NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 as the accepted SHA-256 of the intended-device identifier.}"
[[ "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 must be exactly 64 hex characters."
NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$(printf '%s' "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" | tr '[:upper:]' '[:lower:]')"
export NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256
'''
if marker not in installer or "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" in installer:
    raise SystemExit("installer digest-guard anchor missing or already transformed")
installer = installer.replace(marker, marker + digest_guard, 1)
imports_old = "import importlib.util\nimport sys\nfrom pathlib import Path\n"
imports_new = "import hashlib\nimport hmac\nimport importlib.util\nimport os\nimport re\nimport sys\nfrom pathlib import Path\n"
if imports_old not in installer:
    raise SystemExit("private-reader inline Python import anchor missing")
installer = installer.replace(imports_old, imports_new, 1)
read_old = '''value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
sys.stdout.write(value)
'''
read_new = '''value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
'''
if read_old not in installer:
    raise SystemExit("private-reader value anchor missing")
installer = installer.replace(read_old, read_new, 1)
success_old = '[[ -n "$DEVICE_UDID" ]] || die "The intended-device verification file produced no identifier."\nsay "Private intended-device admission validated"\n'
success_new = '[[ -n "$DEVICE_UDID" ]] || die "The intended-device verification file produced no identifier."\nunset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 || true\nsay "Private intended-device admission validated against Final GO digest"\n'
if success_old not in installer:
    raise SystemExit("private-reader success anchor missing")
installer_path.write_text(installer.replace(success_old, success_new, 1))

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift")
test = test_path.read_text()
test_anchor = '    @Test("accepted source carries the hardened private intended-device reader")\n'
test_method = '''    @Test("intended-device identity is bound to Final GO digest before device discovery")
    func intendedDeviceIdentityMustMatchFinalGoDigest() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"))
        #expect(installer.contains("hashlib.sha256(value.encode(\\\"utf-8\\\")).hexdigest()"))
        #expect(installer.contains("hmac.compare_digest(actual_digest, expected_digest)"))
        #expect(installer.contains("private intended-device identifier does not match Final GO authority"))
        #expect(installer.contains("unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"))
        let digestCheck = installer.range(of: "hmac.compare_digest(actual_digest, expected_digest)")
        let deviceDiscovery = installer.range(of: "Verifying the intended iPhone 12 / iOS 27 baseline")
        #expect(digestCheck != nil)
        #expect(deviceDiscovery != nil)
        if let digestCheck, let deviceDiscovery {
            #expect(digestCheck.lowerBound < deviceDiscovery.lowerBound)
        }
    }

'''
if test_anchor not in test or "intendedDeviceIdentityMustMatchFinalGoDigest" in test:
    raise SystemExit("intended-device source-test anchor missing or already transformed")
test_path.write_text(test.replace(test_anchor, test_method + test_anchor, 1))

workflow_path = Path(".github/workflows/capture-field-build-provenance.yml")
workflow = workflow_path.read_text()
workflow_anchor = "          grep -Fq 'NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE' \"$installer\"\n"
workflow_extra = "          grep -Fq 'NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256' \"$installer\"\n          grep -Fq 'hmac.compare_digest(actual_digest, expected_digest)' \"$installer\"\n"
if workflow_anchor not in workflow or "hmac.compare_digest(actual_digest, expected_digest)" in workflow:
    raise SystemExit("field-provenance digest anchor missing or already transformed")
workflow_path.write_text(workflow.replace(workflow_anchor, workflow_anchor + workflow_extra, 1))
