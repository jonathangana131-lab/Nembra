from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
BRIDGE = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
META_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataSecretRedactionSourceTests.swift")

FRAGMENTS = (
    "localkey", "sessionkey", "appkey", "appsecret", "password",
    "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey",
)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    duplicated = '''    private static let secretKeyFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
        "seckey",
    ]
'''
    canonical = '''    private static let secretKeyFragments = [
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
    APP.write_text(replace_once(app, duplicated, canonical, "deduplicate application classifier"), encoding="utf-8")

    bridge = BRIDGE.read_text(encoding="utf-8")
    old_bridge = '            let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "sessionkey", "seckey", "authkey"]\n'
    new_bridge = '            let secretKeyFragments = ["localkey", "sessionkey", "appkey", "appsecret", "password", "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey"]\n'
    BRIDGE.write_text(replace_once(bridge, old_bridge, new_bridge, "metadata classifier parity"), encoding="utf-8")

    test = META_TEST.read_text(encoding="utf-8")
    old_assertions = '''        #expect(body.contains("localkey"))
        #expect(body.contains("accesstoken"))
        #expect(body.contains("refreshtoken"))
        #expect(body.contains("sessionkey"))
        #expect(body.contains("authkey"))
        #expect(body.contains("seckey"))
'''
    new_assertions = '''        for fragment in [
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
        ] {
            #expect(body.contains("\\\"\\(fragment)\\\""), "Metadata sanitizer must redact export-promised credential key: \\(fragment)")
        }
'''
    META_TEST.write_text(replace_once(test, old_assertions, new_assertions, "metadata classifier regression"), encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    a0 = app.index("private static let secretKeyFragments = [", app.index("private final class SmartLifeDriver"))
    a1 = app.index("private static func redactApplicationSecrets", a0)
    classifier = app[a0:a1]
    bridge = BRIDGE.read_text(encoding="utf-8")
    b0 = bridge.index("private static func redactSecrets(_ object: Any) -> Any")
    b1 = bridge.index("private static func remoteMessage", b0)
    metadata = bridge[b0:b1]
    for fragment in FRAGMENTS:
        token = f'"{fragment}"'
        if classifier.count(token) != 1:
            raise SystemExit(f"application classifier must contain {fragment} exactly once")
        if metadata.count(token) != 1:
            raise SystemExit(f"metadata classifier must contain {fragment} exactly once")
    if "array.map(redactSecrets)" not in metadata:
        raise SystemExit("metadata recursive array redaction missing")
    test = META_TEST.read_text(encoding="utf-8")
    for fragment in FRAGMENTS:
        if f'"{fragment}"' not in test:
            raise SystemExit(f"metadata source regression missing {fragment}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
