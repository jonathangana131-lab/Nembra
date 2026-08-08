#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/es80_signed_field_artifact_evidence.py")
text = path.read_text()

start = text.index("def _profile_value_authorizes(")
end = text.index("\n\ndef _valid_intended_device_udid", start)
replacement = '''WILDCARD_PROFILE_ENTITLEMENT_KEYS = frozenset({"keychain-access-groups"})


def _profile_value_authorizes(
    entitlement_key: str,
    profile_value: object,
    signed_value: object,
) -> bool:
    if isinstance(signed_value, str):
        if isinstance(profile_value, str):
            if (
                entitlement_key in WILDCARD_PROFILE_ENTITLEMENT_KEYS
                and profile_value.endswith("*")
            ):
                return signed_value.startswith(profile_value[:-1])
            return signed_value == profile_value
        if isinstance(profile_value, list):
            return any(
                _profile_value_authorizes(entitlement_key, candidate, signed_value)
                for candidate in profile_value
            )
        return False
    if isinstance(signed_value, list):
        if not isinstance(profile_value, list):
            return False
        return all(
            any(
                _profile_value_authorizes(entitlement_key, candidate, item)
                for candidate in profile_value
            )
            for item in signed_value
        )
    if isinstance(signed_value, dict):
        if not isinstance(profile_value, dict):
            return False
        return all(
            key in profile_value
            and _profile_value_authorizes(entitlement_key, profile_value[key], value)
            for key, value in signed_value.items()
        )
    return profile_value == signed_value
'''
text = text[:start] + replacement + text[end:]

old_call = "if key not in entitlements or not _profile_value_authorizes(entitlements[key], value):"
new_call = "if key not in entitlements or not _profile_value_authorizes(key, entitlements[key], value):"
if text.count(old_call) != 1:
    raise SystemExit("expected exactly one provisioning authorization call site")
text = text.replace(old_call, new_call)

marker = '''    assert application_id == f"{team}.{BUNDLE_ID}"

    bad_profiles = (
'''
if text.count(marker) != 1:
    raise SystemExit("self-test insertion marker drifted")
regression = '''    assert application_id == f"{team}.{BUNDLE_ID}"

    # Provisioning wildcard behavior is entitlement-specific. Exact equality is the default.
    unknown_wildcard_profile = {
        **valid_profile,
        "Entitlements": {
            **valid_profile["Entitlements"],
            "com.example.future": "allowed.*",
        },
    }
    unknown_wildcard_signed = {
        **valid_entitlements,
        "com.example.future": "allowed.value",
    }
    try:
        validate_provisioning_profile(
            unknown_wildcard_profile,
            team_identifier=team,
            bundle_identifier=BUNDLE_ID,
            signed_entitlements=unknown_wildcard_signed,
            signing_certificate_der=leaf_certificate,
            intended_device_udid=device,
            now=datetime(2098, 1, 1, tzinfo=timezone.utc),
        )
    except EvidenceError:
        pass
    else:
        raise AssertionError("unknown entitlement inherited wildcard authorization semantics")

    exact_unknown_profile = {
        **valid_profile,
        "Entitlements": {
            **valid_profile["Entitlements"],
            "com.example.future": "allowed.value",
        },
    }
    validate_provisioning_profile(
        exact_unknown_profile,
        team_identifier=team,
        bundle_identifier=BUNDLE_ID,
        signed_entitlements=unknown_wildcard_signed,
        signing_certificate_der=leaf_certificate,
        intended_device_udid=device,
        now=datetime(2098, 1, 1, tzinfo=timezone.utc),
    )

    bad_profiles = (
'''
text = text.replace(marker, regression)

if 'WILDCARD_PROFILE_ENTITLEMENT_KEYS = frozenset({"keychain-access-groups"})' not in text:
    raise SystemExit("wildcard entitlement allowlist missing")
if '_profile_value_authorizes(key, entitlements[key], value)' not in text:
    raise SystemExit("entitlement key is not threaded through authorization")
if 'unknown entitlement inherited wildcard authorization semantics' not in text:
    raise SystemExit("unknown-key wildcard regression missing")

path.write_text(text)
