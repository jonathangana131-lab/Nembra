from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationUpdateSecretRedactionSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    app = replace_once(
        app,
        '        "authkey",\n        "seckey",\n    ]\n',
        '        "authkey",\n        "seckey",\n        "sessionkey",\n    ]\n',
        "application secret fragment list",
    )
    APP.write_text(app, encoding="utf-8")

    test = TEST.read_text(encoding="utf-8")
    test = replace_once(
        test,
        '        #expect(driver.contains("seckey"))\n',
        '        #expect(driver.contains("seckey"))\n        #expect(driver.contains("sessionkey"))\n',
        "sessionkey source assertion",
    )
    old = '''        let updates = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(export.contains("secretsRedacted: true"))
        #expect(updates.contains("log(\\"tuya_application_update\\", update.merging(["))
'''
    new = '''        let prepareExport = String(try section(
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
        #expect(prepareExport.contains("session key"))
        #expect(updates.contains("log(\\"tuya_application_update\\", update.merging(["))
'''
    test = replace_once(test, old, new, "export/session-key coupling")
    TEST.write_text(test, encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    start = app.index("@MainActor\nprivate final class SmartLifeDriver")
    end = app.index("#endif\n\nprivate enum AppleAccountAuthorizationError", start)
    driver = app[start:end]
    required = [
        '"sessionkey"',
        "String(describing: Self.redactApplicationSecrets(value))",
        "onApplicationUpdate?(sanitized)",
    ]
    for token in required:
        if token not in driver:
            raise SystemExit(f"missing driver custody token: {token}")
    if driver.index("String(describing: Self.redactApplicationSecrets(value))") >= driver.index("onApplicationUpdate?(sanitized)"):
        raise SystemExit("redaction must precede controller callback")
    if "sanitized[String(describing: key)] = String(describing: value)" in driver:
        raise SystemExit("legacy unsanitized projection survived")

    test = TEST.read_text(encoding="utf-8")
    for token in (
        '#expect(driver.contains("sessionkey"))',
        '#expect(prepareExport.contains("session key"))',
    ):
        if token not in test:
            raise SystemExit(f"missing regression token: {token}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
