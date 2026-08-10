source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'

# Nembra Capture's authenticated Tuya BLE experiment must use Tuya's official
# SmartLife App SDK. This file intentionally contains no private provisioning
# material; app-specific Tuya files stay under the already-ignored LocalSecrets.
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # Tuya's current iOS integration requires the app-specific security package
  # generated for this exact bundle identifier. Keep ThingSmartCryption.podspec
  # and its Build directory under the durable ignored path documented by Capture.
  pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSDK'

  # This P0 path needs the official HomeKit/BLE API surface only. Do not pull
  # broader business/control SDKs into the read-only experiment without a
  # concrete consumer.
  pod 'ThingSmartHomeKit', '~> 7.8.0'
end
