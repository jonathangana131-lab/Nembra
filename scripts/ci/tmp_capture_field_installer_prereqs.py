from pathlib import Path

ignore = Path('.gitignore')
text = ignore.read_text()
addition = '''

# Private Capture field-build inputs / generated CocoaPods workspace
LocalSecrets/
Pods/
NembraCapture.xcworkspace/
Podfile.lock
'''
for line in ['LocalSecrets/', 'Pods/', 'NembraCapture.xcworkspace/', 'Podfile.lock']:
    assert line not in text
ignore.write_text(text.rstrip() + addition)

workflow = Path('.github/workflows/capture-field-build-provenance.yml')
w = workflow.read_text()
path_anchor = '      - NembraApp/App/NembraCaptureBuildIdentity.swift\n'
assert w.count(path_anchor) == 1
path_add = '      - .gitignore\n      - scripts/ci/es80_signed_field_artifact_private_runner.py\n'
w = w.replace(path_anchor, path_anchor + path_add, 1)

var_anchor = "          private_provenance='Scripts/capture_tuya_private_input_provenance.py'\n"
assert w.count(var_anchor) == 1
var_add = "          private_device_runner='scripts/ci/es80_signed_field_artifact_private_runner.py'\n          ignore='.gitignore'\n"
w = w.replace(var_anchor, var_anchor + var_add, 1)

check_anchor = '          bash -n "$installer"\n'
assert w.count(check_anchor) == 1
checks = '''          test -f "$private_device_runner"
          grep -Fq 'def read_private_identifier(' "$private_device_runner"
          grep -Fq 'O_NOFOLLOW' "$private_device_runner"
          grep -Fq 'O_DIRECTORY' "$private_device_runner"
          grep -Fq 'dir_fd=parent_descriptor' "$private_device_runner"
          grep -Fxq 'LocalSecrets/' "$ignore"
          grep -Fxq 'Pods/' "$ignore"
          grep -Fxq 'NembraCapture.xcworkspace/' "$ignore"
          grep -Fxq 'Podfile.lock' "$ignore"
'''
w = w.replace(check_anchor, check_anchor + checks, 1)
workflow.write_text(w)

test_path = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift')
t = test_path.read_text()
marker = '    @Test("connected-device discovery must match the private intended iPhone exactly once")\n'
assert t.count(marker) == 1
addition = '''    @Test("accepted source carries the hardened private intended-device reader")
    func privateDeviceReaderExistsAndFailsClosed() throws {
        let helper = try readRepositoryFile("scripts/ci/es80_signed_field_artifact_private_runner.py")

        #expect(helper.contains("def read_private_identifier(path: Path, repository_root: Path) -> str"))
        #expect(helper.contains("O_NOFOLLOW"))
        #expect(helper.contains("O_DIRECTORY"))
        #expect(helper.contains("dir_fd=parent_descriptor"))
        #expect(helper.contains("must live outside the Nembra repository"))
        #expect(helper.contains("stat.S_ISREG"))
        #expect(helper.contains("metadata.st_mode & 0o077"))
        #expect(helper.contains("metadata.st_uid != os.geteuid()"))
        #expect(helper.contains("metadata.st_nlink != 1"))
        #expect(helper.contains("_stable_file_identity(final_metadata) != _stable_file_identity(metadata)"))
        #expect(helper.contains("value != value.strip()"))
        #expect(helper.contains("value in os.fspath(path)"))
    }

    @Test("private build outputs are narrowly ignored while arbitrary untracked state remains rejected")
    func generatedPrivateWorkspaceDoesNotTripAcceptedSourceGuard() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let ignore = try readRepositoryFile(".gitignore")

        for expected in ["LocalSecrets/", "Pods/", "NembraCapture.xcworkspace/", "Podfile.lock"] {
            #expect(ignore.split(separator: "\\n").contains(Substring(expected)))
        }
        #expect(installer.components(separatedBy: "git status --porcelain=v1 --untracked-files=all").count >= 3)
        #expect(installer.contains("Private workspace bootstrap changed tracked or unignored accepted-source inputs"))
        #expect(installer.contains("Accepted-source inputs changed while the field build was compiling"))
    }

'''
test_path.write_text(t.replace(marker, addition + marker, 1))
