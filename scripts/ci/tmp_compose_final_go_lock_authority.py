#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

SOURCE = "7a0da0eb08cac328f2212eb2d2a7c7af0265b7c1"
FINAL = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
TEST = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
ENV_TEST = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py")


def show(path: Path) -> str:
    return subprocess.check_output(
        ["git", "show", f"{SOURCE}:{path.as_posix()}"], text=True
    )


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {text.count(old)}")
    return text.replace(old, new, 1)


# Start from the already canonical-workflow-green lock-authority composition, then
# apply the later stronger intended-device digest custody exactly once.
final = show(FINAL)
final = replace_once(
    final,
    '    lock_contract=("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" in boot and "--resolve-lock-for-review" in boot and \'[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]\' in boot and \'"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\' in ins and "-- xcodebuild" in ins and ins.index(\'"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\')<ins.index("-- xcodebuild"))\n'
    '    if f\'PROCEDURE_ID="{PROC}"\' not in ins or f\'BUNDLE_ID="{BUNDLE}"\' not in ins or f"PROCEDURE_ID: `{PROC}`" not in rb or f\'static let requiredFieldProcedureIdentifier = "{PROC}"\' not in ident or "ES80-FINGERPRINT-v1" in ins or "NEMBRA_ES80_TODAY_RESEARCH" in ins or not lock_contract: raise GoError("candidate carries wrong/retired/incomplete field authority")\n',
    '    lock_contract=("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" in boot and "--resolve-lock-for-review" in boot and \'[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]\' in boot and \'"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\' in ins and "-- xcodebuild" in ins and ins.index(\'"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\')<ins.index("-- xcodebuild"))\n'
    '    digest_contract=("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" in ins and "hmac.compare_digest(actual_digest, expected_digest)" in ins)\n'
    '    if f\'PROCEDURE_ID="{PROC}"\' not in ins or f\'BUNDLE_ID="{BUNDLE}"\' not in ins or f"PROCEDURE_ID: `{PROC}`" not in rb or f\'static let requiredFieldProcedureIdentifier = "{PROC}"\' not in ident or "ES80-FINGERPRINT-v1" in ins or "NEMBRA_ES80_TODAY_RESEARCH" in ins or not lock_contract or not digest_contract: raise GoError("candidate carries wrong/retired/incomplete field authority")\n',
    "candidate digest rendezvous",
)

old_device = '''def device_hash(path:Path):
    p=canonical_private_path(path,"private intended-device identifier")
    raw=regular(p,"private intended-device identifier",True)
    try:t=raw.decode().strip()
    except UnicodeDecodeError as e: raise GoError("private device identifier invalid") from e
    if not t or any(c.isspace() for c in t): raise GoError("private device identifier must be one token")
    return sha(t.encode())

def installer_environment(device:Path,accepted_lock_sha:str)->dict[str,str]:
    if not isinstance(accepted_lock_sha,str) or not HEX64.fullmatch(accepted_lock_sha): raise GoError("accepted Tuya dependency lock digest invalid")
    account=pwd.getpwuid(os.getuid()); device_path=canonical_private_path(device,"private intended-device identifier")
    intended_device_digest=device_hash(device_path)
    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":intended_device_digest,"NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256":accepted_lock_sha}

def installer(repo:Path,source:str,device:Path,accepted_lock_sha:str):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,accepted_lock_sha)
'''
new_device = '''def device_hash(path:Path):
    p=path.expanduser()
    if not p.is_absolute() or p.anchor!=os.sep or any(x in ("", ".", "..") for x in p.parts[1:]): raise GoError("private intended-device identifier path must be canonical absolute")
    if not hasattr(os,"O_NOFOLLOW") or not hasattr(os,"O_DIRECTORY"): raise GoError("descriptor-bound private device custody unavailable")
    clo=getattr(os,"O_CLOEXEC",0); parent=None; fd=None
    try:
        parent=os.open(os.sep,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|clo)
        for component in p.parts[1:-1]:
            nxt=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|clo,dir_fd=parent)
            os.close(parent); parent=nxt
        fd=os.open(p.parts[-1],os.O_RDONLY|os.O_NOFOLLOW|clo,dir_fd=parent)
    except OSError as e:
        raise GoError("private intended-device identifier unavailable through descriptor-bound path custody") from e
    finally:
        if parent is not None: os.close(parent)
    try:
        a=os.fstat(fd)
        if not stat.S_ISREG(a.st_mode) or a.st_size<=0 or a.st_size>4096: raise GoError("private device identifier must be a small non-empty regular file")
        if stat.S_IMODE(a.st_mode)!=0o600: raise GoError("private device identifier must be mode 0600")
        if a.st_uid!=os.geteuid() or a.st_nlink!=1: raise GoError("private device identifier ownership/link custody invalid")
        raw=b""
        while len(raw)<=4096:
            chunk=os.read(fd,4097-len(raw))
            if not chunk: break
            raw+=chunk
        b=os.fstat(fd)
    finally:
        if fd is not None: os.close(fd)
    stable=lambda s:(s.st_dev,s.st_ino,s.st_mode,s.st_uid,s.st_gid,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    if stable(a)!=stable(b) or len(raw)!=a.st_size: raise GoError("private device identifier changed while reading")
    try:t=raw.decode("utf-8")
    except UnicodeDecodeError as e: raise GoError("private device identifier invalid") from e
    if t!=t.strip() or not re.fullmatch(r"[A-Za-z0-9-]+",t): raise GoError("private device identifier must be one canonical token without surrounding whitespace")
    return sha(t.encode("utf-8"))

def installer_environment(device:Path,device_digest:str,accepted_lock_sha:str)->dict[str,str]:
    if not isinstance(accepted_lock_sha,str) or not HEX64.fullmatch(accepted_lock_sha): raise GoError("accepted Tuya dependency lock digest invalid")
    account=pwd.getpwuid(os.getuid()); device_path=canonical_private_path(device,"private intended-device identifier")
    digest=device_digest.lower()
    if not HEX64.fullmatch(digest): raise GoError("private intended-device digest invalid")
    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest,"NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256":accepted_lock_sha}

def installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha:str):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest,accepted_lock_sha)
'''
final = replace_once(final, old_device, new_device, "descriptor-bound prechecked device custody")
final = replace_once(
    final,
    '    accepted_lock=lr["podfileLockSHA256"]; got=run_installer(candidate_repo,source,device_file,accepted_lock); expected=',
    '    accepted_lock=lr["podfileLockSHA256"]; got=run_installer(candidate_repo,source,device_file,dh,accepted_lock); expected=',
    "prechecked device digest install handoff",
)
FINAL.write_text(final)

# The 7a0 suite already covers the lock review and current-main composition. Adapt
# only the installer callback signatures and fixture source needed by the newer
# device-digest rendezvous.
test = show(TEST)
test = replace_once(
    test,
    "  installer=f'PROCEDURE_ID=\"{go.PROC}\"\\nBUNDLE_ID=\"{go.BUNDLE}\"\\n\"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh\"\\n-- xcodebuild\\n'",
    "  installer=f'PROCEDURE_ID=\"{go.PROC}\"\\nBUNDLE_ID=\"{go.BUNDLE}\"\\n# NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256\\n# hmac.compare_digest(actual_digest, expected_digest)\\n\"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh\"\\n-- xcodebuild\\n'",
    "candidate fixture digest contract",
)
test = replace_once(
    test,
    " def inst(self,repo,s,dev,lock):return {'authority':'accepted-candidate-private-installer-execution-v1'",
    " def inst(self,repo,s,dev,h,lock):\n  assert h==H(b'device-token')\n  return {'authority':'accepted-candidate-private-installer-execution-v1'",
    "fixture installer signature",
)
test = test.replace("def run(r,s,d,lock):", "def run(r,s,d,h,lock):")
test = test.replace("def bad(r,s,d,lock):", "def bad(r,s,d,h,lock):")
test = test.replace("def move_main(r,s,d,lock):", "def move_main(r,s,d,h,lock):")
test = test.replace("def merge_pr(r,s,d,lock):", "def merge_pr(r,s,d,h,lock):")
test = test.replace("def move_pr(r,s,d,lock):", "def move_pr(r,s,d,h,lock):")
test = test.replace("def expire(r,s,d,lock):", "def expire(r,s,d,h,lock):")
test = test.replace("def dismiss(r,s,d,lock):", "def dismiss(r,s,d,h,lock):")
test = test.replace("def change_lock_review(r,s,d,lock):", "def change_lock_review(r,s,d,h,lock):")
test = test.replace("def change_device(r,s,d,lock):", "def change_device(r,s,d,h,lock):")
test = test.replace("self.f.inst(r,s,d,lock)", "self.f.inst(r,s,d,h,lock)")
anchor = " def test_private_device_custody_and_installer_drift_rejected(self):\n"
prechecked = ''' def test_prechecked_device_digest_and_reviewed_lock_are_passed_to_installer(self):
  seen=[]
  def capture(r,s,d,h,lock):seen.append((h,lock));return self.f.inst(r,s,d,h,lock)
  self.assertEqual(self.f.build(run_installer=capture)['status'],'GO')
  self.assertEqual(seen,[(H(b'device-token'),self.f.lock)])
'''
test = replace_once(test, anchor, prechecked + anchor, "prechecked-device regression anchor")
TEST.write_text(test)

# Preserve the hostile ambient-lock regression from 7a0, but require the original
# prechecked device digest to cross the process boundary unchanged.
env_test = show(ENV_TEST)
env_test = replace_once(
    env_test,
    "                result = GO.installer(repository, source, private_device, LOCK_SHA256)",
    "                device_digest = GO.device_hash(private_device)\n                result = GO.installer(repository, source, private_device, device_digest, LOCK_SHA256)",
    "environment test installer call",
)
env_test = replace_once(
    env_test,
    "            env = GO.installer_environment(device, LOCK_SHA256)",
    "            device_digest = GO.device_hash(device)\n            env = GO.installer_environment(device, device_digest, LOCK_SHA256)",
    "environment allowlist call",
)
env_test = replace_once(
    env_test,
    '            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], GO.device_hash(device))',
    '            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], device_digest)',
    "environment device digest assertion",
)
env_test = replace_once(
    env_test,
    '                GO.installer_environment(device, "not-reviewed-lock")',
    '                GO.installer_environment(device, GO.device_hash(device), "not-reviewed-lock")',
    "invalid lock call",
)
env_test = replace_once(
    env_test,
    '                GO.installer_environment(alias / "device", LOCK_SHA256)',
    '                GO.installer_environment(alias / "device", "0" * 64, LOCK_SHA256)',
    "symlink-parent call",
)
insert = '''
    def test_installer_environment_preserves_prechecked_digest_instead_of_recomputing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-prechecked-digest-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("original-device", encoding="utf-8")
            device.chmod(0o600)
            prechecked = GO.device_hash(device)
            device.write_text("replacement-device", encoding="utf-8")
            env = GO.installer_environment(device, prechecked, LOCK_SHA256)
            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], prechecked)
            self.assertNotEqual(prechecked, GO.device_hash(device))

    def test_installer_environment_rejects_invalid_prechecked_device_digest(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-device-digest-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            with self.assertRaises(GO.GoError):
                GO.installer_environment(device, "not-a-device-digest", LOCK_SHA256)
'''
env_test = replace_once(
    env_test,
    "\n\nif __name__ == \"__main__\":\n",
    insert + "\n\nif __name__ == \"__main__\":\n",
    "environment regression tail",
)
ENV_TEST.write_text(env_test)
