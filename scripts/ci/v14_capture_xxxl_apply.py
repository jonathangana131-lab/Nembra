#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{path}: anchor count {n} for {old[:80]!r}")
    p.write_text(text.replace(old, new, 1))

shell = "NembraApp/Features/Research/ES80CaptureShellView.swift"
app = "NembraApp/App/NembraApp.swift"

replace_once(shell,
'''            Text("\\(snapshot.evidenceLabel) · SYNTHETIC SOFTWARE STATE")
                .fixedSize(horizontal: false, vertical: true)''',
'''            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "SIMULATOR QA · SYNTHETIC"
                    : "\\(snapshot.evidenceLabel) · SYNTHETIC SOFTWARE STATE"
            )
            .fixedSize(horizontal: false, vertical: true)''')

replace_once(shell,
'''    private var completionPanel: some View {
        let analysisReady = presentationAnalysisReady
        return VStack(alignment: .leading, spacing: 16) {''',
'''    private var completionPanel: some View {
        let analysisReady = presentationAnalysisReady
        return VStack(
            alignment: .leading,
            spacing: dynamicTypeSize.isAccessibilitySize ? 10 : 16
        ) {''')

replace_once(shell,
'''            ZStack {
                Circle()
                    .fill(analysisReady ? .white : .white.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: analysisReady ? "checkmark" : "lock.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(analysisReady ? .black : .white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {''',
'''            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    Circle()
                        .fill(analysisReady ? .white : .white.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: analysisReady ? "checkmark" : "lock.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(analysisReady ? .black : .white)
                }
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {''')

replace_once(shell,
'''        if simulatorQASnapshot != nil {
            Text("Synthetic Simulator QA presentation only. No capture artifact bytes were created, and no physical, RF, protocol, telemetry, or command evidence is claimed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)''',
'''        if simulatorQASnapshot != nil {
            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "Synthetic Simulator QA only. No physical evidence."
                    : "Synthetic Simulator QA presentation only. No capture artifact bytes were created, and no physical, RF, protocol, telemetry, or command evidence is claimed."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(
                "Synthetic Simulator QA presentation only. No capture artifact bytes were created, and no physical, RF, protocol, telemetry, or command evidence is claimed."
            )''')

replace_once(app,
'''                    Text(
                        isAccessibilityLayout
                            ? "Final exact-build checks are still in progress."
                            : "This build is still finishing its final checks before it can collect real ES80 data."
                    )
                    .font(
                        isAccessibilityLayout
                            ? .body.weight(.medium)
                            : (verticalSizeClass == .compact
                                ? .subheadline.weight(.medium)
                                : .title3.weight(.medium))
                    )
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)''',
'''                    if !isAccessibilityLayout {
                        Text("This build is still finishing its final checks before it can collect real ES80 data.")
                            .font(
                                verticalSizeClass == .compact
                                    ? .subheadline.weight(.medium)
                                    : .title3.weight(.medium)
                            )
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }''')

replace_once(app,
'''                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.lock.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not ready for scooter capture yet")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(
                            isAccessibilityLayout
                                ? "Exact-build checks must pass before Bluetooth capture can begin."
                                : "Nembra keeps every scooter action locked until the exact app build passes its required checks and is explicitly cleared for this physical procedure. When this screen unlocks, Capture will guide the OFF / ON sequence step by step."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(verticalSizeClass == .compact ? 12 : (isAccessibilityLayout ? 14 : 18))
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(physicalLockAccessibilityLabel)
                .accessibilityIdentifier("es80.capture.physical-run-locked")''',
'''                HStack(alignment: .top, spacing: isAccessibilityLayout ? 0 : 12) {
                    if !isAccessibilityLayout {
                        Image(systemName: "exclamationmark.lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: isAccessibilityLayout ? 3 : 6) {
                        Text(isAccessibilityLayout ? "Physical capture NO-GO" : "Not ready for scooter capture yet")
                            .font(isAccessibilityLayout ? .subheadline.weight(.semibold) : .headline)
                            .foregroundStyle(.white)

                        Text(
                            isAccessibilityLayout
                                ? "Exact-build clearance is still required."
                                : "Nembra keeps every scooter action locked until the exact app build passes its required checks and is explicitly cleared for this physical procedure. When this screen unlocks, Capture will guide the OFF / ON sequence step by step."
                        )
                        .font(isAccessibilityLayout ? .footnote : .subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(verticalSizeClass == .compact ? 12 : (isAccessibilityLayout ? 10 : 18))
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(physicalLockAccessibilityLabel)
                .accessibilityIdentifier("es80.capture.physical-run-locked")''')

replace_once(app,
'spacing: verticalSizeClass == .compact ? 10 : (isAccessibilityLayout ? 14 : 28)',
'spacing: verticalSizeClass == .compact ? 10 : (isAccessibilityLayout ? 10 : 28)')
replace_once(app,
'spacing: verticalSizeClass == .compact ? 6 : (isAccessibilityLayout ? 8 : 14)',
'spacing: verticalSizeClass == .compact ? 6 : (isAccessibilityLayout ? 6 : 14)')
replace_once(app,
'.padding(.horizontal, isAccessibilityLayout ? 18 : 22)',
'.padding(.horizontal, isAccessibilityLayout ? 16 : 22)')
replace_once(app,
'.padding(.top, verticalSizeClass == .compact ? 8 : (isAccessibilityLayout ? 12 : 18))',
'.padding(.top, verticalSizeClass == .compact ? 8 : (isAccessibilityLayout ? 8 : 18))')

shell_text = Path(shell).read_text()
app_text = Path(app).read_text()
combined = shell_text + app_text
for token in (
    "SIMULATOR QA · SYNTHETIC",
    "Synthetic Simulator QA only. No physical evidence.",
    "Physical capture NO-GO",
    "Exact-build clearance is still required.",
    'accessibilityIdentifier("es80.capture.physical-run-locked")',
    'accessibilityIdentifier("es80.capture.engineering-details")',
):
    if token not in combined:
        raise SystemExit(f"missing repaired contract: {token}")
if ".dynamicTypeSize(" in shell_text or ".dynamicTypeSize(" in app_text:
    raise SystemExit("repair must not cap Dynamic Type")
