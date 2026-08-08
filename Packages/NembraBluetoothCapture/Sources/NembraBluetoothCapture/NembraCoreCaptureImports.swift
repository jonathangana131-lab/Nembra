import NembraCore

// TODAY field-ready compile bridge.
//
// NembraBluetoothCapture already declares NembraCore as a package dependency, but two
// long-lived Capture source files reference these public NembraCore capture-domain types
// without importing NembraCore in their individual Swift files. Xcode 27's package build
// correctly fails those unqualified references. Keep this tiny module-local bridge until
// the direct imports can be folded into those files without colliding with the active
// Capture-shell owner.
//
// This changes no capture behavior, evidence semantics, field authorization, Bluetooth
// operation, stationary/charger preflight, or write capability.
typealias PassiveBluetoothCaptureSession = NembraCore.PassiveBluetoothCaptureSession
typealias PassiveBluetoothCaptureJSON = NembraCore.PassiveBluetoothCaptureJSON
