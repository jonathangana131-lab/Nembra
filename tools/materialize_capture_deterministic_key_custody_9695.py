#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")


def replace_exact(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    source = source.replace(old, new, 1)


replace_exact(
    "        for (key, value) in dps {\n",
    "        for (key, value) in Self.sortedApplicationEntries(dps) {\n",
    "top-level SDK application dictionary traversal",
)
replace_exact(
    "            for (key, value) in dictionary {\n",
    "            for (key, value) in sortedApplicationEntries(dictionary) {\n",
    "nested SDK application dictionary traversal",
)

marker = "    private static let secretKeyFragments = [\n"
helper = '''    // Assign collision suffixes only after traversing the original SDK keys in a
    // deterministic order. Otherwise Dictionary hash order can decide which admitted
    // evidence value receives the base redacted key versus #2/#3. Tuya application
    // dictionaries use scalar AnyHashable keys; spelling, concrete scalar type, then
    // scalar reflection provide a stable pre-redaction identity for that bounded input.
    private static func sortedApplicationEntries(
        _ dictionary: [AnyHashable: Any]
    ) -> [(key: AnyHashable, value: Any)] {
        dictionary.sorted { left, right in
            let leftDescription = String(describing: left.key)
            let rightDescription = String(describing: right.key)
            if leftDescription != rightDescription {
                return leftDescription < rightDescription
            }

            let leftType = String(reflecting: type(of: left.key.base))
            let rightType = String(reflecting: type(of: right.key.base))
            if leftType != rightType {
                return leftType < rightType
            }

            return String(reflecting: left.key.base) < String(reflecting: right.key.base)
        }
    }

'''
replace_exact(marker, helper + marker, "application key ordering helper insertion")

start = source.index("@MainActor\nprivate final class SmartLifeDriver")
end = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", start)
driver = source[start:end]
assert driver.count("for (key, value) in Self.sortedApplicationEntries(dps)") == 1
assert driver.count("for (key, value) in sortedApplicationEntries(dictionary)") == 1
assert "for (key, value) in dps {" not in driver
assert "for (key, value) in dictionary {" not in driver
assert "String(describing: left.key)" in driver
assert "String(reflecting: type(of: left.key.base))" in driver
assert "String(reflecting: left.key.base)" in driver
assert "Set([NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret])" in driver
assert "left.count > right.count" in driver
assert "redactedApplicationDescription(value)" in driver

path.write_text(source, encoding="utf-8")
