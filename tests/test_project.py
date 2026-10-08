import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class GameModeTests(unittest.TestCase):
    def setUp(self):
        self.profiles = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in (ROOT / "profiles").glob("*.json")}
        self.engine = (ROOT / "src" / "GameMode.ps1").read_text(encoding="utf-8")

    def test_expected_profiles(self):
        self.assertEqual(set(self.profiles), {"cs2", "rdr2", "msfs2024"})
        self.assertEqual(self.profiles["cs2"]["processName"], "cs2")
        self.assertEqual(self.profiles["rdr2"]["processName"], "RDR2")
        self.assertEqual(self.profiles["msfs2024"]["processName"], "FlightSimulator2024")

    def test_valid_settings(self):
        cfg = json.loads((ROOT / "config.json").read_text())
        self.assertTrue(2 <= cfg["pollSeconds"] <= 15)
        self.assertTrue(5 <= cfg["exitGraceSeconds"] <= 120)

    def test_allowlisted_services(self):
        for profile in self.profiles.values():
            self.assertTrue(set(profile["stopServices"]) <= {"Spooler", "WSearch"})

    def test_safe_priority(self):
        self.assertIn("AboveNormal", self.engine)
        self.assertNotIn("PriorityClass = 'Realtime'", self.engine)

    def test_state_saved_before_changes(self):
        self.assertLess(self.engine.find("Save-State $snapshot"), self.engine.find("Set-GameRegistry $snapshot.registry"))
        self.assertIn("Restore-Services $state.services", self.engine)

    def test_installer(self):
        script = (ROOT / "scripts" / "Install.ps1").read_text()
        self.assertIn("New-ScheduledTaskTrigger -AtLogOn", script)
        self.assertIn("-RunLevel Highest", script)
        self.assertIn("PersonalGameModeV7", script)

    def test_restore(self):
        for path in ("Restore.ps1", "Uninstall.ps1"):
            content = (ROOT / "scripts" / path).read_text()
            self.assertIn("stop.signal", content)
            self.assertIn("-Action Restore", content)

    def test_files(self):
        for name in ("README.md", "LICENSE", ".gitignore", "docs/ARCHITECTURE.md", "docs/ADDING_GAMES.md", "docs/SAFETY.md", "docs/TESTING.md", "docs/PUBLISHING.md"):
            self.assertTrue((ROOT / name).is_file(), name)

    def test_no_corporate_branding(self):
        for path in ROOT.rglob("*"):
            if path.is_file() and path.suffix.lower() in {".ps1", ".json", ".md", ".cmd", ".py"}:
                self.assertNotIn("telecomsip", path.read_text(encoding="utf-8").lower())

if __name__ == "__main__":
    unittest.main()
