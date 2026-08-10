from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text(encoding="utf-8")

old_header = '''                HStack(alignment: .firstTextBaseline) {
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
new_header = '''                if dynamicTypeSize.isAccessibilitySize {
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

old_observation = '''                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Read-only observation")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\\(Int(min(age, 45))) / 45 s")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        ProgressView(value: min(age / 45, 1))
                        requirementRow("Secure local link", ready: test.sdkLocalBLEOnline)
'''
new_observation = '''                    VStack(alignment: .leading, spacing: 8) {
                        if dynamicTypeSize.isAccessibilitySize {
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
                        requirementRow("Secure local link", ready: test.sdkLocalBLEOnline)
'''

for label, old, new in (("correlation header", old_header, new_header), ("observation timer", old_observation, new_observation)):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one current-product match, found {count}")
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
