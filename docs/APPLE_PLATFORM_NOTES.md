# Apple platform notes — iOS 27 research checkpoint

Date: 2026-08-04

These notes describe current public Apple behavior researched during development. Exact API availability and signatures must still be compiled against the installed iOS 27 SDK on macOS/Xcode before implementation is called complete.

## Core Bluetooth restoration and relaunch
- Opt into central-manager state restoration with a **stable persisted** `CBCentralManagerOptionRestoreIdentifierKey` and recreate the manager with that same identifier every launch.
- In scene-based apps, Apple explicitly says not to rely on launch options for restored central-manager identifiers; restore through `centralManager(_:willRestoreState:)`.
- Bluetooth restoration only helps when an app is actually pending on a Bluetooth action/event (for example scanning, connecting, or subscribed notifications) and the corresponding event occurs.
- Apple's current TN3115 table says an app removed from memory or crashed can be relaunched for eligible pending Bluetooth work, while a user force-quit is listed as **No**. The same technote has an iOS 26+ note tying relaunch behavior to accessories set up with AccessorySetupKit. Until this is validated with the real MAXSHOT flow, Nembra must continue to tell users that manually force-quitting can disable automatic background reconnection/ride detection and must never promise otherwise.
- Toggling Bluetooth fully off in Settings also prevents Bluetooth-state-restoration relaunch until conditions recover.

Architecture implication: central-manager identity, known peripheral identity, pending connection/subscription state, and restoration handling are long-lived service concerns, never SwiftUI-screen lifetime state.

## AccessorySetupKit
- AccessorySetupKit provides privacy-preserving Bluetooth/Wi-Fi accessory discovery and setup and can hand the app a Bluetooth identifier after the user authorizes an accessory.
- The app declares supported accessory traits such as Bluetooth names, company identifiers, or services. Nembra **cannot safely finalize these descriptors yet** because the MAXSHOT V1S Pro's exact advertisement name/services are still unverified.
- Once real advertisement/service capture exists, evaluate an AccessorySetupKit-first onboarding path before falling back to broad Core Bluetooth discovery.
- Apple notes the AccessorySetupKit sample itself requires real devices for Bluetooth testing; this part is a hardware-validation task, not a Simulator-only claim.

## iOS 26+ Bluetooth + Live Activity behavior
Apple's current Core Bluetooth overview says that in iOS 26 and later, when an app has an instantiated `CBManager` and starts a Live Activity before backgrounding, it can retain foreground-equivalent Bluetooth privileges for certain operations while backgrounded, including less-restricted scanning behavior.

Product rule: investigate this for an **actual active ride Live Activity** only. Do not create a fake Live Activity solely as a background-execution loophole.

## Background location
- Current Core Location guidance supports `CLBackgroundActivitySession` for legitimate ongoing background activity and `CLServiceSession` for authorization/service-session management.
- Apple notes that iOS normally suspends most background apps; queued location updates may be delivered when the app runs again. A background activity session is appropriate when timely updates are genuinely required, such as precise route tracking during an active workout/ride.
- If the process terminates while receiving eligible background location updates, the app must reconstruct the relevant service/session immediately on relaunch so queued updates can resume.
- Energy guidance explicitly says not to run high-frequency/high-accuracy location continuously when it is unnecessary.

Nembra implication: escalate location only after strong ride evidence, maintain it while an active ride genuinely needs route fidelity, then end/reduce it after ride completion.

## MapKit routing truth
`MKDirectionsTransportType` currently exposes `any`, `automobile`, `cycling`, `transit`, and `walking`. There is no dedicated public electric-scooter transport type in this API surface.

If Nembra uses cycling directions as a best-effort option, the product must label the routing basis honestly and must not claim the route is legally or physically scooter-safe.

## Liquid Glass
Use native SwiftUI glass APIs for interactive controls/chrome where they improve hierarchy and touch feedback. Do not turn the content layer into a stack of translucent cards. Keep information surfaces stable and readable on iPhone 12.
