from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    text = text.replace(old, new, 1)


# Controller-owned retry authority. Never let the View bypass retained generation ownership.
controller_anchor = "    var canRestartFromFreshOFF1: Bool { failedAttemptCanRestartFromOFF1 }\n\n"
retry = """    func retry() {
        guard phase == .failed, canRestartFromFreshOFF1 else {
            message = "This failed attempt still retains session authority. Relaunch Capture before another OFF1 attempt."
            log("in_process_retry_rejected")
            return
        }
        startBaseline()
    }

"""
replace_once(controller_anchor, controller_anchor + retry, "controller retry anchor")

# Route failed prerequisite states back to the exact missing authority surface without reusing evidence.
replace_once(
    "        case .failed:\n            failurePanel\n",
    """        case .failed:
            if !test.fieldBuildIsAuthoritative || !test.privateConfig {
                VStack(spacing: 16) {
                    failureRecoveryContextPanel
                    preflightPanel
                }
            } else if !sdkAccount.loggedIn || !test.sdkAccountLoggedIn {
                VStack(spacing: 16) {
                    failureRecoveryContextPanel
                    sdkAuthorizationPanel
                }
            } else if !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                VStack(spacing: 16) {
                    failureRecoveryContextPanel
                    preflightPanel
                }
            } else {
                failurePanel
            }
""",
    "failed primary surface",
)

# Correlation progress must not squeeze the title against 4/4 at accessibility text sizes.
panel_start = text.index("    private var correlationPanel: some View {")
header_start = text.index("                HStack(alignment: .firstTextBaseline) {", panel_start)
header_end = text.index("\n\n                if test.phase == .correlated {", header_start)
old_header = text[header_start:header_end]
new_header = """                if dynamicTypeSize.isAccessibilitySize {
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
                }"""
if "correlationDisplayedWindowOrdinal" not in old_header:
    raise SystemExit("correlation header no longer contains the package-derived ordinal")
text = text[:header_start] + new_header + text[header_end:]

# The authenticated observation label and countdown also need a vertical AX composition.
obs_start = text.index("                    let age = test.canonicalObservedAgeSeconds ?? 0")
timer_start = text.index("                        HStack {", obs_start)
timer_end = text.index("\n                        ProgressView(value: min(age / 45, 1))", timer_start)
old_timer = text[timer_start:timer_end]
new_timer = """                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Authenticated observation")
                                    .font(.subheadline.weight(.semibold))
                                Text("\\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        } else {
                            HStack {
                                Text("Authenticated observation")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        }"""
if "Authenticated observation" not in old_timer:
    raise SystemExit("observation timer header changed")
text = text[:timer_start] + new_timer + text[timer_end:]
replace_once(
    "                        ProgressView(value: min(age / 45, 1))\n",
    """                        ProgressView(value: min(age / 45, 1))
                            .accessibilityLabel("Authenticated observation progress")
                            .accessibilityValue("\\(Int(min(age, 45))) of 45 seconds")
""",
    "observation progress semantics",
)

# Explain prerequisite recovery without claiming the failed attempt can be reused.
failure_marker = "    private var failurePanel: some View {\n"
if text.count(failure_marker) != 1:
    raise SystemExit("failure panel marker changed")
recovery_panel = """    private var failureRecoveryContextPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Capture paused", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Restore the missing prerequisite below. The failed attempt is not reused as evidence.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

"""
text = text.replace(failure_marker, recovery_panel + failure_marker, 1)

# The terminal failure action calls the controller gate and stays disabled until authority is restored.
failure_start = text.index("    private var failurePanel: some View {")
failure_end = text.index("    private var completionPanel: some View {", failure_start)
failure = text[failure_start:failure_end]
if failure.count("                        test.startBaseline()") != 1:
    raise SystemExit("failure restart action changed")
failure = failure.replace("                        test.startBaseline()", "                        test.retry()", 1)
control = "                    .controlSize(.large)\n"
if failure.count(control) != 1:
    raise SystemExit("failure restart control size changed")
failure = failure.replace(control, control + "                    .disabled(!authorityReady || test.membershipBusy)\n", 1)
text = text[:failure_start] + failure + text[failure_end:]

# Fail if stale product behavior survived.
for forbidden in (
    'case .failed:\n            failurePanel',
    'Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")',
):
    if forbidden in text:
        raise SystemExit(f"stale Capture product contract survived: {forbidden}")

for required in (
    "func retry()",
    "guard phase == .failed, canRestartFromFreshOFF1 else",
    "failureRecoveryContextPanel",
    "test.retry()",
    ".disabled(!authorityReady || test.membershipBusy)",
    "if dynamicTypeSize.isAccessibilitySize",
    'accessibilityLabel("Correlation progress")',
    'accessibilityLabel("Authenticated observation progress")',
    "procedureIdentifier == Self.fieldProcedureIdentifier",
):
    if required not in text and required != "procedureIdentifier == Self.fieldProcedureIdentifier":
        raise SystemExit(f"required Capture product contract missing: {required}")

identity = Path("NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")
if "procedureIdentifier == Self.fieldProcedureIdentifier" not in identity:
    raise SystemExit("built procedure authority regressed during UI recovery")

path.write_text(text, encoding="utf-8")
