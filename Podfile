platform :ios, '17.0'

# Nembra Capture's authenticated Tuya BLE experiment must use Tuya's official
# SmartLife App SDK. This file intentionally contains no AppKey, AppSecret,
# account credential, local_key, session key, or other private material.
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # Tuya SmartLife App SDK 7.8.0 is the current iOS line documented by Tuya.
  # Keep the dependency explicit so `canImport(ThingSmartHomeKit)` cannot be
  # mistaken for a provisioned build when the standalone project has no SDK.
  pod 'ThingSmartHomeKit', '~> 7.8.0'
end
