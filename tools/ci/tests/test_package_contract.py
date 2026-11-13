"""Read-only packaging/installer contract tests.

Never execute installation, App replacement, driver installation, or CoreAudio actions.
"""
import plistlib
import subprocess
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PLIST = ROOT / "remote-orbit/Packaging/Info.plist"
ICON = ROOT / "remote-orbit/Brand/RemoteOrbitMark.svg"


class RemoteOrbitPackagingContractTests(unittest.TestCase):
    def test_app_info_plist_has_required_bundle_metadata(self):
        with PLIST.open("rb") as data:
            info = plistlib.load(data)
        self.assertEqual(info["CFBundleIdentifier"], "com.lost0rz.RemoteOrbit")
        self.assertEqual(info["CFBundleExecutable"], "RemoteOrbit")
        self.assertEqual(info["CFBundlePackageType"], "APPL")
        self.assertEqual(info["LSMinimumSystemVersion"], "13.0")
        self.assertTrue(info["CFBundleShortVersionString"])
        self.assertTrue(info["CFBundleVersion"])

    def test_icon_source_is_a_valid_svg(self):
        self.assertTrue(ICON.is_file())
        root = ET.parse(ICON).getroot()
        self.assertTrue(root.tag.endswith("svg"), root.tag)

    def test_install_and_packaging_scripts_are_syntax_checked_never_executed(self):
        scripts = [
            ROOT / "package-dmg.sh", ROOT / "LaunchRemoteOrbit.command",
            *(ROOT / "remote-orbit").rglob("*.sh"),
            *(ROOT / "remote-orbit-audio-driver").rglob("*.sh"),
            *(ROOT / "installer/pkg-scripts").iterdir(),
        ]
        self.assertTrue(scripts)
        for script in sorted(set(scripts)):
            if not script.is_file():
                continue
            with self.subTest(script=script.relative_to(ROOT).as_posix()):
                first_line = script.read_text(encoding="utf-8").splitlines()[0]
                self.assertTrue(first_line.startswith("#!"), str(script))
                shell = "/bin/zsh" if "zsh" in first_line else "/bin/bash"
                result = subprocess.run([shell, "-n", str(script)],
                                        capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
