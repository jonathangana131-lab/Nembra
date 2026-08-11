#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = "a1f5a90414b5ca26bdd6bebb485189b6bcbe227f"
ISSUER = "scripts/ci/es80_authenticated_stationary_final_go.py"
MAIN_TEST = "scripts/ci/tests/test_es80_authenticated_stationary_final_go.py"
ENV_TEST = "scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py"
SIGNED_TEST = "scripts/ci/tests/test_es80_authenticated_stationary_signed_artifact.py"
SIGNED_DEVICE_TEST = "scripts/ci/tests/test_es80_authenticated_stationary_signed_artifact_device_custody.py"


def run(*args: str, capture: bool = False) -> str:
    p = subprocess.run(
        list(args), cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return p.stdout if capture else ""


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label} seam count={count}")
    return source.replace(old, new, 1)


issuer_path = ROOT / ISSUER
issuer = issuer_path.read_text()
issuer = replace_once(
    issuer,
    "import argparse, hashlib, importlib.util, json, os, pwd, re, stat, subprocess, sys, urllib.request, zipfile\n",
    "import argparse, hashlib, importlib.util, json, os, pwd, re, stat, subprocess, sys, tempfile, urllib.request, zipfile\n",
    "issuer import",
)
old_git = '''def git(repo:Path,*args):
    try:return subprocess.run(["/usr/bin/git","-C",str(repo),*args],check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env={"PATH":"/usr/bin:/bin"}).stdout.strip()
    except (OSError,subprocess.CalledProcessError) as e: raise GoError("candidate Git custody failed") from e
'''
new_git = '''def _git_environment()->dict[str,str]:
    return {"PATH":"/usr/bin:/bin","GIT_NO_REPLACE_OBJECTS":"1"}

def git(repo:Path,*args):
    try:return subprocess.run(["/usr/bin/git","-C",str(repo),*args],check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=_git_environment()).stdout.strip()
    except (OSError,subprocess.CalledProcessError) as e: raise GoError("candidate Git custody failed") from e

def git_bytes(repo:Path,*args)->bytes:
    try:return subprocess.run(["/usr/bin/git","-C",str(repo),*args],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=_git_environment()).stdout
    except (OSError,subprocess.CalledProcessError) as e: raise GoError("candidate Git byte custody failed") from e
'''
issuer = replace_once(issuer, old_git, new_git, "replacement-blind Git helper")
old_env_return = '    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest,"NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256":accepted_lock_sha256}\n'
new_env_return = '    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","GIT_NO_REPLACE_OBJECTS":"1","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest,"NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256":accepted_lock_sha256}\n'
issuer = replace_once(issuer, old_env_return, new_env_return, "closed installer Git replacement fence")
start = issuer.index("def installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha256:str):\n")
end = issuer.index("\ndef retained_signed_artifact(", start)
new_installer = '''def _accepted_installer_bytes(root:Path,source:str)->tuple[bytes,str]:
    accepted_blob=git(root,"rev-parse",f"{source}:{INSTALLER}").lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",accepted_blob): raise GoError("accepted installer Git blob invalid")
    raw=git_bytes(root,"cat-file","blob",accepted_blob)
    if not raw: raise GoError("accepted installer Git blob is empty")
    current=regular(root/INSTALLER,"candidate installer at execution boundary")
    if current!=raw: raise GoError("candidate installer bytes changed before private side effect")
    actual_blob=git(root,"hash-object","--no-filters","--",INSTALLER).lower()
    if actual_blob!=accepted_blob: raise GoError("candidate installer execution bytes differ from accepted Git blob")
    return raw,accepted_blob

def installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha256:str):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest,accepted_lock_sha256)
    raw,accepted_blob=_accepted_installer_bytes(root,source)
    pinned=None
    try:
        pinned=tempfile.TemporaryFile(mode="w+b",prefix="nembra-final-go-installer-")
        fd=pinned.fileno(); os.fchmod(fd,0o600)
        pinned.write(raw); pinned.flush(); os.fsync(fd); pinned.seek(0)
        pinned_bytes=pinned.read()
        if pinned_bytes!=raw: raise GoError("sealed installer bytes changed before execution")
        pinned.seek(0)
        st=os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.geteuid() or stat.S_IMODE(st.st_mode)!=0o600 or st.st_size!=len(raw): raise GoError("sealed installer descriptor custody invalid")
        fd_path=f"/dev/fd/{fd}"
        p=subprocess.run(
            ["/bin/bash","--noprofile","--norc","-p","-c",'source "$1" "$2"',str(root/INSTALLER),fd_path,source],
            cwd=root,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,pass_fds=(fd,),
        )
    except OSError as e: raise GoError("private installer execution failed") from e
    finally:
        if pinned is not None: pinned.close()
    if p.returncode or "SDK-INTEGRATED CAPTURE LAUNCHED" not in p.stdout or canon(git(root,"rev-parse","HEAD"),"post-install HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("private installer did not preserve exact accepted field subject")
    return {"authority":"accepted-candidate-private-installer-execution-v2","result":"success","sourceCommitSHA":source,"installerGitBlob":accepted_blob,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}
'''
issuer = issuer[:start] + new_installer + issuer[end:]
old_expected = 'expected={"authority":"accepted-candidate-private-installer-execution-v1","result":"success","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}\n'
new_expected = 'expected={"authority":"accepted-candidate-private-installer-execution-v2","result":"success","sourceCommitSHA":source,"installerGitBlob":cs["installerGitBlob"],"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}\n'
issuer = replace_once(issuer, old_expected, new_expected, "installer result authority")
issuer_path.write_text(issuer)

# Main adversarial suite: fixture authority version + Git replace-ref attack.
main_path = ROOT / MAIN_TEST
main = main_path.read_text()
main = main.replace("'authority':'accepted-candidate-private-installer-execution-v1'", "'authority':'accepted-candidate-private-installer-execution-v2'", 1)
main = replace_once(
    main,
    "'result':'success','sourceCommitSHA':s,'buildIdentifier':f'capture-v14-{s[:12]}'",
    "'result':'success','sourceCommitSHA':s,'installerGitBlob':go.git(self.repo,'rev-parse',f'{s}:{go.INSTALLER}').lower(),'buildIdentifier':f'capture-v14-{s[:12]}'",
    "fixture installer Git blob",
)
marker = " def test_candidate_dirty_and_retired_authority_rejected(self):\n"
replace_test = ''' def test_git_replace_refs_cannot_redefine_accepted_candidate_objects(self):
  original=self.f.s;installer=self.f.repo/go.INSTALLER
  installer.write_text(installer.read_text()+'# attacker replacement bytes\\n')
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'add',go.INSTALLER],check=True)
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'commit','-qm','attacker replacement'],check=True)
  attacker=subprocess.check_output(['/usr/bin/git','-C',str(self.f.repo),'rev-parse','HEAD'],text=True).strip()
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'replace',original,attacker],check=True)
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'reset','--hard',original],check=True,stdout=subprocess.DEVNULL)
  self.assertEqual(subprocess.check_output(['/usr/bin/git','-C',str(self.f.repo),'rev-parse','HEAD'],text=True).strip(),original)
  self.no(lambda:go.candidate(self.f.repo,original))

'''
if main.count(marker) != 1:
    raise SystemExit(f"replace-ref test marker count={main.count(marker)}")
main = main.replace(marker, replace_test + marker, 1)
main_path.write_text(main)

# Closed-environment suite proves $0/$1 preservation, replacement-blind env, and pre-launch pathname swap cannot execute attacker bytes.
env_path = ROOT / ENV_TEST
env_test = env_path.read_text()
env_test = replace_once(
    env_test,
    '                f"[[ \\\"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\\\" == {accepted_lock!r} ]] || exit 48\\n"\n',
    '                f"[[ \\\"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\\\" == {accepted_lock!r} ]] || exit 48\\n"\n'
    '                "[[ \\\"${GIT_NO_REPLACE_OBJECTS:-}\\\" == 1 ]] || exit 49\\n"\n'
    '                f"[[ \\\"$0\\\" == {str(installer)!r} ]] || exit 50\\n"\n'
    '                f"[[ \\\"${{1:-}}\\\" == {source!r} ]] || exit 51\\n"\n',
    "sealed installer shell identity assertions",
)
env_test = replace_once(
    env_test,
    '            self.assertEqual(env["ENV"], "/dev/null")\n',
    '            self.assertEqual(env["ENV"], "/dev/null")\n            self.assertEqual(env["GIT_NO_REPLACE_OBJECTS"], "1")\n',
    "closed Git environment assertion",
)
marker = "    def test_installer_environment_is_explicit_allowlist(self) -> None:\n"
race_test = '''    def test_checkout_path_swap_before_bash_launch_cannot_change_executed_bytes(self) -> None:
        from unittest import mock
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-execution-subject-") as temporary:
            root = Path(temporary).resolve(strict=True)
            repository = root / "candidate"
            repository.mkdir()
            subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"], check=True)
            installer = repository / GO.INSTALLER
            installer.parent.mkdir(parents=True, exist_ok=True)
            installer.write_text("#!/bin/bash\\nset -euo pipefail\\nprintf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'\\n", encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(repository), "add", "."], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(repository), "commit", "-qm", "fixture"], check=True)
            source = subprocess.check_output(["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
            device = root / "device"; device.write_text("device-token", encoding="utf-8"); device.chmod(0o600)
            sentinel = root / "attacker-ran"
            real_run = subprocess.run
            swapped = False
            def intercept(args, **kwargs):
                nonlocal swapped
                if args and args[0] == "/bin/bash" and not swapped:
                    swapped = True
                    installer.write_text(f"#!/bin/bash\\ntouch {str(sentinel)!r}\\nprintf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'\\n", encoding="utf-8")
                return real_run(args, **kwargs)
            with mock.patch.object(GO.subprocess, "run", side_effect=intercept):
                with self.assertRaises(GO.GoError):
                    GO.installer(repository, source, device, GO.device_hash(device), "e" * 64)
            self.assertTrue(swapped, "test did not reach the private Bash side-effect boundary")
            self.assertFalse(sentinel.exists(), "mutable checkout pathname bytes executed instead of the sealed accepted installer")

'''
if env_test.count(marker) != 1:
    raise SystemExit(f"execution-subject race test marker count={env_test.count(marker)}")
env_test = env_test.replace(marker, race_test + marker, 1)
env_path.write_text(env_test)

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
for path in (ISSUER, MAIN_TEST, ENV_TEST):
    compile((ROOT / path).read_text(), path, "exec")
run("python3", "-B", MAIN_TEST)
run("python3", "-B", ENV_TEST)
run("python3", "-B", SIGNED_TEST)
run("python3", "-B", SIGNED_DEVICE_TEST)
if any(ROOT.glob("scripts/ci/**/__pycache__")):
    raise SystemExit("validation created Python bytecode residue")
changed = sorted(
    p for p in run("git", "diff", "--name-only", BASE, capture=True).splitlines()
    if p != "scripts/ci/tmp_v14_seal_installer_execution_subject.py"
    and not p.startswith(".github/workflows/tmp-v14-seal-installer-execution-subject")
)
expected = sorted([ISSUER, MAIN_TEST, ENV_TEST])
if changed != expected:
    raise SystemExit(f"unexpected product scope: {changed!r}")
print("sealed installer execution-subject and replacement-blind Git custody validated")
