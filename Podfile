source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'

# Nembra Capture's authenticated read-only experiment uses Tuya's official
# SmartLife App SDK. No AppKey, AppSecret, account credential, local_key,
# session key, or other private value belongs in this public file.
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # Tuya's app-specific security component is downloaded for the exact Capture
  # bundle ID and kept under ignored LocalSecrets/TuyaSDK.
  pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSDK'

  # AppKey/AppSecret are generated into this ignored local Swift pod by the
  # repository provisioner. They never travel through xcodebuild/devicectl argv.
  pod 'NembraTuyaPrivateConfig', :path => './LocalSecrets/TuyaRuntime'

  # Exact public pins: a field build must not silently move to a newer 7.8.x
  # graph because CocoaPods resolved on another day.
  pod 'ThingSmartHomeKit', '7.8.0'
  pod 'ThingSmartBusinessExtensionKit', '7.8.0'

  # Do not add pairing, activation, OTA, DP-control, or BLEExtra bundles. The
  # scooter is already activated; this disposable utility observes only the
  # supported authenticated read-only surface.
end
