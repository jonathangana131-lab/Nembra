#!/usr/bin/env python3
"""Ephemeral Xcode graph probe for the Dashboard NembraCore package boundary.

This script is validation-only. It rewrites the checked-out runner workspace so the
Nembra app consumes the local NembraCore Swift package product instead of compiling
the legacy hand-picked NembraCore source files directly. It also imports NembraCore
from app/test Swift files so Xcode can expose the real module-boundary/API failures.

No generated project or Swift source is intended to be committed as product output.
"""
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "Nembra.xcodeproj/project.pbxproj"

PACKAGE_BUILD_FILE = "DA5B00000000000000000001"
PACKAGE_REFERENCE = "DA5B00000000000000000002"
PACKAGE_PRODUCT = "DA5B00000000000000000003"

DIRECT_CORE_BUILD_IDS = (
    "A00000000000000000000007",  # VehicleDomain
    "A00000000000000000000008",  # ScooterService
    "A00000000000000000000009",  # SimulatedScooterService
    "A0000000000000000000000F",  # SpeedTelemetry
    "A00000000000000000000010",  # TelemetryBenchmark
    "A00000000000000000000011",  # UnverifiedScooterService
    "A00000000000000000000021",  # SpeedDisplayInterpolation
    "A00000000000000000000022",  # RollingNumberModel
    "A00000000000000000000023",  # SimulationConfiguration
    "A00000000000000000000024",  # RideEngine
    "A00000000000000000000025",  # RideCheckpointPersistence
    "A00000000000000000000026",  # RideCheckpointCoordinator
    "A00000000000000000000027",  # RideHistoryCommit
    "A00000000000000000000028",  # RideDistanceReconciliation
    "A00000000000000000000029",  # LiveDistanceIntegration
    "A00000000000000000000039",  # RideLocationEvidence
)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"probe expected exactly one {label}, found {count}")
    return text.replace(old, new, 1)


def patch_project() -> None:
    text = PROJECT.read_text(encoding="utf-8")

    build_marker = "/* Begin PBXBuildFile section */\n"
    text = replace_once(
        text,
        build_marker,
        build_marker
        + f"\t\t{PACKAGE_BUILD_FILE} /* NembraCore in Frameworks */ = "
          f"{{isa = PBXBuildFile; productRef = {PACKAGE_PRODUCT} /* NembraCore */; }};\n",
        "PBXBuildFile section marker",
    )

    app_frameworks = (
        "\t\tF00000000000000000000001 = "
        "{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; "
        "files = (); runOnlyForDeploymentPostprocessing = 0; };"
    )
    text = replace_once(
        text,
        app_frameworks,
        "\t\tF00000000000000000000001 = "
        "{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; "
        f"files = ({PACKAGE_BUILD_FILE} /* NembraCore in Frameworks */); "
        "runOnlyForDeploymentPostprocessing = 0; };",
        "app Frameworks build phase",
    )

    app_target_anchor = (
        "\t\t\tname = Nembra;\n"
        "\t\t\tproductName = Nembra;\n"
    )
    text = replace_once(
        text,
        app_target_anchor,
        "\t\t\tname = Nembra;\n"
        f"\t\t\tpackageProductDependencies = ({PACKAGE_PRODUCT} /* NembraCore */);\n"
        "\t\t\tproductName = Nembra;\n",
        "app target package-product anchor",
    )

    project_anchor = (
        "\t\t\tmainGroup = 100000000000000000000001;\n"
        "\t\t\tproductRefGroup = 100000000000000000000008;\n"
    )
    text = replace_once(
        text,
        project_anchor,
        "\t\t\tmainGroup = 100000000000000000000001;\n"
        f"\t\t\tpackageReferences = ({PACKAGE_REFERENCE} /* XCLocalSwiftPackageReference \"Packages/NembraCore\" */);\n"
        "\t\t\tproductRefGroup = 100000000000000000000008;\n",
        "project package-reference anchor",
    )

    sections_anchor = "/* Begin XCBuildConfiguration section */\n"
    package_sections = (
        "/* Begin XCLocalSwiftPackageReference section */\n"
        f"\t\t{PACKAGE_REFERENCE} /* XCLocalSwiftPackageReference \"Packages/NembraCore\" */ = "
        "{isa = XCLocalSwiftPackageReference; relativePath = Packages/NembraCore; };\n"
        "/* End XCLocalSwiftPackageReference section */\n\n"
        "/* Begin XCSwiftPackageProductDependency section */\n"
        f"\t\t{PACKAGE_PRODUCT} /* NembraCore */ = {{isa = XCSwiftPackageProductDependency; "
        f"package = {PACKAGE_REFERENCE} /* XCLocalSwiftPackageReference \"Packages/NembraCore\" */; "
        "productName = NembraCore; };\n"
        "/* End XCSwiftPackageProductDependency section */\n\n"
    )
    text = replace_once(
        text,
        sections_anchor,
        package_sections + sections_anchor,
        "Swift package section anchor",
    )

    phase_pattern = re.compile(
        r"(300000000000000000000001 = \{\n"
        r"\t\t\tisa = PBXSourcesBuildPhase;\n"
        r"\t\t\tbuildActionMask = 2147483647;\n"
        r"\t\t\tfiles = \()(?P<files>[^)]*)(\);\n"
        r"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        r"\t\t\};)"
    )
    match = phase_pattern.search(text)
    if match is None:
        raise SystemExit("probe could not locate app Sources phase")
    files = match.group("files")
    for build_id in DIRECT_CORE_BUILD_IDS:
        if build_id not in files:
            raise SystemExit(f"probe expected direct Core build ID {build_id} in app Sources")
        files = re.sub(rf"\b{re.escape(build_id)}\s*,?\s*", "", files, count=1)
    files = re.sub(r",\s*,", ",", files).strip()
    prefix_start, prefix_end = match.span("files")
    text = text[:prefix_start] + files + text[prefix_end:]

    PROJECT.write_text(text, encoding="utf-8")

    verified = PROJECT.read_text(encoding="utf-8")
    app_phase = phase_pattern.search(verified)
    if app_phase is None:
        raise SystemExit("patched app Sources phase disappeared")
    for build_id in DIRECT_CORE_BUILD_IDS:
        if build_id in app_phase.group("files"):
            raise SystemExit(f"direct Core source still compiled by app: {build_id}")
    for token in (PACKAGE_BUILD_FILE, PACKAGE_REFERENCE, PACKAGE_PRODUCT):
        if token not in verified:
            raise SystemExit(f"package graph token missing after patch: {token}")


def inject_imports() -> None:
    roots = (ROOT / "NembraApp", ROOT / "NembraAppTests")
    changed = 0
    for source_root in roots:
        for path in sorted(source_root.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            if re.search(r"(?m)^import NembraCore\s*$", text):
                continue
            path.write_text("import NembraCore\n" + text, encoding="utf-8")
            changed += 1
    if changed == 0:
        raise SystemExit("probe imported NembraCore into no app/test Swift files")
    print(f"probe imported NembraCore into {changed} app/test Swift files")


def main() -> None:
    patch_project()
    inject_imports()
    print(f"probe removed {len(DIRECT_CORE_BUILD_IDS)} direct NembraCore source memberships")
    print("probe linked local NembraCore package product into Nembra target")


if __name__ == "__main__":
    main()
