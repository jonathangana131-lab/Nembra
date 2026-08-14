#!/usr/bin/env python3
"""One-shot exact-head materializer for the validated Capture retirement repair."""

from __future__ import annotations

from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one {label}, found {count}")
    return text.replace(old, new)


def replace_region(text: str, start_marker: str, end_marker: str, replacement: str, label: str) -> str:
    if text.count(start_marker) != 1 or text.count(end_marker) != 1:
        raise SystemExit(f"could not uniquely locate {label}")
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + replacement.rstrip() + "\n\n\n" + text[end:]


def replace_test(text: str, start_name: str, next_name: str, replacement: str) -> str:
    return replace_region(
        text,
        f"    def {start_name}(",
        f"    def {next_name}(",
        replacement,
        start_name,
    )


def patch_helper() -> None:
    path = Path("scripts/ci/capture_signed_app_build_origin_custody.py")
    source = path.read_text(encoding="utf-8")

    assertion = '''def _direct_local_identity_record_exists(kind: str, name: str) -> bool:
    completed = subprocess.run(
        ["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    detail = ((completed.stdout or "") + "\\n" + (completed.stderr or "")).strip()
    if completed.returncode == 0:
        return True
    if "eDSRecordNotFound" in detail or "-14136" in detail:
        return False
    raise BuildOriginCustodyError(
        f"could not classify direct Directory Services {kind} record: "
        f"rc={completed.returncode} detail={detail[-800:]!r}"
    )


def _assert_local_build_identity_retired(name: str, uid: int, *, timeout: float = 6.0) -> None:
    if uid <= 0:
        raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")
    deadline = time.monotonic() + timeout
    latest_live: tuple[int, ...] = ()
    latest_zombies: tuple[int, ...] = ()
    latest_user_record = True
    latest_group_record = True
    while True:
        latest_live, latest_zombies = _process_state_for_uid(uid)
        latest_user_record = _direct_local_identity_record_exists("Users", name)
        latest_group_record = _direct_local_identity_record_exists("Groups", name)
        if not latest_live and not latest_zombies and not latest_user_record and not latest_group_record:
            return
        if time.monotonic() >= deadline:
            break
        subprocess.run(
            ["/usr/bin/dscacheutil", "-flushcache"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        time.sleep(0.05)
    raise BuildOriginCustodyError(
        "ephemeral build destructive authority survived retirement: "
        f"live_pids={list(latest_live)} zombie_pids={list(latest_zombies)} "
        f"user_record={latest_user_record} group_record={latest_group_record}"
    )'''
    source = replace_region(
        source,
        "def _assert_local_build_identity_retired(",
        "def _remove_local_build_identity(",
        assertion,
        "retirement assertion",
    )

    remover = '''def _remove_local_build_identity(name: str, uid: int | None, *, require_absent: bool = False) -> None:
    if sys.platform != "darwin":
        return
    if require_absent and (uid is None or uid <= 0):
        raise BuildOriginCustodyError("cannot verify retirement for a missing build UID")
    if uid is not None and uid > 0:
        killed = subprocess.run(
            ["/usr/bin/pkill", "-9", "-u", str(uid), ".*"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if require_absent and killed.returncode not in (0, 1):
            raise BuildOriginCustodyError(
                f"could not request initial build-principal process retirement: pkill exit {killed.returncode}"
            )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)
    if require_absent:
        final_kill = subprocess.run(
            ["/usr/bin/pkill", "-9", "-u", str(uid), ".*"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if final_kill.returncode not in (0, 1):
            raise BuildOriginCustodyError(
                f"could not request final build-principal process retirement: pkill exit {final_kill.returncode}"
            )
        _assert_local_build_identity_retired(name, uid)'''
    source = replace_region(
        source,
        "def _remove_local_build_identity(",
        "def _create_local_build_identity(",
        remover,
        "identity remover",
    )

    if source.count('["/usr/bin/pkill", "-9", "-u", str(uid), ".*"]') != 2:
        raise SystemExit("post-DS candidate must contain exactly two UID-wide kills")
    compile(source, str(path), "exec", dont_inherit=True)
    path.write_text(source, encoding="utf-8")


def patch_provenance() -> None:
    path = Path(".github/workflows/capture-field-build-provenance.yml")
    source = path.read_text(encoding="utf-8")
    source = replace_once(
        source,
        "grep -Fq '**_structured_credentials(build_uid, build_gid, ())' \"$build_origin_custody\"",
        "grep -Fq '**_structured_credentials(uid, gid, ())' \"$build_origin_custody\"",
        "stale structured-credential provenance oracle",
    )
    anchor = "          grep -Fq 'def _assert_local_build_identity_retired(' \"$build_origin_custody\"\n"
    addition = (
        anchor
        + "          grep -Fq 'def _direct_local_identity_record_exists(' \"$build_origin_custody\"\n"
        + "          grep -Fq '\"eDSRecordNotFound\" in detail or \"-14136\" in detail' \"$build_origin_custody\"\n"
        + "          grep -Fq 'if not latest_live and not latest_zombies and not latest_user_record and not latest_group_record:' \"$build_origin_custody\"\n"
        + "          test \"$(grep -Fc '[\"/usr/bin/pkill\", \"-9\", \"-u\", str(uid), \".*\"]' \"$build_origin_custody\")\" = '2'\n"
    )
    source = replace_once(source, anchor, addition, "provenance retirement anchor")
    path.write_text(source, encoding="utf-8")


def patch_tests() -> None:
    path = Path("scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py")
    source = path.read_text(encoding="utf-8")
    source = replace_once(
        source,
        '        self.assertIn("_wait_for_no_live_uid(uid)", source)\n',
        '        self.assertIn("def _direct_local_identity_record_exists(", source)\n'
        '        self.assertIn("if not latest_live and not latest_zombies and not latest_user_record and not latest_group_record:", source)\n'
        '        self.assertEqual(source.count(\'["/usr/bin/pkill", "-9", "-u", str(uid), ".*"]\'), 2)\n',
        "pre-DS source assertion",
    )

    verified = '''    def test_verified_identity_retirement_requires_zero_process_and_direct_ds_authority(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_retirement")
        with (
            mock.patch.object(helper, "_process_state_for_uid", return_value=((), ())),
            mock.patch.object(helper, "_direct_local_identity_record_exists", return_value=False),
        ):
            helper._assert_local_build_identity_retired("nembrabuildtest", 55001)

        for process_state in (((1234,), ()), ((), (1234,))):
            with (
                self.subTest(process_state=process_state),
                mock.patch.object(helper, "_process_state_for_uid", return_value=process_state),
                mock.patch.object(helper, "_direct_local_identity_record_exists", return_value=False),
                self.assertRaises(helper.BuildOriginCustodyError),
            ):
                helper._assert_local_build_identity_retired("nembrabuildtest", 55001, timeout=0)

        with (
            mock.patch.object(helper, "_process_state_for_uid", return_value=((), ())),
            mock.patch.object(
                helper,
                "_direct_local_identity_record_exists",
                side_effect=lambda kind, _name: kind == "Users",
            ),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._assert_local_build_identity_retired("nembrabuildtest", 55001, timeout=0)

        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._assert_local_build_identity_retired("nembrabuildtest", 0)'''
    source = replace_test(
        source,
        "test_verified_identity_retirement_requires_no_live_uid_or_identity_lookup",
        "test_strict_identity_removal_proves_zero_live_uid_before_directory_service_deletion",
        verified,
    )

    strict = '''    def test_strict_identity_removal_deletes_ds_before_final_uid_quiescence(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_strict_retirement")
        events: list[str] = []

        def run_side_effect(argv, **_kwargs):
            if argv[:3] == ["/usr/bin/pkill", "-9", "-u"]:
                events.append("pkill")
            elif argv[:3] == ["/usr/bin/dscl", ".", "-delete"]:
                if argv[3].startswith("/Users/"):
                    events.append("delete-user")
                elif argv[3].startswith("/Groups/"):
                    events.append("delete-group")
            return mock.Mock(returncode=0)

        def verify_side_effect(_name, _uid):
            events.append("verify-direct-authority")

        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.subprocess, "run", side_effect=run_side_effect),
            mock.patch.object(helper, "_wait_for_no_live_uid") as legacy_wait,
            mock.patch.object(
                helper,
                "_assert_local_build_identity_retired",
                side_effect=verify_side_effect,
            ),
        ):
            helper._remove_local_build_identity("nembrabuildtest", 55001, require_absent=True)

        self.assertEqual(events.count("pkill"), 2)
        first_kill = events.index("pkill")
        second_kill = len(events) - 1 - events[::-1].index("pkill")
        self.assertLess(first_kill, events.index("delete-user"))
        self.assertLess(events.index("delete-user"), events.index("delete-group"))
        self.assertLess(events.index("delete-group"), second_kill)
        self.assertLess(second_kill, events.index("verify-direct-authority"))
        legacy_wait.assert_not_called()'''
    source = replace_test(
        source,
        "test_strict_identity_removal_proves_zero_live_uid_before_directory_service_deletion",
        "test_strict_identity_removal_rejects_unclassifiable_pkill_failure",
        strict,
    )
    compile(source, str(path), "exec", dont_inherit=True)
    path.write_text(source, encoding="utf-8")


def main() -> None:
    patch_helper()
    patch_provenance()
    patch_tests()


if __name__ == "__main__":
    main()
