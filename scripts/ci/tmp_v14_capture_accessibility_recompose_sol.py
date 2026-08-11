from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")

state_marker = '''    @StateObject private var tuya = TuyaAccountBridge()\n    @State private var showEngineeringDetails = false\n'''
state_replacement = '''    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @StateObject private var tuya = TuyaAccountBridge()\n    @State private var showEngineeringDetails = false\n'''
if source.count(state_marker) != 1:
    raise SystemExit("CaptureP0Root state marker drifted")
source = source.replace(state_marker, state_replacement, 1)

stack_start = '''                    VStack(alignment: .leading, spacing: 22) {\n'''
linked_marker = '''\n                        if tuya.isLinked {\n'''
start = source.find(stack_start)
if start < 0:
    raise SystemExit("CaptureP0Root stack marker missing")
linked = source.find(linked_marker, start)
if linked < 0:
    raise SystemExit("CaptureP0Root linked-device marker missing")

replacement = '''                    VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 22) {\n                        if dynamicTypeSize.isAccessibilitySize {\n                            accountSetupPanel\n                            rootIntro\n                        } else {\n                            rootIntro\n                            accountSetupPanel\n                        }\n'''
source = source[:start] + replacement + source[linked:]

padding_marker = '''                    .padding(.horizontal, 20)\n                    .padding(.top, 22)\n                    .padding(.bottom, 44)\n'''
padding_replacement = '''                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 20)\n                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 12 : 22)\n                    .padding(.bottom, 44)\n'''
if source.count(padding_marker) != 1:
    raise SystemExit("CaptureP0Root padding marker drifted")
source = source.replace(padding_marker, padding_replacement, 1)

root_panel_marker = '''    @ViewBuilder\n    private func rootPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {\n'''
helpers = '''    private var rootIntro: some View {\n        VStack(alignment: .leading, spacing: 8) {\n            Text("NEMBRA CAPTURE")\n                .font(.caption2.bold())\n                .tracking(1.5)\n                .foregroundStyle(.cyan)\n            Text("Prepare the scooter link")\n                .font(.largeTitle.bold())\n            Text("One guided setup establishes the account and bound-device context Nembra will use before passive target correlation begins.")\n                .font(.body)\n                .foregroundStyle(.secondary)\n                .fixedSize(horizontal: false, vertical: true)\n        }\n    }\n\n    private var accountSetupPanel: some View {\n        rootPanel {\n            VStack(alignment: .leading, spacing: 14) {\n                Label(\n                    tuya.isLinked ? "Account link ready" : "Link your scooter account",\n                    systemImage: tuya.isLinked ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark"\n                )\n                .font(.title3.bold())\n                .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)\n\n                if dynamicTypeSize.isAccessibilitySize {\n                    accountLinkActions\n                    accountStatus\n                } else {\n                    accountStatus\n                    accountLinkActions\n                }\n\n                if let data = tuya.qrPNGData,\n                   let image = UIImage(data: data),\n                   !tuya.isLinked {\n                    Image(uiImage: image)\n                        .interpolation(.none)\n                        .resizable()\n                        .scaledToFit()\n                        .frame(maxWidth: 230)\n                        .padding(10)\n                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))\n                    Button("I approved it · check now") { tuya.checkApprovalNow() }\n                        .buttonStyle(.bordered)\n                        .controlSize(.large)\n                }\n\n                if tuya.phase == .failed {\n                    Button("Reset account link") { tuya.resetLink() }\n                        .buttonStyle(.bordered)\n                }\n            }\n        }\n    }\n\n    private var accountStatus: some View {\n        Text(tuya.statusMessage)\n            .font(.footnote)\n            .foregroundStyle(.secondary)\n            .fixedSize(horizontal: false, vertical: true)\n    }\n\n    @ViewBuilder\n    private var accountLinkActions: some View {\n        if !tuya.isLinked {\n            TextField("Tuya Smart User Code", text: $tuya.userCode)\n                .textInputAutocapitalization(.never)\n                .autocorrectionDisabled()\n                .padding(12)\n                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))\n            Button("Create approval QR") { tuya.requestApproval() }\n                .buttonStyle(.borderedProminent)\n                .controlSize(.large)\n                .accessibilityIdentifier("nembra.capture.account.create-approval")\n        }\n    }\n\n'''
if source.count(root_panel_marker) != 1:
    raise SystemExit("CaptureP0Root rootPanel marker drifted")
source = source.replace(root_panel_marker, helpers + root_panel_marker, 1)

required = [
    '@Environment(\\.dynamicTypeSize) private var dynamicTypeSize',
    'if dynamicTypeSize.isAccessibilitySize {\n                            accountSetupPanel\n                            rootIntro',
    'if dynamicTypeSize.isAccessibilitySize {\n                    accountLinkActions\n                    accountStatus',
    '.accessibilityIdentifier("nembra.capture.account.create-approval")',
]
for marker in required:
    if marker not in source:
        raise SystemExit(f"missing transformed marker: {marker}")

if '.dynamicTypeSize(' in source[source.find('private struct CaptureP0Root'):source.find('private final class SecureLinkController')]:
    raise SystemExit("Dynamic Type must not be capped in CaptureP0Root")

path.write_text(source, encoding="utf-8")
