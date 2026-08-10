source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # Tuya requires the app-specific security package generated for this exact
  # iOS bundle identifier. Keep ThingSmartCryption.podspec + Build only in
  # this ignored local directory; never commit the generated security SDK.
  pod 'ThingSmartCryption', :path => './.tuya-private-sdk'

  # Pinned to the current Tuya SmartLife App SDK generation selected for this
  # one-time authenticated read-only preflight.
  pod 'ThingSmartHomeKit', '~> 7.8.0'
  pod 'ThingSmartBusinessExtensionKit', '~> 7.8.0'
  pod 'ThingSmartBusinessExtensionKitBLEExtra', '~> 7.8.0'
end
