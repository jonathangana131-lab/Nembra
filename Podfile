source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'

# Nembra Capture's authenticated Tuya BLE experiment must use Tuya's official
# SmartLife App SDK. This file intentionally contains no private provisioning
# material; app-specific Tuya files stay under the already-ignored LocalSecrets.
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # Tuya's current iOS integration requires the app-specific security package
  # generated for this exact bundle identifier. Place ThingSmartCryption.podspec
  # and its Build directory in LocalSecrets/TuyaSecuritySDK on the build Mac.
  pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSecuritySDK'

  # Keep the public SmartLife dependency explicit so canImport(ThingSmartHomeKit)
  # cannot be mistaken for a fully provisioned field build.
  pod 'ThingSmartHomeKit', '~> 7.8.0'
end
