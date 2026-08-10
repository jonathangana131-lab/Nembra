from pathlib import Path

app = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = app.read_text()
old = '''        [NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret]
            .filter { !$0.isEmpty }
'''
new = '''        [NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret]
            .filter { !$0.isEmpty }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0 < $1
            }
'''
if source.count(old) != 1:
    raise SystemExit(f"exact-secret ordering seam drifted: {source.count(old)}")
source = source.replace(old, new, 1)
app.write_text(source)

test = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationSecretValueCustodySourceTests.swift")
test_source = test.read_text()
anchor = '''        #expect(!callback.contains("String(describing: Self.redactApplicationSecrets(value))"))
    }

'''
replacement = '''        #expect(!callback.contains("String(describing: Self.redactApplicationSecrets(value))"))
        #expect(sanitizer.contains("if $0.count != $1.count { return $0.count > $1.count }"))
        #expect(sanitizer.contains("return $0 < $1"))
    }

'''
if test_source.count(anchor) != 1:
    raise SystemExit("secret custody regression seam drifted")
test.write_text(test_source.replace(anchor, replacement, 1))

secret_block = source.split("private static var exactSecretValues: [String]", 1)[1].split("private static func redactKnownSecretValues", 1)[0]
if "if $0.count != $1.count { return $0.count > $1.count }" not in secret_block:
    raise SystemExit("longest-secret-first ordering is missing")
if "return $0 < $1" not in secret_block:
    raise SystemExit("deterministic tie-break is missing")
