from pathlib import Path

path = Path("scripts/field/install_one_time_capture.command")
source = path.read_text(encoding="utf-8")

helper_anchor = '''TUYA_PROVENANCE_HELPER="$ROOT/Scripts/capture_tuya_private_input_provenance.py"
TUYA_PRIVATE_SDK="$ROOT/LocalSecrets/TuyaSDK"
'''
helper_replacement = '''TUYA_PROVENANCE_HELPER="$ROOT/Scripts/capture_tuya_private_input_provenance.py"
TUYA_BUILD_WINDOW_GUARD="$ROOT/Scripts/capture_tuya_private_input_build_guard.py"
[[ -f "$TUYA_BUILD_WINDOW_GUARD" ]] || die "Private Tuya build-window custody guard is missing from the accepted source."
TUYA_PRIVATE_SDK="$ROOT/LocalSecrets/TuyaSDK"
'''
if source.count(helper_anchor) != 1:
    raise SystemExit(f"private helper anchor drifted: {source.count(helper_anchor)}")
source = source.replace(helper_anchor, helper_replacement, 1)

build_anchor = '''xcodebuild \\
    -workspace NembraCapture.xcworkspace \\
    -scheme "Nembra Capture" \\
    -configuration Debug \\
    -destination "generic/platform=iOS" \\
    -derivedDataPath "$DERIVED" \\
    -allowProvisioningUpdates \\
    -allowProvisioningDeviceRegistration \\
    DEVELOPMENT_TEAM="$TEAM_ID" \\
    CODE_SIGN_STYLE=Automatic \\
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \\
    "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL" \\
    "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA" \\
    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\
    "INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID" \\
    build
'''
build_replacement = '''# Endpoint fingerprints alone cannot prove that a transient private-input change
# was not consumed by the compiler and restored before the post-build verify.
# Keep macOS vnode custody armed for every admitted private file/directory across
# the complete compiler/linker window, then retain the cryptographic verify below.
/usr/bin/python3 -I "$TUYA_BUILD_WINDOW_GUARD" \\
    --lockfile "$ROOT/Podfile.lock" \\
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \\
    --security-build "$TUYA_PRIVATE_SDK/Build" \\
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \\
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \\
    -- xcodebuild \\
    -workspace NembraCapture.xcworkspace \\
    -scheme "Nembra Capture" \\
    -configuration Debug \\
    -destination "generic/platform=iOS" \\
    -derivedDataPath "$DERIVED" \\
    -allowProvisioningUpdates \\
    -allowProvisioningDeviceRegistration \\
    DEVELOPMENT_TEAM="$TEAM_ID" \\
    CODE_SIGN_STYLE=Automatic \\
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \\
    "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL" \\
    "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA" \\
    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\
    "INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID" \\
    build || die "Private inputs changed while xcodebuild was running, vnode custody failed, or the signed build itself failed. No field artifact was admitted."
'''
if source.count(build_anchor) != 1:
    raise SystemExit(f"field xcodebuild anchor drifted: {source.count(build_anchor)}")
source = source.replace(build_anchor, build_replacement, 1)
path.write_text(source, encoding="utf-8")
