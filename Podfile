source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'

# Nembra Capture's authenticated Tuya BLE experiment must use Tuya's official
# SmartLife App SDK. This file intentionally contains no AppKey, AppSecret,
# account credential, local_key, session key, or other private material.
#
# Tuya's app-specific security SDK is downloaded from the Developer Platform as
# ios_core_sdk.tar.gz. Extract its Build directory and ThingSmartCryption.podspec
# beneath ignored LocalSecrets/TuyaSDK before running the bootstrap script.
#
# AppKey/AppSecret are generated separately into an ignored local Swift pod under
# LocalSecrets/TuyaRuntime. They never travel through xcodebuild/devicectl argv.
project 'NembraCapture.xcodeproj'

target 'Nembra Capture' do
  # App-specific security component. This path is intentionally ignored by git.
  pod 'ThingSmartCryption', :path => './LocalSecrets/TuyaSDK'

  # Local-only app identity compiled into the private field workspace. The public
  # standalone .xcodeproj does not consume this pod and therefore remains fail-closed.
  pod 'NembraTuyaPrivateConfig', :path => './LocalSecrets/TuyaRuntime'

  # SmartLife App SDK 7.8.0 is the current iOS line documented by Tuya.
  pod 'ThingSmartHomeKit', '~> 7.8.0'
  pod 'ThingSmartBusinessExtensionKit', '~> 7.8.0'

  # Do not add pairing/activation BizBundles or BLEExtra merely to make the
  # authenticated observation experiment work. The already-activated-device
  # connection API is documented on ThingSmartBLEManager; activation remains
  # outside this read-only test's authority.
end
