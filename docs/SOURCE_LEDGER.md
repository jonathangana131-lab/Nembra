# Source ledger

Research date: 2026-08-04. Links are starting points, not automatic truth; storefront specs are intentionally cross-checked against owner-unit evidence.

## MAXSHOT / V1S Pro
- MAXSHOT shop: https://shopmaxshot.com/
- BikeIndex real-owner V1 SPRO examples: https://bikeindex.org/bikes/2866633 and https://bikeindex.org/bikes/2828544
- AOVO PRO/MAXSHOT V1SPRO product-family imagery: https://www.aovopro.com/product/maxshot-v1spro-electric-scooter-350w-dual-suspension-turn-signals-foldable-us/
- Broader MAXSHOT reference site used only for cross-checking inconsistent marketing claims: https://maxshotscooter.com/

## Apple — Bluetooth/accessory setup
- Core Bluetooth: https://developer.apple.com/documentation/corebluetooth
- TN3115 Bluetooth State Restoration app relaunch rules: https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules
- CBCentralManager: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager
- Central Manager State Restoration Options: https://developer.apple.com/documentation/corebluetooth/central-manager-state-restoration-options
- CBCentralManagerOptionRestoreIdentifierKey: https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey
- Core Bluetooth background processing guide: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- AccessorySetupKit: https://developer.apple.com/documentation/accessorysetupkit
- Discovering/configuring accessories: https://developer.apple.com/documentation/accessorysetupkit/discovering-and-configuring-accessories

## Apple — location/maps
- Handling location updates in the background: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- Accessing the device's location efficiently: https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently
- CLBackgroundActivitySession: https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession
- MKDirectionsTransportType: https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype
- Cycling directions: https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/cycling

## YouFS public capability references
- Official YouFs-A App Store listing: https://apps.apple.com/us/app/youfs-a/id1615712353 — describes live vehicle info, lock, speed, power, lights, gear, total/trip mileage, riding time, start mode, battery voltage, fault status, and says the speed of each gear can be adjusted.
- Google Play YouFs-A listing: https://play.google.com/store/apps/details?id=com.yongfengshun — mirrors the same developer capability description.

These are generic YouFS capabilities, not proof of DP numbers or exact behavior on the user's MAXSHOT production batch.

## Prior protocol audit
The repository intentionally carries forward protocol facts already established in the user's prior MAXSHOT/YouFS research, while rejecting the prior disposable UI/prototype architecture. See `PROTOCOL_NOTES.md` for the strict verified/probable/unknown split.
