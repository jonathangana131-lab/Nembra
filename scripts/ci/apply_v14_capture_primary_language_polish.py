from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text(encoding="utf-8")

replacements = [
    (
        '"The next step is passive Bluetooth correlation. Keep the scooter stationary and begin with it powered off."',
        '"Next, Nembra will match this scooter by its OFF → ON → OFF → ON signal pattern. Keep the scooter stationary and begin with it powered off."',
    ),
    (
        '"Capture stays locked until the exact field build, Tuya SDK session, and this scooter\'s current account membership are all proven."',
        '"Capture stays locked until this Capture build, your Tuya account, and this scooter in that account are all confirmed."',
    ),
    ('requirementRow("Exact field build", ready: test.fieldBuildIsAuthoritative)', 'requirementRow("Capture build", ready: test.fieldBuildIsAuthoritative)'),
    ('requirementRow("Official Tuya SDK", ready: test.privateConfig)', 'requirementRow("Tuya secure service", ready: test.privateConfig)'),
    ('"Starts the first passive Bluetooth correlation window."', '"Starts the first read-only signal check with the scooter powered off."'),
    (
        '"One Bluetooth target repeated through the full OFF → ON → OFF → ON pattern. Confirm it for this attempt before Tuya takes over the secure link."',
        '"One nearby signal repeated through the full OFF → ON → OFF → ON pattern. Confirm this signal for the current attempt before Nembra opens the secure read-only link."',
    ),
    ('"Finishes only when the package-owned scan window has earned its required evidence duration."', '"Finishes only after this read-only signal check has run long enough to be valid."'),
    ('"Historical UUID, name, RSSI, FD50, and Tuya hints never authorize the target."', '"Only the full OFF → ON → OFF → ON pattern can authorize the nearby signal for this attempt."'),
    ('Text("Target confirmed")', 'Text("Scooter signal confirmed")'),
    (
        '"Tuya can now become the sole Bluetooth owner. Capture remains read-only. No DP query or scooter command is authorized by this surface."',
        '"Nembra can now open the secure Tuya link. Capture stays read-only and cannot send scooter commands."',
    ),
    ('"Tuya owns Bluetooth now. Capture is waiting for the supported local session to become current."', '"Tuya owns the secure Bluetooth link now. Capture is waiting for this scooter\'s current read-only session."'),
    (
        '"Keep Capture in the foreground and leave the scooter untouched while the accepted observation horizon is earned."',
        '"Keep Capture in the foreground and leave the scooter untouched until this read-only observation is complete."',
    ),
    ('Text("Authenticated observation")', 'Text("Read-only observation")'),
    ('"Restore the missing prerequisite below. The failed attempt is not reused as evidence."', '"Restore the missing requirement below. This stopped attempt will not be reused."'),
    (
        '"Nothing was promoted after the blocker. Re-establish the required field authority, then begin a fresh OFF1 attempt."',
        '"Nothing from the stopped attempt will carry forward. Restore the required setup, then begin again with the scooter powered off."',
    ),
    (
        '"The prior session generation was not proven retired in-process, so Capture will not offer an OFF1 restart here."',
        '"The previous secure session did not fully close inside the app, so Capture will not start another attempt until you relaunch."',
    ),
    ('case .baseline, .scanning, .powerOn, .correlated: return "TARGET CORRELATION"', 'case .baseline, .scanning, .powerOn, .correlated: return "FIND SCOOTER"'),
    (
        '"No evidence was promoted past the blocker. Restore the required prerequisite, then restart from scooter OFF."',
        '"Nothing from the stopped attempt will carry forward. Restore the missing requirement, then restart with the scooter powered off."',
    ),
    (
        '"No evidence was promoted past the blocker. This session is not proven retired; relaunch Capture before another attempt."',
        '"The stopped attempt cannot be safely retired inside the app. Relaunch Capture before another attempt."',
    ),
    ('"A fresh four-window power pattern identifies the nearby Bluetooth target for this attempt only."', '"The OFF → ON → OFF → ON signal pattern identifies the nearby scooter for this attempt only."'),
    ('"Tuya becomes the sole Bluetooth owner while Capture stays read-only."', '"Nembra opens one secure Tuya connection while Capture stays read-only."'),
    (
        '"Keep the scooter stationary and Capture in the foreground until the accepted horizon is sealed."',
        '"Keep the scooter stationary and Capture in the foreground until the read-only observation is complete."',
    ),
    ('"Everything required for a passive current-attempt target correlation is ready."', '"Everything required to find this scooter by its current signal pattern is ready."'),
    ('"Prove the exact field build and same-account Tuya authority before Bluetooth starts."', '"Confirm this Capture build and the Tuya account that owns the scooter before Bluetooth starts."'),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one primary-language source match, found {count}: {old}")
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
