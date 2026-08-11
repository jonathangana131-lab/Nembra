from pathlib import Path


INSTALLER = Path("scripts/field/install_one_time_capture.command")

OLD = '''    source = subprocess.check_output(
        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],
        cwd=root,
        stderr=subprocess.DEVNULL,
    )'''

NEW = '''    git_environment = {
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "LANG": "C",
        "LC_ALL": "C",
    }
    source = subprocess.check_output(
        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )'''


def main() -> None:
    text = INSTALLER.read_text(encoding="utf-8")
    count = text.count(OLD)
    if count != 1:
        raise SystemExit(
            f"accepted-source runner changed unexpectedly; expected one exact block, found {count}"
        )
    INSTALLER.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")


if __name__ == "__main__":
    main()
