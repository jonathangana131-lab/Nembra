#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")
old = '''    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
        "seckey",
    ]
'''
new = '''    private static let secretKeyFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]
'''
if source.count(old) != 1:
    raise SystemExit(f"expected one current application secret classifier, found {source.count(old)}")
source = source.replace(old, new, 1)
path.write_text(source, encoding="utf-8")

start = source.index("@MainActor\nprivate final class SmartLifeDriver")
end = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", start)
driver = source[start:end]
for fragment in (
    "localkey", "sessionkey", "appkey", "appsecret", "password",
    "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey",
):
    if f'"{fragment}"' not in driver:
        raise SystemExit(f"application secret classifier missing export-promised fragment: {fragment}")
if "String(describing: Self.redactApplicationSecrets(value))" not in driver:
    raise SystemExit("nested application values must still pass through recursive sanitizer before String(describing:)")
if "onApplicationUpdate?(sanitized)" not in driver:
    raise SystemExit("sanitized application dictionary must remain the only callback admission")
if "No account UID, AppKey/AppSecret, password, account token, local_key, session key" not in source:
    raise SystemExit("export promise anchor changed; review classifier contract before proceeding")
for forbidden in ("publishDps", "queryDps", "writeValue"):
    if forbidden in driver:
        raise SystemExit(f"secret-custody lane gained forbidden protocol authority: {forbidden}")
print("application-update export secret promise: PASS")
