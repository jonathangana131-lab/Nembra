from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureAccessibilityXXXLSourceTests.swift"

OLD_CORRELATION = '''                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FIND SCOOTER")
                            .font(.caption2.bold())
                            .tracking(1.2)
                            .foregroundStyle(.cyan)
                        Text(test.phase == .correlated ? "Scooter signal found" : test.correlationWindowLabel)
                            .font(.title2.bold())
                    }
                    Spacer()
                    Text("\\(correlationDisplayedWindowOrdinal)/4")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }
'''

NEW_CORRELATION = '''                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FIND SCOOTER")
                                .font(.caption2.bold())
                                .tracking(1.2)
                                .foregroundStyle(.cyan)
                            Text(test.phase == .correlated ? "Scooter signal found" : test.correlationWindowLabel)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\\(correlationDisplayedWindowOrdinal)/4")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Correlation progress")
                            .accessibilityValue("\\(correlationDisplayedWindowOrdinal) of 4 windows")
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FIND SCOOTER")
                                .font(.caption2.bold())
                                .tracking(1.2)
                                .foregroundStyle(.cyan)
                            Text(test.phase == .correlated ? "Scooter signal found" : test.correlationWindowLabel)
                                .font(.title2.bold())
                        }
                        Spacer()
                        Text("\\(correlationDisplayedWindowOrdinal)/4")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Correlation progress")
                            .accessibilityValue("\\(correlationDisplayedWindowOrdinal) of 4 windows")
                    }
                }
'''

OLD_OBSERVATION = '''                        HStack {
                            Text("Read-only observation")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\\(Int(min(age, 45))) / 45 s")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        ProgressView(value: min(age / 45, 1))
'''

NEW_OBSERVATION = '''                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Read-only observation")
                                    .font(.subheadline.weight(.semibold))
                                Text("\\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        } else {
                            HStack {
                                Text("Read-only observation")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        }
                        ProgressView(value: min(age / 45, 1))
                            .accessibilityLabel("Read-only observation progress")
                            .accessibilityValue("\\(Int(min(age, 45))) of 45 seconds")
'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Accessibility XXXL layout")
struct TuyaCaptureAccessibilityXXXLSourceTests {
    @Test("correlation progress recomposes at Accessibility sizes")
    func correlationHeaderRecomposesAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(in: app, from: "private var correlationPanel: some View", to: "private var secureObservationPanel: some View"))

        #expect(panel.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(panel.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(panel.contains(".accessibilityLabel(\"Correlation progress\")"))
        #expect(panel.contains(".accessibilityValue(\"\\(correlationDisplayedWindowOrdinal) of 4 windows\")"))
        #expect(panel.contains("else {\n                    HStack(alignment: .firstTextBaseline)"))
    }

    @Test("observation progress recomposes and has semantic progress")
    func observationProgressRecomposesAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(in: app, from: "private var secureObservationPanel: some View", to: "private var failureRecoveryContextPanel: some View"))

        #expect(panel.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(panel.contains("VStack(alignment: .leading, spacing: 4)"))
        #expect(panel.contains(".accessibilityLabel(\"Read-only observation progress\")"))
        #expect(panel.contains(".accessibilityValue(\"\\(Int(min(age, 45))) of 45 seconds\")"))
        #expect(panel.contains("else {\n                            HStack"))
    }

    @Test("reflow remains inside the presentation boundary")
    func reflowHasNoAuthoritySideEffect() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable"))

        #expect(view.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(view.contains("SignInWithAppleButton(.signIn)"))
        #expect(view.contains("test.canRestartFromFreshOFF1"))
        #expect(!view.contains("SIMCTL_CHILD_"))
        #expect(!view.contains("NEMBRA_SIMULATION_"))
        #expect(!view.contains("publishDps"))
        #expect(!view.contains("queryDps"))
        #expect(!view.contains("writeValue"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
'''


def require_count(text: str, token: str, count: int, label: str) -> None:
    actual = text.count(token)
    if actual != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {actual}")


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    require_count(app, OLD_CORRELATION, 1, "compact correlation header")
    require_count(app, OLD_OBSERVATION, 1, "compact observation progress")
    require_count(app, '@Environment(\\.dynamicTypeSize) private var dynamicTypeSize', 1, "Dynamic Type environment")
    require_count(app, "PackageCorrelationOwnershipLease", 1, "current process-global package lease")

    app = app.replace(OLD_CORRELATION, NEW_CORRELATION, 1)
    app = app.replace(OLD_OBSERVATION, NEW_OBSERVATION, 1)
    APP.write_text(app, encoding="utf-8")

    if TEST.exists():
        raise SystemExit("Accessibility XXXL regression already exists on exact product parent")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    for token in (
        'if dynamicTypeSize.isAccessibilitySize',
        '.accessibilityLabel("Correlation progress")',
        '.accessibilityValue("\\(correlationDisplayedWindowOrdinal) of 4 windows")',
        '.accessibilityLabel("Read-only observation progress")',
        '.accessibilityValue("\\(Int(min(age, 45))) of 45 seconds")',
        'PackageCorrelationOwnershipLease',
        'SignInWithAppleButton(.signIn)',
    ):
        if token not in app:
            raise SystemExit(f"required current product/AX token missing: {token}")
    if OLD_CORRELATION in app or OLD_OBSERVATION in app:
        raise SystemExit("compact-only large-text layout survived")
    for forbidden in ("SIMCTL_CHILD_", "NEMBRA_SIMULATION_", "publishDps", "queryDps", "writeValue"):
        secure = app[app.index("private struct SecureLinkView: View"):app.index("private struct SecureTransfer: Transferable")]
        if forbidden in secure:
            raise SystemExit(f"presentation boundary gained authority token: {forbidden}")

    if not TEST.exists():
        raise SystemExit("Accessibility XXXL source regression missing")
    test = TEST.read_text(encoding="utf-8")
    for token in (
        "correlationHeaderRecomposesAtAccessibilitySizes",
        "observationProgressRecomposesAtAccessibilitySizes",
        "reflowHasNoAuthoritySideEffect",
    ):
        if token not in test:
            raise SystemExit(f"AX regression missing contract: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
