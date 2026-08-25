from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text()

preflight_anchor = "    var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict {"
helper = """    var applicationEvidenceSurvivedHistoricalWindow: Bool {
        guard let authenticatedAt = ledgerSnapshot.authenticatedAtUptimeNanoseconds,
              let latestPayload = ledgerSnapshot.latestApplicationPayloadUptimeNanoseconds,
              latestPayload >= authenticatedAt else { return false }
        return latestPayload - authenticatedAt >= TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
    }

"""
if "var applicationEvidenceSurvivedHistoricalWindow: Bool" in text:
    raise SystemExit("application-survival presentation helper already exists unexpectedly")
if text.count(preflight_anchor) != 1:
    raise SystemExit(f"preflight insertion anchor count was {text.count(preflight_anchor)}, expected 1")
text = text.replace(preflight_anchor, helper + preflight_anchor, 1)

old_copy = "Waiting for a genuine application update and the canonical 45-second horizon…"
new_copy = "Waiting for repeated same-generation scooter data to survive the startup rejection window and the canonical 45-second stability horizon…"
if text.count(old_copy) != 1:
    raise SystemExit(f"authentication-copy anchor count was {text.count(old_copy)}, expected 1")
text = text.replace(old_copy, new_copy, 1)

old_row = '                        requirementRow("Scooter data received", ready: test.applicationUpdateCount > 0)'
new_rows = """                        requirementRow("Repeated scooter data", ready: test.applicationUpdateCount >= TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount)
                        requirementRow("Startup window survived", ready: test.applicationEvidenceSurvivedHistoricalWindow)"""
if text.count(old_row) != 1:
    raise SystemExit(f"observation-row anchor count was {text.count(old_row)}, expected 1")
text = text.replace(old_row, new_rows, 1)

path.write_text(text)
