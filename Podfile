source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'

# Nembra Capture's authenticated Tuya BLE experiment must use Tuya's official
# SmartLife App SDK. This file intentionally contains no AppKey, AppSecret,
# account credential, local_key, session key, or other private material.
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # Tuya's current iOS integration requires the app-specific security package
  # generated for this exact bundle identifier. Keep ThingSmartCryption.podspec
  # and its Build directory only in this ignored local directory; never commit
  # the generated security SDK.
  pod 'ThingSmartCryption', :path => './.tuya-private-sdk'

  # Keep the public SmartLife dependency explicit so canImport(ThingSmartHomeKit)
  # cannot be mistaken for a fully provisioned field build.
  pod 'ThingSmartHomeKit', '~> 7.8.0'
end
