source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'
project 'NembraCapture.xcodeproj'

private_tuya_root = File.expand_path('.nembra-tuya-sdk', __dir__)
private_cryption_podspec = File.join(private_tuya_root, 'ThingSmartCryption.podspec')

unless File.file?(private_cryption_podspec)
  abort <<~MESSAGE
    Missing the private Tuya SmartLife security component.
    Download the iOS SDK security package generated for bundle ID
    com.jonathangana131.nembra.capturelearn and place its Build/ directory plus
    ThingSmartCryption.podspec under .nembra-tuya-sdk/.
    Never commit that directory, AppKey, or AppSecret.
  MESSAGE
end

target 'Nembra Capture' do
  use_frameworks!

  # Tuya's generated security component is app-specific and remains local/private.
  pod 'ThingSmartCryption', :path => private_tuya_root

  # Official SmartLife app/device/BLE APIs used by the read-only authenticated preflight.
  pod 'ThingSmartHomeKit'
end
