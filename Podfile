source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'

# Nembra Capture's authenticated Tuya BLE experiment must use Tuya's official
# SmartLife App SDK. This file intentionally contains no AppKey, AppSecret,
# account credential, local_key, session key, or other private material.
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # SmartLife App SDK v5+ requires the app-specific security component built
  # on the Tuya Developer Platform for this exact bundle identifier. Keep its
  # ThingSmartCryption.podspec + Build payload under the git-ignored
  # LocalSecrets/TuyaSDK directory on the private development Mac only.
  pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSDK'

  # Tuya SmartLife App SDK 7.8.0 is the selected iOS line for this experiment.
  # Keep the dependency explicit so `canImport(ThingSmartHomeKit)` cannot be
  # mistaken for a fully provisioned build when the app security SDK is absent.
  pod 'ThingSmartHomeKit', '~> 7.8.0'
end
