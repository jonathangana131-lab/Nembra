#!/usr/bin/env python3
from pathlib import Path

ISSUER = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
TESTS = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


source = ISSUER.read_text(encoding="utf-8")
source = replace_once(
    source,
    "import argparse, hashlib, importlib.util, json, os, pwd, re, stat, subprocess, sys, urllib.request, zipfile\n",
    "import argparse, hashlib, importlib.util, json, os, pwd, re, stat, subprocess, sys, threading, urllib.request, zipfile\n",
    "issuer imports",
)

old = '''def installer(repo:Path,source:str,device:Path):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device)
    try:p=subprocess.run(["/bin/bash","--noprofile","--norc","-p",str(root/INSTALLER),source],cwd=root,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    except OSError as e: raise GoError("private installer execution failed") from e
    if p.returncode or "SDK-INTEGRATED CAPTURE LAUNCHED" not in p.stdout or canon(git(root,"rev-parse","HEAD"),"post-install HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("private installer did not preserve exact accepted field subject")
    return {"authority":"accepted-candidate-private-installer-execution-v1","result":"success","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}
'''
new = '''def accepted_installer_blob(root:Path,source:str)->bytes:
    expected=git(root,"rev-parse",f"{source}:{INSTALLER}").lower()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",expected): raise GoError("accepted installer Git blob invalid")
    try:
        result=subprocess.run(["/usr/bin/git","-C",str(root),"cat-file","blob",f"{source}:{INSTALLER}"],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env={"PATH":"/usr/bin:/bin"})
    except (OSError,subprocess.CalledProcessError) as e: raise GoError("accepted installer Git blob unavailable") from e
    raw=result.stdout
    prefix=b"blob "+str(len(raw)).encode()+b"\\0"
    actual=(hashlib.sha1(prefix+raw).hexdigest() if len(expected)==40 else hashlib.sha256(prefix+raw).hexdigest())
    if actual!=expected: raise GoError("accepted installer Git blob bytes do not match object identity")
    return raw

def installer(repo:Path,source:str,device:Path):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device); raw=accepted_installer_blob(root,source)
    read_fd,write_fd=os.pipe(); delivery={"sent":0,"error":None}
    def feed()->None:
        try:
            view=memoryview(raw)
            while view:
                written=os.write(write_fd,view)
                delivery["sent"]+=written; view=view[written:]
        except OSError as error:
            delivery["error"]=error
        finally:
            try: os.close(write_fd)
            except OSError: pass
    feeder=threading.Thread(target=feed,name="nembra-final-go-installer-blob",daemon=True); feeder.start()
    try:
        command=f'source /dev/fd/{read_fd} "$1"'
        p=subprocess.run(["/bin/bash","--noprofile","--norc","-p","-c",command,str(root/INSTALLER),source],cwd=root,env=env,stdin=subprocess.DEVNULL,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,pass_fds=(read_fd,))
    except OSError as e:
        raise GoError("private installer execution failed") from e
    finally:
        try: os.close(read_fd)
        except OSError: pass
        feeder.join()
    if p.returncode==0 and (delivery["error"] is not None or delivery["sent"]!=len(raw)): raise GoError("accepted installer bytes were not fully delivered")
    if p.returncode or "SDK-INTEGRATED CAPTURE LAUNCHED" not in p.stdout or canon(git(root,"rev-parse","HEAD"),"post-install HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("private installer did not preserve exact accepted field subject")
    return {"authority":"accepted-candidate-private-installer-execution-v1","result":"success","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}
'''
source = replace_once(source, old, new, "installer execution boundary")
ISSUER.write_text(source, encoding="utf-8")

tests = TESTS.read_text(encoding="utf-8")
tests = replace_once(
    tests,
    "import os\nimport subprocess\n",
    "import os\nimport shlex\nimport subprocess\n",
    "test imports",
)

regression = '''\n    def test_verified_installer_cannot_be_replaced_only_for_execution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-installer-subject-") as temporary:
            root = Path(temporary).resolve(strict=True)
            repository = root / "candidate"
            repository.mkdir()
            subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"], check=True)

            installer = repository / GO.INSTALLER
            runbook = repository / GO.RUNBOOK
            identity = repository / GO.IDENTITY
            installer.parent.mkdir(parents=True, exist_ok=True)
            runbook.parent.mkdir(parents=True, exist_ok=True)
            identity.parent.mkdir(parents=True, exist_ok=True)
            accepted_installer = (
                "#!/bin/bash\\n"
                "set -euo pipefail\\n"
                f'PROCEDURE_ID="{GO.PROC}"\\n'
                f'BUNDLE_ID="{GO.BUNDLE}"\\n'
                "printf '%s\\n' 'accepted installer executed'\\n"
                "exit 97\\n"
            )
            installer.write_text(accepted_installer, encoding="utf-8")
            installer.chmod(0o755)
            runbook.write_text(f"PROCEDURE_ID: `{GO.PROC}`\\n", encoding="utf-8")
            identity.write_text(
                f'static let requiredFieldProcedureIdentifier = "{GO.PROC}"\\n',
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(repository), "add", "."], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(repository), "commit", "-qm", "accepted candidate"], check=True)
            source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"], text=True
            ).strip()
            accepted = GO.candidate(repository, source)
            self.assertEqual(accepted["sourceCommitSHA"], source)

            backup = root / "accepted-installer.command"
            backup.write_text(accepted_installer, encoding="utf-8")
            backup.chmod(0o755)
            sentinel = root / "malicious-installer-executed"
            malicious = (
                "#!/bin/bash\\n"
                "set -euo pipefail\\n"
                f"trap '/bin/cp {shlex.quote(str(backup))} \\\"$0\\\"; /bin/chmod 755 \\\"$0\\\"' EXIT\\n"
                f"printf '%s\\n' 'executed' > {shlex.quote(str(sentinel))}\\n"
                "printf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'\\n"
            )
            installer.write_text(malicious, encoding="utf-8")
            installer.chmod(0o755)

            private_device = root / "intended-device"
            private_device.write_text("00008101-001234567890001E", encoding="utf-8")
            private_device.chmod(0o600)

            with self.assertRaises(GO.GoError):
                GO.installer(repository, source, private_device)
            self.assertFalse(
                sentinel.exists(),
                "Final-GO executed a pathname-swapped installer instead of the exact accepted Git blob bytes",
            )
\n'''
marker = '\n\nif __name__ == "__main__":\n    unittest.main(verbosity=2)\n'
if marker not in tests:
    raise SystemExit("test insertion marker missing")
tests = tests.replace(marker, regression + marker, 1)
TESTS.write_text(tests, encoding="utf-8")
