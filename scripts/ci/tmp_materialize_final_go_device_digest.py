#!/usr/bin/env python3
from pathlib import Path
import re

issuer_path = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
issuer = issuer_path.read_text()

candidate_anchor = "    if f'PROCEDURE_ID=\"{PROC}\"' not in ins or f'BUNDLE_ID=\"{BUNDLE}\"' not in ins or f\"PROCEDURE_ID: `{PROC}`\" not in rb or f'static let requiredFieldProcedureIdentifier = \"{PROC}\"' not in ident or \"ES80-FINGERPRINT-v1\" in ins or \"NEMBRA_ES80_TODAY_RESEARCH\" in ins: raise GoError(\"candidate carries wrong/retired field authority\")\n"
if candidate_anchor not in issuer or "candidate installer lacks intended-device digest rendezvous" in issuer:
    raise SystemExit("candidate authority anchor missing/already transformed")
candidate_guard = "    if \"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256\" not in ins or \"hmac.compare_digest(actual_digest, expected_digest)\" not in ins: raise GoError(\"candidate installer lacks intended-device digest rendezvous\")\n"
issuer = issuer.replace(candidate_anchor, candidate_guard + candidate_anchor, 1)

start = issuer.index("def device_hash(path:Path):\n")
end = issuer.index("def retained_signed_artifact(", start)
replacement = '''def device_hash(path:Path):
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

def installer_environment(device:Path,device_digest:str)->dict[str,str]:
    account=pwd.getpwuid(os.getuid()); device_path=canonical_private_path(device,"private intended-device identifier")
    digest=device_digest.lower()
    if not HEX64.fullmatch(digest): raise GoError("private intended-device digest invalid")
    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest}

def installer(repo:Path,source:str,device:Path,device_digest:str):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest)
    try:p=subprocess.run(["/bin/bash","--noprofile","--norc","-p",str(root/INSTALLER),source],cwd=root,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    except OSError as e: raise GoError("private installer execution failed") from e
    if p.returncode or "SDK-INTEGRATED CAPTURE LAUNCHED" not in p.stdout or canon(git(root,"rev-parse","HEAD"),"post-install HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("private installer did not preserve exact accepted field subject")
    return {"authority":"accepted-candidate-private-installer-execution-v1","result":"success","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}

'''
issuer = issuer[:start] + replacement + issuer[end:]
old_call = "got=run_installer(candidate_repo,source,device_file); expected="
if old_call not in issuer:
    raise SystemExit("run-installer authority anchor missing")
issuer = issuer.replace(old_call, "got=run_installer(candidate_repo,source,device_file,dh); expected=", 1)
issuer_path.write_text(issuer)

main_test_path = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
test = main_test_path.read_text()
fixture_old = "go.INSTALLER:f'PROCEDURE_ID=\"{go.PROC}\"\\nBUNDLE_ID=\"{go.BUNDLE}\"\\n'"
fixture_new = "go.INSTALLER:f'PROCEDURE_ID=\"{go.PROC}\"\\nBUNDLE_ID=\"{go.BUNDLE}\"\\n# NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256\\n# hmac.compare_digest(actual_digest, expected_digest)\\n'"
if fixture_old not in test:
    raise SystemExit("main test installer fixture anchor missing")
test = test.replace(fixture_old, fixture_new, 1)
test = test.replace("self.dev.write_text('device-token\\n')", "self.dev.write_text('device-token')", 1)
test = test.replace("def inst(self,repo,s,dev):return", "def inst(self,repo,s,dev,h):\n  assert h==H(b'device-token')\n  return", 1)
test = re.sub(r"def ([A-Za-z_][A-Za-z0-9_]*)\(r,s,d\):", r"def \1(r,s,d,h):", test)
test = test.replace("self.f.inst(r,s,d)", "self.f.inst(r,s,d,h)")
insert_anchor = " def test_private_device_custody_and_installer_drift_rejected(self):\n"
if insert_anchor not in test or "test_prechecked_device_digest_is_passed_to_installer" in test:
    raise SystemExit("main test digest insertion anchor missing/already transformed")
new_test = ''' def test_prechecked_device_digest_is_passed_to_installer(self):
  seen=[]
  def capture(r,s,d,h):seen.append(h);return self.f.inst(r,s,d,h)
  self.assertEqual(self.f.build(run_installer=capture)['status'],'GO')
  self.assertEqual(seen,[H(b'device-token')])
'''
test = test.replace(insert_anchor, new_test + insert_anchor, 1)
main_test_path.write_text(test)

env_test_path = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py")
envtest = env_test_path.read_text()
envtest = envtest.replace("import importlib.util\n", "import hashlib\nimport importlib.util\n", 1)
envtest = envtest.replace("result = GO.installer(repository, source, private_device)", "result = GO.installer(repository, source, private_device, GO.device_hash(private_device))", 1)
envtest = envtest.replace("env = GO.installer_environment(device)", "digest = GO.device_hash(device)\n            env = GO.installer_environment(device, digest)", 1)
envtest = envtest.replace('self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"], str(device))', 'self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"], str(device))\n            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], digest)', 1)
envtest = envtest.replace("GO.installer_environment(alias / \"device\")", "GO.installer_environment(alias / \"device\", \"a\" * 64)", 1)
fixture_line = '"[[ -z \\\"${NEMBRA_TUYA_APP_KEY:-}\\\" ]] || exit 45\\n"\n'
if fixture_line not in envtest:
    raise SystemExit("environment fixture anchor missing")
envtest = envtest.replace(fixture_line, fixture_line + '                "[[ \\\"${NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256:-}\\\" =~ ^[0-9a-f]{64}$ ]] || exit 47\\n"\n', 1)
env_test_path.write_text(envtest)
