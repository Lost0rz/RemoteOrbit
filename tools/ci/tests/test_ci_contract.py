"""Contract checks for the project-owned RemoteOrbit Domain test catalog.

These do not run product tests or install any system components.
The authoritative router still lives in Engineering Governance.
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAPABILITIES = json.loads((ROOT / ".github/ci-capabilities.json").read_text(encoding="utf-8"))
WORKFLOW = (ROOT / ".github/workflows/remoteorbit-ci.yml").read_text(encoding="utf-8")
SUITE_DIR = ROOT / "remote-orbit/Tests/RemoteOrbitTests"


def matches(pattern, path):
    """Mirror the Governance path-glob rules: '*' never crosses a slash."""
    sections = ["^"]
    index = 0
    while index < len(pattern):
        if pattern.startswith("**/", index):
            sections.append("(?:.*/)?")
            index += 3
        elif pattern.startswith("**", index):
            sections.append(".*")
            index += 2
        elif pattern[index] == "*":
            sections.append("[^/]*")
            index += 1
        elif pattern[index] == "?":
            sections.append("[^/]")
            index += 1
        else:
            sections.append(re.escape(pattern[index]))
            index += 1
    return re.fullmatch("".join(sections) + "$", path) is not None


def selected(path):
    return [
        lane["id"]
        for lane in CAPABILITIES["tests"]
        if any(matches(pattern, path) for pattern in lane["paths"])
    ]


class RemoteOrbitCIRoutingContractTests(unittest.TestCase):
    def test_known_sources_and_tests_have_a_lane(self):
        for directory in ("remote-orbit/Sources", "remote-orbit/Tests"):
            for path in (ROOT / directory).rglob("*"):
                if not path.is_file():
                    continue
                rel = path.relative_to(ROOT).as_posix()
                with self.subTest(path=rel):
                    self.assertTrue(selected(rel), f"Source change would be unmapped: {rel}")

    def test_non_source_runtime_resources_and_ci_config_are_mapped(self):
        important = [
            ".github/ci-capabilities.json", ".github/workflows/remoteorbit-ci.yml",
            ".gitignore", "remote-orbit/SelfTests/main.swift",
            "remote-orbit/Brand/RemoteOrbitMark.svg", "remote-orbit/Packaging/Info.plist",
            "remote-orbit/Package.swift", "remote-orbit/run-self-tests.sh",
            "remote-orbit/package-app.sh", "remote-orbit/install-app.sh",
            "package-dmg.sh", "LaunchRemoteOrbit.command",
            "installer/pkg-scripts/preinstall", "installer/pkg-scripts/postinstall",
            "remote-orbit-audio-driver/build-driver.sh",
            "remote-orbit-audio-driver/install-driver.sh",
        ]
        for rel in important:
            with self.subTest(path=rel):
                self.assertTrue(selected(rel), rel)

    def test_ordinary_changes_select_only_relevant_lanes(self):
        self.assertEqual(selected(".github/workflows/remoteorbit-ci.yml"), ["ci-contracts"])
        self.assertEqual(selected(".github/ci-capabilities.json"), ["ci-contracts"])
        self.assertEqual(selected("remote-orbit/SelfTests/main.swift"), ["protocol-focused"])
        self.assertEqual(selected("remote-orbit/Sources/RemoteOrbit/VoiceReceiverReadiness.swift"),
                         ["voice-focused"])
        self.assertEqual(selected("remote-orbit/Sources/RemoteOrbit/AudioPipe.swift"),
                         ["audio-focused"])
        self.assertEqual(selected("remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsView.swift"),
                         ["shortcuts-focused", "settings-focused"])
        self.assertEqual(selected("remote-orbit/Package.swift"),
                         ["package-smoke", "swift-full"])
        self.assertEqual(selected("remote-orbit/Sources/RemoteOrbit/main.swift"),
                         ["protocol-focused", "audio-focused", "hid-focused", "voice-focused", "swift-build"])
        self.assertIn("package-contracts",
                      selected("tools/ci/tests/test_package_contract.py"))
        self.assertEqual(selected("remote-orbit/Tests/RemoteOrbitTests/VoiceShortcutEmitterTests.swift"),
                         ["shortcuts-focused"])
        self.assertEqual(selected("remote-orbit/Sources/RemoteOrbit/Diagnostics/DiagnosticCLI.swift"),
                         ["diagnostics-focused"])
        self.assertEqual(selected("remote-orbit/Brand/RemoteOrbitMark.svg"),
                         ["package-contracts", "package-smoke"])
        self.assertNotIn("swift-full", selected("remote-orbit/Tests/RemoteOrbitTests/VoicePressCoordinatorTests.swift"))

    def test_native_hid_and_dependency_changes_expand_safely(self):
        native = "native-hid-build"
        self.assertIn(native, selected(
            "remote-orbit/Sources/RemoteOrbitHIDBridge/RemoteOrbitHIDBridge.cpp"))
        self.assertIn(native, selected(
            "remote-orbit/Sources/RemoteOrbitHIDBridge/vendor/upstream/manifest.json"))
        self.assertIn(native, selected(
            "remote-orbit/Sources/RemoteOrbitHIDHelper/RemoteOrbitHIDHelper.swift"))
        self.assertIn(native, selected(
            "remote-orbit/Sources/RemoteOrbit/VoiceShortcutHID.swift"))
        self.assertIn("swift-full", selected("remote-orbit/Package.swift"))
        self.assertEqual(selected("remote-orbit/new-unknown-executable.bin"), [])

    def test_each_test_file_selects_a_lane_that_runs_its_xctest_class(self):
        suites = set()
        for file in sorted(SUITE_DIR.glob("*.swift")):
            rel = file.relative_to(ROOT).as_posix()
            classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b",
                                 file.read_text(encoding="utf-8"))
            self.assertTrue(classes, f"No XCTestCase class in {rel}")
            actions = [
                " ".join(lane["command"])
                for lane in CAPABILITIES["tests"] if lane["id"] in selected(rel)
            ]
            for classname in classes:
                with self.subTest(classname=classname):
                    self.assertTrue(any(re.search(r"\b" + re.escape(classname) + r"\b", cmd)
                                        for cmd in actions),
                                    f"{classname} is mapped but not actually selected")
                suites.add(classname)
        self.assertGreaterEqual(len(suites), 45)

    def test_no_normal_test_file_triggers_entire_swift_suite(self):
        for test in SUITE_DIR.glob("*.swift"):
            self.assertNotIn("swift-full", selected(test.relative_to(ROOT).as_posix()))
        self.assertFalse(CAPABILITIES["fallback_satisfies_ready"])
        self.assertEqual(CAPABILITIES["fallback_tests"], ["ci-contracts"])

    def test_resource_and_install_commands_have_no_host_side_effects(self):
        for lane in CAPABILITIES["tests"]:
            text = " ".join(lane["command"])
            text += " ".join(" ".join(step) for step in lane.get("setup", []))
            for unsafe in ("install-app.sh", "install-driver.sh", "coreaudiod",
                           "killall ", "sudo ", "open /Applications"):
                self.assertNotIn(unsafe, text, (lane["id"], unsafe))
            if lane.get("fork_safe"):
                self.assertNotIn("self-hosted", lane["runner"])
        self.assertFalse(CAPABILITIES["tests"][0].get("cwd") == "remote-orbit")

    def test_workflow_trust_and_milestone_main_push(self):
        self.assertIn("ci-router-reusable.yml@v0.10.1", WORKFLOW)
        self.assertNotIn("@v0.10.0", WORKFLOW)
        self.assertIn("  pull_request:", WORKFLOW)
        self.assertIn("  push:", WORKFLOW)
        self.assertIn("    branches: [main]", WORKFLOW)
        self.assertIn("  workflow_dispatch:", WORKFLOW)
        self.assertIn("Main push affected Domain plan", WORKFLOW)
        self.assertIn("Main push scoped test", WORKFLOW)
        self.assertIn("Main push scoped verification", WORKFLOW)
        self.assertIn("git -C project merge-base --is-ancestor", WORKFLOW)
        self.assertIn("MAIN_PUSH_SCOPE_UNVERIFIED", WORKFLOW)
        self.assertIn("MAIN_PUSH_SCOPED_TESTS_PASS", WORKFLOW)
        self.assertIn("github.event.pull_request.draft == false", WORKFLOW)
        self.assertNotIn("package-app.sh", WORKFLOW)
        self.assertNotIn("swift test", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
