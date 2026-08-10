from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductSurfaceSourceTests.swift")

app = APP.read_text()
old_extension = '''private extension View {
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}
'''
new_extension = '''private extension View {
    func inputSurface() -> some View {
        padding(12)
            .frame(minHeight: 50)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}
'''
if app.count(old_extension) != 1:
    raise SystemExit("legacy card helper anchor changed")
app = app.replace(old_extension, new_extension, 1)
APP.write_text(app)

tests = TEST.read_text()
anchor = '        #expect(body.contains("navigationTitle(\\"Capture\\")"))\n'
addition = '''        #expect(body.contains(".inputSurface()"))
        #expect(app.contains("func inputSurface() -> some View"))
        #expect(!app.contains("func card() -> some View"))
'''
if tests.count(anchor) != 1:
    raise SystemExit("product surface test anchor changed")
tests = tests.replace(anchor, anchor + addition, 1)
TEST.write_text(tests)

app = APP.read_text()
assert app.count(".inputSurface()") == 3
assert "func inputSurface() -> some View" in app
assert "func card() -> some View" not in app
