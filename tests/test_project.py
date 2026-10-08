import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "src" / "GameMode.ps1").read_text(encoding="utf-8")
MANAGER = (ROOT / "scripts" / "Manage.ps1").read_text(encoding="utf-8")

class ProjectStructureTests(unittest.TestCase):
    def test_version_is_initial(self):
        self.assertEqual((ROOT / "VERSION").read_text().strip(), "0.1.0")
        cfg = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
        self.assertEqual(cfg["version"], "0.1.0")
        self.assertEqual(cfg["schemaVersion"], 1)

    def test_three_initial_game_profiles(self):
        profiles = {
            f.stem: json.loads(f.read_text(encoding="utf-8"))
            for f in (ROOT / "profiles").glob("*.json")
        }
        self.assertEqual(set(profiles), {"cs2", "rdr2", "msfs2024"})
        self.assertEqual(profiles["cs2"]["processName"], "cs2")
        self.assertEqual(profiles["rdr2"]["processName"], "RDR2")
        self.assertEqual(profiles["msfs2024"]["processName"], "FlightSimulator2024")

    def test_profiles_do_not_have_kill_lists(self):
        for f in (ROOT / "profiles").glob("*.json"):
            data = json.loads(f.read_text(encoding="utf-8"))
            with self.subTest(profile=f.name):
                self.assertFalse(
                    set(data).intersection({"closeApps", "stopServices", "killApps", "commands", "stopWSL"})
                )

    def test_safe_only(self):
        self.assertFalse(json.loads((ROOT / "config.json").read_text())["autoCloseProcesses"])
        self.assertFalse(json.loads((ROOT / "config.json").read_text())["stopServices"])
        for unsafe in ("Stop-Process -Force", "Stop-Service", "wsl.exe --shutdown",
                       "DisableRealtimeMonitoring", "Set-MpPreference", "bcdedit"):
            self.assertNotIn(unsafe.lower(), ENGINE.lower())

    def test_snapshot_and_restore(self):
        self.assertIn("Save-State $snapshot", ENGINE)
        self.assertIn("Restore-Registry", ENGINE)
        self.assertIn("Restore-Priorities", ENGINE)
        self.assertIn("Restore-Session", ENGINE)
        self.assertIn("oldPlan", ENGINE)

    def test_process_scan(self):
        for marker in ("Get-CimInstance Win32_Process", "Get-CimInstance Win32_Service",
                       "cpuDeltaSeconds", "review-only", "game-related", "interactive"):
            self.assertIn(marker, ENGINE)

    def test_startup_non_elevated(self):
        self.assertIn("New-ScheduledTaskTrigger -AtLogOn", MANAGER)
        self.assertIn("-RunLevel Limited", MANAGER)
        self.assertIn("LOCALAPPDATA", MANAGER)
        self.assertNotIn("-RunLevel Highest", MANAGER)

    def test_restoration_command(self):
        self.assertIn("stop.signal", MANAGER)
        self.assertIn("-Action Restore", MANAGER)

    def test_required_docs(self):
        for path in (
            "README.md", "CHANGELOG.md", "VERSION", "LICENSE", ".gitignore",
            "docs/ARCHITECTURE.md", "docs/PROCESS_POLICY.md",
            "docs/ADDING_GAMES.md", "docs/TESTING.md",
            "scripts/SelfTest.ps1", "INSTALAR.cmd", "RESTAURAR.cmd",
            "DESINSTALAR.cmd", "STATUS.cmd", "VERIFICAR.cmd", "REATIVAR.cmd"
        ):
            self.assertTrue((ROOT / path).is_file(), path)

    def test_no_old_version_names_in_current_docs(self):
        for path in (ROOT / "docs").glob("*.md"):
            doc = path.read_text(encoding="utf-8").lower()
            self.assertNotIn("v7", doc)
            self.assertNotIn("v8", doc)

if __name__ == "__main__":
    unittest.main()
