from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
BRIDGE = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
APP_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationUpdateSecretRedactionSourceTests.swift")
BRIDGE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataSecretRedactionSourceTests.swift")

FRAGMENTS = (
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
)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    old_app_list = '''    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
        "seckey",
    ]
'''
    new_app_list = '''    private static let secretKeyFragments = [
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
    APP.write_text(replace_once(app, old_app_list, new_app_list, "application classifier"), encoding="utf-8")

    bridge = BRIDGE.read_text(encoding="utf-8")
    old_bridge_list = '            let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "sessionkey", "seckey", "authkey"]\n'
    new_bridge_list = '            let secretKeyFragments = ["localkey", "sessionkey", "appkey", "appsecret", "password", "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey"]\n'
    BRIDGE.write_text(replace_once(bridge, old_bridge_list, new_bridge_list, "metadata classifier"), encoding="utf-8")

    app_test = APP_TEST.read_text(encoding="utf-8")
    old_assertions = '''        #expect(driver.contains("localkey"))
        #expect(driver.contains("accesstoken"))
        #expect(driver.contains("refreshtoken"))
        #expect(driver.contains("sessionkey"))
        #expect(driver.contains("authkey"))
        #expect(driver.contains("seckey"))
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
            #expect(driver.contains("\\\"\\(fragment)\\\""), "Application sanitizer must redact export-promised credential key: \\(fragment)")
        }
'''
    app_test = replace_once(app_test, old_assertions, new_assertions, "application classifier regression")
    old_export = '''        let updates = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(export.contains("secretsRedacted: true"))
        #expect(updates.contains("log(\\\"tuya_application_update\\\", update.merging(["))
        #expect(source.contains("No account UID, AppKey/AppSecret, password, account token, local_key, session key"))
'''
    new_export = '''        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))
        let updates = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(export.contains("secretsRedacted: true"))
        #expect(prepareExport.contains("No account UID, AppKey/AppSecret, password, account token, local_key, session key"))
        #expect(updates.contains("log(\\\"tuya_application_update\\\", update.merging(["))
'''
    APP_TEST.write_text(replace_once(app_test, old_export, new_export, "application export-promise coupling"), encoding="utf-8")

    bridge_test = BRIDGE_TEST.read_text(encoding="utf-8")
    old_bridge_assertions = '''        #expect(body.contains("localkey"))
        #expect(body.contains("accesstoken"))
        #expect(body.contains("refreshtoken"))
        #expect(body.contains("sessionkey"))
        #expect(body.contains("authkey"))
        #expect(body.contains("seckey"))
'''
    new_bridge_assertions = '''        for fragment in [
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
    BRIDGE_TEST.write_text(replace_once(bridge_test, old_bridge_assertions, new_bridge_assertions, "metadata classifier regression"), encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    a = app.index("@MainActor\nprivate final class SmartLifeDriver")
    b = app.index("#endif\n\nprivate enum AppleAccountAuthorizationError", a)
    driver = app[a:b]
    bridge = BRIDGE.read_text(encoding="utf-8")
    r0 = bridge.index("private static func redactSecrets(_ object: Any) -> Any")
    r1 = bridge.index("private static func remoteMessage", r0)
    metadata = bridge[r0:r1]
    for fragment in FRAGMENTS:
        token = f'"{fragment}"'
        if token not in driver:
            raise SystemExit(f"application classifier missing {fragment}")
        if token not in metadata:
            raise SystemExit(f"metadata classifier missing {fragment}")
    if driver.index("String(describing: Self.redactApplicationSecrets(value))") >= driver.index("onApplicationUpdate?(sanitized)"):
        raise SystemExit("application recursive redaction must precede controller callback")
    if "array.map(redactApplicationSecrets)" not in driver or "array.map(redactSecrets)" not in metadata:
        raise SystemExit("recursive array redaction missing")
    if "sanitized[String(describing: key)] = String(describing: value)" in driver:
        raise SystemExit("legacy unsanitized projection survived")

    app_test = APP_TEST.read_text(encoding="utf-8")
    bridge_test = BRIDGE_TEST.read_text(encoding="utf-8")
    for fragment in FRAGMENTS:
        if f'"{fragment}"' not in app_test:
            raise SystemExit(f"application regression missing {fragment}")
        if f'"{fragment}"' not in bridge_test:
            raise SystemExit(f"metadata regression missing {fragment}")
    if "prepareExport.contains" not in app_test or "AppKey/AppSecret, password, account token, local_key, session key" not in app_test:
        raise SystemExit("application regression no longer pins accepted-export secret promise")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
