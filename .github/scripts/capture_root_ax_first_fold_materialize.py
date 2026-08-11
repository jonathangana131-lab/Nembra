from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()

replacements = [
    (
        "hero",
        '''            Text(\n                isAccessibilityLayout\n                    ? (fieldBuildIsAuthoritative\n                        ? "Link the account that owns this scooter before discovery."\n                        : "Account setup only in this public build.")\n                    : "Link the account that owns this scooter. Physical Capture still depends on the field-build gate and fresh scooter authority below."\n            )\n            .font(isAccessibilityLayout ? .callout : .body)\n            .foregroundStyle(Color.white.opacity(0.78))\n            .fixedSize(horizontal: false, vertical: true)\n''',
        '''            if !isAccessibilityLayout {\n                Text("Link the account that owns this scooter. Physical Capture still depends on the field-build gate and fresh scooter authority below.")\n                    .font(.body)\n                    .foregroundStyle(Color.white.opacity(0.78))\n                    .fixedSize(horizontal: false, vertical: true)\n            }\n''',
    ),
    (
        "authority",
        '''                Text(\n                    isAccessibilityLayout\n                        ? (fieldBuildIsAuthoritative\n                            ? "Account and scooter authority are still required before Bluetooth starts."\n                            : "Public build: account metadata only. Bluetooth and physical evidence stay locked.")\n                        : (fieldBuildIsAuthoritative\n                            ? "Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts."\n                            : "This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture.")\n                )\n                .font(isAccessibilityLayout ? .callout : .subheadline)\n                .foregroundStyle(Color.white.opacity(0.76))\n                .fixedSize(horizontal: false, vertical: true)\n''',
        '''                if !isAccessibilityLayout {\n                    Text(\n                        fieldBuildIsAuthoritative\n                            ? "Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts."\n                            : "This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture."\n                    )\n                    .font(.subheadline)\n                    .foregroundStyle(Color.white.opacity(0.76))\n                    .fixedSize(horizontal: false, vertical: true)\n                }\n''',
    ),
    (
        "account heading",
        '''                        Text(tuya.isLinked ? "Account metadata ready" : "Prepare account metadata")\n                            .font(.title3.bold())\n                            .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)\n                        Text(\n                            tuya.isLinked\n                                ? "Account context is ready for scooter selection."\n                                : "Use the Tuya Smart user code for the account that owns this scooter."\n                        )\n                        .font(.subheadline)\n                        .foregroundStyle(Color.white.opacity(0.74))\n                        .fixedSize(horizontal: false, vertical: true)\n''',
        '''                        Text(\n                            tuya.isLinked\n                                ? "Account metadata ready"\n                                : (isAccessibilityLayout ? "Account metadata" : "Prepare account metadata")\n                        )\n                        .font(isAccessibilityLayout ? .headline : .title3.bold())\n                        .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)\n\n                        if !isAccessibilityLayout || tuya.isLinked {\n                            Text(\n                                tuya.isLinked\n                                    ? "Account context is ready for scooter selection."\n                                    : "Use the Tuya Smart user code for the account that owns this scooter."\n                            )\n                            .font(.subheadline)\n                            .foregroundStyle(Color.white.opacity(0.74))\n                            .fixedSize(horizontal: false, vertical: true)\n                        }\n''',
    ),
    (
        "AX tail",
        '''                    if isAccessibilityLayout {\n                        Text("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.")\n                            .font(.footnote)\n                            .foregroundStyle(Color.white.opacity(0.72))\n                            .fixedSize(horizontal: false, vertical: true)\n                        statusText\n                    }\n''',
        '''                    if isAccessibilityLayout {\n                        Text("Account setup only in this public build.")\n                            .font(.footnote.weight(.semibold))\n                            .foregroundStyle(Color.white.opacity(0.78))\n                            .fixedSize(horizontal: false, vertical: true)\n                        Text("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.")\n                            .font(.footnote)\n                            .foregroundStyle(Color.white.opacity(0.72))\n                            .fixedSize(horizontal: false, vertical: true)\n                        statusText\n                    }\n''',
    ),
]

for name, old, new in replacements:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{name}: expected exactly one source block, found {count}")
    source = source.replace(old, new, 1)

path.write_text(source)
