#!/usr/bin/env python3
from pathlib import Path

PROJECT = Path("Nembra.xcodeproj/project.pbxproj")
text = PROJECT.read_text()

BUILD_MARKER = "A00000000000000000000032 /* DashboardView.swift in Sources */"
FILE_MARKER = "B00000000000000000000032 /* DashboardView.swift */"
GROUP_MARKER = "100000000000000000000032 /* Dashboard */"

if BUILD_MARKER in text and FILE_MARKER in text and GROUP_MARKER in text:
    print("DashboardView is already wired into the Xcode project.")
    raise SystemExit(0)

replacements = [
    (
        "\t\tA00000000000000000000030 /* NembraUITests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000030 /* NembraUITests.swift */; };\n",
        "\t\tA00000000000000000000030 /* NembraUITests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000030 /* NembraUITests.swift */; };\n"
        "\t\tA00000000000000000000032 /* DashboardView.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000032 /* DashboardView.swift */; };\n",
        "build file",
    ),
    (
        "\t\tB00000000000000000000031 /* NembraUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = NembraUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };\n",
        "\t\tB00000000000000000000031 /* NembraUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = NembraUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };\n"
        "\t\tB00000000000000000000032 /* DashboardView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DashboardView.swift; sourceTree = \"<group>\"; };\n",
        "file reference",
    ),
    (
        "\t\t\t\t100000000000000000000005 /* Home */,\n\t\t\t\t100000000000000000000009 /* Resources */,\n",
        "\t\t\t\t100000000000000000000005 /* Home */,\n\t\t\t\t100000000000000000000032 /* Dashboard */,\n\t\t\t\t100000000000000000000009 /* Resources */,\n",
        "app group child",
    ),
]

for old, new, label in replacements:
    if old not in text:
        raise SystemExit(f"Missing PBX anchor: {label}")
    text = text.replace(old, new, 1)

home_group = '''\t\t100000000000000000000005 /* Home */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (B00000000000000000000005, B00000000000000000000006, B0000000000000000000000F);
\t\t\tname = Home;
\t\t\tpath = Features/Home;
\t\t\tsourceTree = "<group>";
\t\t};
'''
dashboard_group = '''\t\t100000000000000000000032 /* Dashboard */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (B00000000000000000000032);
\t\t\tname = Dashboard;
\t\t\tpath = Features/Dashboard;
\t\t\tsourceTree = "<group>";
\t\t};
'''
if home_group not in text:
    raise SystemExit("Missing PBX anchor: Home group")
text = text.replace(home_group, home_group + dashboard_group, 1)

source_anchor = "A00000000000000000000028, A00000000000000000000029);"
if source_anchor not in text:
    raise SystemExit("Missing PBX anchor: app source list")
text = text.replace(
    source_anchor,
    "A00000000000000000000028, A00000000000000000000029, A00000000000000000000032);",
    1,
)

if not all(marker in text for marker in (BUILD_MARKER, FILE_MARKER, GROUP_MARKER)):
    raise SystemExit("Dashboard Xcode wiring validation failed")

PROJECT.write_text(text)
print("DashboardView wired into Nembra.xcodeproj.")
