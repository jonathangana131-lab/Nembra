#!/usr/bin/env python3
"""One-shot materializer for the Capture final-authority recovery child.

This script is intentionally deleted by its recovery workflow after it applies the
missing product provenance contract and repairs the exact-head regression oracles.
It must fail closed on any source-shape drift.
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def write(relative: str, source: str) -> None:
    (ROOT / relative).write_text(source, encoding="utf-8")


def replace_exact(relative: str, old: str, new: str, expected: int = 1) -> None:
    source = read(relative)
    actual = source.count(old)
    if actual != expected:
        raise SystemExit(
            f"{relative}: expected {expected} occurrence(s), found {actual}: {old[:120]!r}"
        )
    write(relative, source.replace(old, new, expected))


def materialize_private_provenance() -> None:
    identity = "NembraApp/App/NembraCaptureBuildIdentity.swift"
    replace_exact(
        identity,
        '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n',
        '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n'
        '    static let tuyaPrivateInputProvenanceSHA256InfoKey = "NembraCaptureTuyaPrivateInputProvenanceSHA256"\n',
    )
    replace_exact(
        identity,
        "    let tuyaDependencyLockSHA256: String\n",
        "    let tuyaDependencyLockSHA256: String\n"
        "    let tuyaPrivateInputProvenanceSHA256: String\n",
    )
    replace_exact(
        identity,
        '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n',
        '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n'
        '            tuyaPrivateInputProvenanceSHA256: ((infoDictionary[tuyaPrivateInputProvenanceSHA256InfoKey] as? String) ?? "").lowercased(),\n',
    )
    dependency_validation = (
        "              tuyaDependencyLockSHA256.count == 64,\n"
        "              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n"
        "                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n"
        "              }),\n"
    )
    replace_exact(
        identity,
        dependency_validation,
        dependency_validation
        + "              tuyaPrivateInputProvenanceSHA256.count == 64,\n"
        + "              tuyaPrivateInputProvenanceSHA256.utf8.allSatisfy({ byte in\n"
        + "                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n"
        + "              }),\n",
    )
    replace_exact(
        identity,
        "This build has no valid exact Git + reviewed Tuya dependency + canonical stationary procedure provenance.",
        "This build has no valid exact Git + reviewed Tuya dependency + independently accepted private-input + canonical stationary procedure provenance.",
    )

    project = "NembraCapture.xcodeproj/project.pbxproj"
    lock_setting = (
        'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = '
        '"$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";'
    )
    replace_exact(
        project,
        lock_setting,
        lock_setting
        + '\n\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaPrivateInputProvenanceSHA256 = '
        + '"$(NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256)";',
        expected=2,
    )

    entrypoint = "NembraApp/App/NembraCaptureEntrypoint.swift"
    replace_exact(
        entrypoint,
        "        let tuyaDependencyLockSHA256: String\n",
        "        let tuyaDependencyLockSHA256: String\n"
        "        let tuyaPrivateInputProvenanceSHA256: String\n",
    )
    replace_exact(
        entrypoint,
        "            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n",
        "            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n"
        "            tuyaPrivateInputProvenanceSHA256: buildIdentity.tuyaPrivateInputProvenanceSHA256,\n",
    )
    replace_exact(entrypoint, "            schemaVersion: 10,\n", "            schemaVersion: 11,\n")

    installer = "scripts/field/install_one_time_capture.command"
    replace_exact(
        installer,
        '        "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n',
        '        "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n'
        '        "NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256=$ACCEPTED_TUYA_PROVENANCE_SHA256" \\\n',
    )
    replace_exact(
        installer,
        'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n',
        'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
        'BUILT_TUYA_PRIVATE_PROVENANCE_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaPrivateInputProvenanceSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n',
    )
    replace_exact(
        installer,
        '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n',
        '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n'
        '[[ "$BUILT_TUYA_PRIVATE_PROVENANCE_SHA256" == "$ACCEPTED_TUYA_PROVENANCE_SHA256" ]] || die "Built Capture app private-input provenance does not match the independently accepted manifest SHA-256. Discard this candidate."\n',
    )
    replace_exact(
        installer,
        "unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST\n",
        "unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_TUYA_PRIVATE_PROVENANCE_SHA256 BUILT_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST\n",
    )
    replace_exact(
        installer,
        'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"',
        'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, independently accepted private-input provenance, canonical stationary procedure, and field product"',
    )


def migrate_source_contracts() -> None:
    changed_schema_files: list[str] = []
    tests_root = ROOT / "Packages/NembraBluetoothCapture/Tests"
    for path in tests_root.rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        if "schemaVersion: 10" not in source:
            continue
        migrated = source.replace("schemaVersion: 10", "schemaVersion: 11")
        migrated = migrated.replace("schemaVersion: 9", "schemaVersion: 10")
        path.write_text(migrated, encoding="utf-8")
        changed_schema_files.append(path.relative_to(ROOT).as_posix())
    if not changed_schema_files:
        raise SystemExit("no Capture schema-version source contracts were migrated")

    dependency_test = (
        "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
        "TuyaFieldDependencyProvenanceSourceTests.swift"
    )
    anchors = (
        (
            '#expect(installer.contains("NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256"))',
            '#expect(installer.contains("NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256=$ACCEPTED_TUYA_PROVENANCE_SHA256"))',
        ),
        (
            '#expect(installer.contains("BUILT_TUYA_DEPENDENCY_LOCK_SHA256\\\" == \\\"$TUYA_DEPENDENCY_LOCK_SHA256"))',
            '#expect(installer.contains("BUILT_TUYA_PRIVATE_PROVENANCE_SHA256\\\" == \\\"$ACCEPTED_TUYA_PROVENANCE_SHA256"))',
        ),
        (
            '#expect(app.contains("let tuyaDependencyLockSHA256: String"))',
            '#expect(app.contains("let tuyaPrivateInputProvenanceSHA256: String"))',
        ),
        (
            '#expect(app.contains("tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256"))',
            '#expect(app.contains("tuyaPrivateInputProvenanceSHA256: buildIdentity.tuyaPrivateInputProvenanceSHA256"))',
        ),
    )
    source = read(dependency_test)
    for old, new in anchors:
        if source.count(old) != 1:
            raise SystemExit(f"dependency source contract shape changed: {old}")
        source = source.replace(old, old + "\n        " + new, 1)
    write(dependency_test, source)

    field_workflow = ".github/workflows/capture-field-build-provenance.yml"
    workflow_anchors = (
        (
            "grep -Fq 'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = \"$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)\";' \"$project\"",
            "grep -Fq 'INFOPLIST_KEY_NembraCaptureTuyaPrivateInputProvenanceSHA256 = \"$(NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256)\";' \"$project\"",
        ),
        (
            "grep -Fq 'static let tuyaDependencyLockSHA256InfoKey = \"NembraCaptureTuyaDependencyLockSHA256\"' \"$identity\"",
            "grep -Fq 'static let tuyaPrivateInputProvenanceSHA256InfoKey = \"NembraCaptureTuyaPrivateInputProvenanceSHA256\"' \"$identity\"",
        ),
        (
            "grep -Fq 'tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256' \"$entrypoint\"",
            "grep -Fq 'tuyaPrivateInputProvenanceSHA256: buildIdentity.tuyaPrivateInputProvenanceSHA256' \"$entrypoint\"",
        ),
        (
            "grep -Fq '\"NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256\"' \"$installer\"",
            "grep -Fq '\"NEMBRA_CAPTURE_TUYA_PRIVATE_PROVENANCE_SHA256=$ACCEPTED_TUYA_PROVENANCE_SHA256\"' \"$installer\"",
        ),
        (
            "grep -Fq 'plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - \"$APP_INFO_PLIST\"' \"$installer\"",
            "grep -Fq 'plutil -extract NembraCaptureTuyaPrivateInputProvenanceSHA256 raw -o - \"$APP_INFO_PLIST\"' \"$installer\"",
        ),
        (
            "grep -Fq '[[ \"$BUILT_TUYA_DEPENDENCY_LOCK_SHA256\" == \"$TUYA_DEPENDENCY_LOCK_SHA256\" ]]' \"$installer\"",
            "grep -Fq '[[ \"$BUILT_TUYA_PRIVATE_PROVENANCE_SHA256\" == \"$ACCEPTED_TUYA_PROVENANCE_SHA256\" ]]' \"$installer\"",
        ),
    )
    source = read(field_workflow)
    for old, new in workflow_anchors:
        if source.count(old) != 1:
            raise SystemExit(f"field-build provenance workflow shape changed: {old}")
        source = source.replace(old, old + "\n          " + new, 1)
    write(field_workflow, source)


def repair_python39_dynamic_import_oracle() -> None:
    path = "scripts/ci/tests/test_capture_private_provenance_preacceptance.py"
    replace_exact(path, "import importlib.util\n", "import importlib.util\nimport sys\n")
    replace_exact(
        path,
        "    module = importlib.util.module_from_spec(spec)\n"
        "    spec.loader.exec_module(module)\n"
        "    return module\n",
        "    module = importlib.util.module_from_spec(spec)\n"
        "    # Python 3.9 dataclasses resolve the defining module through sys.modules.\n"
        "    # Register this dynamic module before execution just like normal import machinery.\n"
        "    sys.modules[spec.name] = module\n"
        "    spec.loader.exec_module(module)\n"
        "    return module\n",
    )


def repair_hostile_environment_oracles() -> None:
    # A DYLD injection variable cannot be supplied to the *new Bash interpreter*
    # that hosts the test harness: macOS dyld may kill Bash before Nembra's
    # wrapper exists. Set only that variable inside the live shell immediately
    # before the admitted tool call; the child tool must still observe it unset.
    dyld_entry = '                "DYLD_INSERT_LIBRARIES": "/tmp/attacker.dylib",\n'

    orchestrator_test = "scripts/ci/tests/test_capture_selected_xcode_build_orchestrator.py"
    replace_exact(orchestrator_test, dyld_entry, "")
    replace_exact(
        orchestrator_test,
        '+ function_source + "tool=\\\"$1\\\"\\nshift\\nrun_frozen_xcode_tool \\\"$tool\\\" \\\"$@\\\"\\n",',
        '+ function_source + "export DYLD_INSERT_LIBRARIES=/tmp/attacker.dylib\\n" '
        '+ "tool=\\\"$1\\\"\\nshift\\nrun_frozen_xcode_tool \\\"$tool\\\" \\\"$@\\\"\\n",',
    )

    handoff_test = "scripts/ci/tests/test_capture_frozen_device_tool_handoff.py"
    replace_exact(handoff_test, dyld_entry, "")
    replace_exact(
        handoff_test,
        '                + function_source\n'
        '                + "tool=\\\"$1\\\"\\nshift\\nrun_frozen_xcode_tool \\\"$tool\\\" \\\"$@\\\"\\n",\n',
        '                + function_source\n'
        '                + "export DYLD_INSERT_LIBRARIES=/tmp/attacker.dylib\\n"\n'
        '                + "tool=\\\"$1\\\"\\nshift\\nrun_frozen_xcode_tool \\\"$tool\\\" \\\"$@\\\"\\n",\n',
    )


def main() -> None:
    materialize_private_provenance()
    migrate_source_contracts()
    repair_python39_dynamic_import_oracle()
    repair_hostile_environment_oracles()
    print("Capture final-authority recovery materialized successfully.")


if __name__ == "__main__":
    main()
