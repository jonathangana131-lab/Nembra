from pathlib import Path

SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = SOURCE.read_text()

promise = "No account UID, AppKey/AppSecret, password, account token, local_key, session key"
if promise not in text:
    raise SystemExit("accepted export secret promise not found")

old = '''    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]'''
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
    ]'''

if text.count(old) != 1:
    raise SystemExit(f"expected exactly one narrow credential classifier, found {text.count(old)}")

for fragment in ("sessionkey", "appkey", "appsecret", "password", "accounttoken"):
    if f'"{fragment}"' in text[text.index("private final class SmartLifeDriver"):text.index("private enum AppleAccountAuthorizationError")]:
        raise SystemExit(f"repair fragment already present before materialization: {fragment}")

text = text.replace(old, new, 1)
SOURCE.write_text(text)

updated = SOURCE.read_text()
driver = updated[updated.index("private final class SmartLifeDriver"):updated.index("private enum AppleAccountAuthorizationError")]
for fragment in (
    "localkey", "sessionkey", "appkey", "appsecret", "password", "accounttoken",
    "accesstoken", "refreshtoken", "authkey", "seckey",
):
    if f'"{fragment}"' not in driver:
        raise SystemExit(f"redaction fragment missing after materialization: {fragment}")

if "String(describing: Self.redactApplicationSecrets(value))" not in driver:
    raise SystemExit("recursive application sanitizer missing")
if "onApplicationUpdate?(sanitized)" not in driver:
    raise SystemExit("single sanitized callback boundary missing")

print("materialized export-promised application secret redaction")
