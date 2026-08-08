#!/usr/bin/env python3
"""Fail-closed verification for one exact signed Nembra iOS field-build candidate.

Produces candidate evidence only. It never authorizes physical ES80 Experiment One.
"""
from __future__ import annotations

import argparse, hashlib, json, os, plistlib, re, shutil, subprocess, sys, tempfile, uuid, zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Callable

SCHEMA_VERSION = 1
STATUS = "candidate-only-no-go"
PLATFORM = "ios-device"
RECIPE_ID = "ES80-FINGERPRINT-v1"
PROCEDURE_VERSION = "V14"
EXPECTED_BUNDLE_ID = "com.jonathangana131.nembra"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
TEAM = re.compile(r"^[A-Z0-9]{10}$")
CDHASH = re.compile(r"^[0-9a-fA-F]{40,64}$")

class VerificationError(RuntimeError): pass

@dataclass(frozen=True)
class EmbeddedBuildIdentity:
    build_identifier: str
    build_instance_id: str
    source_commit_sha: str
    bundle_identifier: str
    executable_name: str

@dataclass(frozen=True)
class SigningEvidence:
    team_identifier: str
    code_directory_hash: str
    provisioning_profile_uuid: str
    provisioning_profile_expiration_utc: str

@dataclass(frozen=True)
class CandidateEvidence:
    identity: EmbeddedBuildIdentity
    signing: SigningEvidence
    ipa_sha256: str
    executable_sha256: str
    info_plist_sha256: str
    executable_bytes: bytes
    info_plist_bytes: bytes

def sha_bytes(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def sha_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()

def require_sha40(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA40.fullmatch(value):
        raise VerificationError(f"{label} must be one exact lowercase 40-hex Git SHA")
    return value

def require_uuid(value: object, label: str) -> str:
    if not isinstance(value, str) or value != value.strip() or any(ord(c) < 32 for c in value):
        raise VerificationError(f"{label} must be unpadded canonical lowercase UUID text")
    try: canonical = str(uuid.UUID(value))
    except (ValueError, AttributeError) as exc: raise VerificationError(f"{label} must be one canonical UUID") from exc
    if value != canonical: raise VerificationError(f"{label} must be canonical lowercase UUID text")
    return value

def require_build_id(value: object) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or len(value) > 160:
        raise VerificationError("NembraCaptureBuildIdentifier is blank, padded, or oversized")
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise VerificationError("NembraCaptureBuildIdentifier contains control characters")
    return value

def safe_member(name: str) -> PurePosixPath:
    p = PurePosixPath(name)
    if p.is_absolute() or ".." in p.parts or not p.parts:
        raise VerificationError(f"IPA contains unsafe archive path: {name!r}")
    return p

def reject_symlink(info: zipfile.ZipInfo) -> None:
    mode = (info.external_attr >> 16) & 0xFFFF
    if (mode & 0o170000) == 0o120000:
        raise VerificationError(f"IPA contains unsupported symlink entry: {info.filename}")

def inspect_members(z: zipfile.ZipFile):
    files = [i for i in z.infolist() if not i.is_dir()]
    names = []
    for info in files:
        names.append(str(safe_member(info.filename))); reject_symlink(info)
    plists = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
    if len(plists) != 1: raise VerificationError("IPA must contain exactly one Payload/<app>.app/Info.plist")
    info_name = plists[0]; prefix = info_name[:-len("Info.plist")]
    info_bytes = z.read(info_name)
    try: plist = plistlib.loads(info_bytes)
    except Exception as exc: raise VerificationError("IPA Info.plist is not a valid plist") from exc
    if not isinstance(plist, dict): raise VerificationError("IPA Info.plist root must be a dictionary")
    exe = plist.get("CFBundleExecutable")
    if not isinstance(exe, str) or not exe or "/" in exe: raise VerificationError("CFBundleExecutable is missing or invalid")
    exe_member = f"{prefix}{exe}"
    if exe_member not in names: raise VerificationError("IPA does not contain the executable named by CFBundleExecutable")
    bundle = plist.get("CFBundleIdentifier")
    if bundle != EXPECTED_BUNDLE_ID: raise VerificationError(f"Field candidate bundle identifier must be {EXPECTED_BUNDLE_ID!r}; got {bundle!r}")
    identity = EmbeddedBuildIdentity(
        require_build_id(plist.get("NembraCaptureBuildIdentifier")),
        require_uuid(plist.get("NembraCaptureBuildInstanceID"), "NembraCaptureBuildInstanceID"),
        require_sha40(plist.get("NembraCaptureBuildCommitSHA"), "NembraCaptureBuildCommitSHA"),
        bundle, exe,
    )
    return prefix.rstrip("/"), info_bytes, z.read(exe_member), identity

def extract_safe(z: zipfile.ZipFile, root: Path) -> None:
    for info in z.infolist():
        p = safe_member(info.filename); reject_symlink(info)
        dest = root.joinpath(*p.parts)
        if info.is_dir(): dest.mkdir(parents=True, exist_ok=True); continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        with z.open(info) as src, dest.open("wb") as dst: shutil.copyfileobj(src, dst)
        perms = ((info.external_attr >> 16) & 0xFFFF) & 0o777
        if perms: os.chmod(dest, perms)

def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise VerificationError(f"Command failed ({' '.join(cmd)}): {(result.stderr or result.stdout).strip()}")
    return result

def probe_signing(app: Path, bundle: str) -> SigningEvidence:
    if sys.platform != "darwin" or not Path("/usr/bin/codesign").exists() or not Path("/usr/bin/security").exists():
        raise VerificationError("codesign/provisioning verification requires macOS Apple signing tools")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    detail = run(["/usr/bin/codesign", "-d", "--verbose=4", str(app)])
    text = f"{detail.stdout}\n{detail.stderr}"
    if "Signature=adhoc" in text: raise VerificationError("Ad-hoc signatures cannot become a physical field-build candidate")
    tm = re.search(r"^TeamIdentifier=([^\r\n]+)$", text, re.MULTILINE); cm = re.search(r"^CDHash=([^\r\n]+)$", text, re.MULTILINE)
    if not tm or not cm: raise VerificationError("codesign output is missing TeamIdentifier or CDHash")
    team, cdhash = tm.group(1).strip(), cm.group(1).strip().lower()
    if not TEAM.fullmatch(team) or not CDHASH.fullmatch(cdhash): raise VerificationError("codesign identity is malformed")
    profile_path = app / "embedded.mobileprovision"
    if not profile_path.is_file(): raise VerificationError("Signed field candidate is missing embedded.mobileprovision")
    decoded = run(["/usr/bin/security", "cms", "-D", "-i", str(profile_path)]).stdout.encode()
    try: profile = plistlib.loads(decoded)
    except Exception as exc: raise VerificationError("Could not decode embedded provisioning profile") from exc
    if not isinstance(profile, dict) or not isinstance(profile.get("TeamIdentifier"), list) or team not in profile["TeamIdentifier"]:
        raise VerificationError("Provisioning profile TeamIdentifier does not match the code signature")
    profile_uuid = profile.get("UUID"); expiration = profile.get("ExpirationDate"); entitlements = profile.get("Entitlements")
    if not isinstance(profile_uuid, str) or not profile_uuid: raise VerificationError("Provisioning profile UUID is missing")
    if not isinstance(expiration, datetime): raise VerificationError("Provisioning profile ExpirationDate is missing")
    expiration = expiration.astimezone(timezone.utc)
    if expiration <= datetime.now(timezone.utc): raise VerificationError("Provisioning profile is expired")
    if not isinstance(entitlements, dict) or entitlements.get("application-identifier") != f"{team}.{bundle}":
        raise VerificationError("Provisioning profile application-identifier does not match the signed Nembra bundle")
    return SigningEvidence(team, cdhash, profile_uuid, expiration.isoformat().replace("+00:00", "Z"))

def inspect_candidate(ipa: Path, expected_sha: str, *, signing_probe: Callable[[Path, str], SigningEvidence] = probe_signing) -> CandidateEvidence:
    expected_sha = require_sha40(expected_sha, "exact repository HEAD")
    if not ipa.is_file() or ipa.suffix.lower() != ".ipa": raise VerificationError("--ipa must name one existing .ipa file")
    try:
        with zipfile.ZipFile(ipa) as z:
            prefix, info_bytes, exe_bytes, identity = inspect_members(z)
            if identity.source_commit_sha != expected_sha: raise VerificationError("Embedded NembraCaptureBuildCommitSHA does not equal the exact repository HEAD")
            with tempfile.TemporaryDirectory(prefix="nembra-field-candidate-") as tmp:
                root = Path(tmp); extract_safe(z, root); app = root.joinpath(*PurePosixPath(prefix).parts)
                if not app.is_dir(): raise VerificationError("Extracted Nembra .app bundle is missing")
                signing = signing_probe(app, identity.bundle_identifier)
    except zipfile.BadZipFile as exc: raise VerificationError("IPA is not a valid ZIP archive") from exc
    return CandidateEvidence(identity, signing, sha_file(ipa), sha_bytes(exe_bytes), sha_bytes(info_bytes), exe_bytes, info_bytes)

def build_record(e: CandidateEvidence) -> dict[str, object]:
    return {
        "schemaVersion": SCHEMA_VERSION, "status": STATUS, "platform": PLATFORM,
        "buildIdentifier": e.identity.build_identifier, "buildInstanceID": e.identity.build_instance_id,
        "sourceCommitSHA": e.identity.source_commit_sha, "bundleIdentifier": e.identity.bundle_identifier,
        "teamIdentifier": e.signing.team_identifier, "ipaSHA256": e.ipa_sha256,
        "executableSHA256": e.executable_sha256, "infoPlistSHA256": e.info_plist_sha256,
        "codeDirectoryHash": e.signing.code_directory_hash, "provisioningProfileUUID": e.signing.provisioning_profile_uuid,
        "provisioningProfileExpirationUTC": e.signing.provisioning_profile_expiration_utc,
        "experimentRecipeID": RECIPE_ID, "procedureVersion": PROCEDURE_VERSION,
    }

def exact_head(root: Path) -> str: return require_sha40(run(["git", "rev-parse", "--verify", "HEAD^{commit}"], root).stdout.strip(), "repository HEAD")
def require_pristine(root: Path) -> None:
    if run(["git", "status", "--porcelain=v1", "--untracked-files=all"], root).stdout:
        raise VerificationError("Field candidate verification refuses tracked or non-ignored untracked repository inputs")

def retain_candidate(ipa: Path, out: Path, e: CandidateEvidence) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    retained_ipa, retained_exe, retained_info = out/"Nembra-Field-Candidate.ipa", out/"Nembra", out/"Info.plist"
    record, boundary = out/"NembraCaptureFieldBuildCandidateRecord.json", out/"PHYSICAL_NO_GO.txt"
    shutil.copyfile(ipa, retained_ipa); retained_exe.write_bytes(e.executable_bytes); retained_info.write_bytes(e.info_plist_bytes)
    if (sha_file(retained_ipa), sha_file(retained_exe), sha_file(retained_info)) != (e.ipa_sha256, e.executable_sha256, e.info_plist_sha256):
        raise VerificationError("Retained signed-candidate bytes diverged from inspected evidence")
    record.write_text(json.dumps(build_record(e), indent=2, sort_keys=True)+"\n")
    boundary.write_text("PHYSICAL EXPERIMENT ONE: NO-GO.\nSigned-device field-build CANDIDATE evidence only. Not independent acceptance, not a GO record, and not authorization to run the ES80 procedure.\n")
    return record

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__); p.add_argument("--ipa", required=True, type=Path); p.add_argument("--output-dir", type=Path, default=Path("Artifacts/ES80FieldCandidate")); a = p.parse_args(argv)
    root = Path(__file__).resolve().parents[2]
    try:
        require_pristine(root); head = exact_head(root); evidence = inspect_candidate(a.ipa.resolve(), head); record = retain_candidate(a.ipa.resolve(), a.output_dir.resolve(), evidence)
    except VerificationError as exc:
        print(f"ES80 field candidate verification FAILED: {exc}", file=sys.stderr); return 2
    print(f"Verified signed iOS field-build CANDIDATE for exact source {head}\nCandidate record: {record}\nPHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN."); return 0

if __name__ == "__main__": raise SystemExit(main())
