#!/usr/bin/env python3
"""Exercise installer files in a temporary filesystem; no global install or launch."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

scripts = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="catchtype-install-test-") as directory:
    root = Path(directory).resolve()
    apps, localbin, mockbin = (root / name for name in ("Applications", "localbin", "mocks"))
    for path in (apps, localbin, mockbin, root / "build", root / "home"):
        path.mkdir()
    env = dict(os.environ, HOME=str(root / "home"), TEST_ROOT=str(root),
               PATH=f"{mockbin}:{os.environ['PATH']}")
    for name in ("catchtype", "CatchTypeApp"):
        binary = root / "build" / name
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)
    mocks = {
        "uname": 'echo Darwin',
        "swift": 'case "$*" in *--show-bin-path*) echo "$TEST_ROOT/build";; esac',
        "codesign": 'exit 0',
        "plutil": 'exit 0',
        "ditto": 'cp -R "$1" "$2"',
        "sudo": 'exec "$@"',
        "ps": '''case "$*" in
    *-axo*)
      if [ -f "$TEST_ROOT/running" ]; then echo "123 $(id -u) $TEST_ROOT/Applications/CatchType.app/Contents/MacOS/CatchType"; fi
      echo "456 $(id -u) $TEST_ROOT/build/CatchTypeApp" ;;
    *) if [ -f "$TEST_ROOT/running" ]; then echo "$TEST_ROOT/Applications/CatchType.app/Contents/MacOS/CatchType"; fi ;;
esac''',
        "kill": '''[ "$*" = "-TERM 123" ] || exit 99
if [ ! -f "$TEST_ROOT/refuse-stop" ]; then rm -f "$TEST_ROOT/running"; fi
echo "$*" >> "$TEST_ROOT/kills"''',
        "sleep": 'exit 0',
        "launchctl": '''if [ "$1" = bootstrap ] && [ -f "$TEST_ROOT/fail-bootstrap" ]; then
    rm "$TEST_ROOT/fail-bootstrap"
    exit 1
fi''',
    }
    for name, body in mocks.items():
        path = mockbin / name
        path.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
        path.chmod(0o755)
    for name in ("install.sh", "uninstall.sh", "install-common.sh"):
        # Redirect fixed system destinations in a test copy, preserving production defaults.
        source = (scripts / name).read_text().replace("/Applications", str(apps)).replace("/usr/local/bin", str(localbin)).replace("/bin/kill", str(mockbin / "kill"))
        (root / name).write_text(source)

    def run(name, expected=0):
        result = subprocess.run(["bash", str(root / name)], env=env, capture_output=True, text=True)
        assert result.returncode == expected, result.stdout + result.stderr

    (root / "running").touch()
    run("install.sh")
    assert not (root / "running").exists(), "stop manually launched installed app on update"
    bundle = apps / "CatchType.app"
    cli = localbin / "catchtype"
    plist = root / "home/Library/LaunchAgents/app.catchtype.macos.plist"
    assert (bundle / "Contents/MacOS/CatchType").is_file()
    assert cli.resolve() == bundle / "Contents/Helpers/catchtype"
    assert plist.is_file(), "LaunchAgents must be created on a fresh account"
    launch_config = plistlib.loads(plist.read_bytes())
    assert launch_config["RunAtLoad"] is True
    assert launch_config["KeepAlive"] == {"SuccessfulExit": False}, "menu Quit must stay stopped; crashes restart"
    old_app = bundle / "Contents/MacOS/CatchType"
    old_app.write_text("previous app\n")
    old_plist = plist.read_text()
    (root / "fail-bootstrap").touch()
    run("install.sh", expected=1)
    assert old_app.read_text() == "previous app\n", "failed update must restore old app"
    assert plist.read_text() == old_plist
    assert cli.resolve() == bundle / "Contents/Helpers/catchtype"
    assert not list(apps.glob(".catchtype.*")), "destination staging must be removed"
    (root / "running").touch()
    (root / "refuse-stop").touch()
    run("uninstall.sh", expected=1)
    assert bundle.exists() and plist.exists(), "do not remove an app that did not stop"
    (root / "refuse-stop").unlink()
    run("uninstall.sh")
    assert not (root / "running").exists(), "stop manually launched installed app on uninstall"
    assert not bundle.exists() and not cli.is_symlink() and not plist.exists()
    (root / "fail-bootstrap").touch()
    run("install.sh", expected=1)
    assert not bundle.exists() and not cli.is_symlink() and not plist.exists(), "failed fresh install must roll back"
    cli.write_text("unrelated executable\n")
    run("install.sh", expected=1)
    assert cli.read_text() == "unrelated executable\n", "do not replace an unrelated regular file"
    assert not bundle.exists()
    cli.unlink()
    cli.symlink_to(root / "unrelated/.build/release/catchtype")
    run("install.sh", expected=1)
    run("uninstall.sh")
    assert cli.is_symlink(), "preserve other repositories' build links"
    cli.unlink()
    cli.symlink_to(root.parent / ".build/release/catchtype")
    run("install.sh")
    assert cli.resolve() == bundle / "Contents/Helpers/catchtype", "upgrade known legacy build link"
    run("uninstall.sh")
    assert set((root / "kills").read_text().splitlines()) == {"-TERM 123"}, "never stop debug binary"
print("installer selfcheck: fresh install, failed update/fresh rollback, uninstall, unrelated file/link protection, exact installed process shutdown passed")
