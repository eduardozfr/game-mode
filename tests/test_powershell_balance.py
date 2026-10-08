from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PowerShellBalanceTests(unittest.TestCase):
    def test_balanced_braces(self):
        for script in ROOT.rglob("*.ps1"):
            text = script.read_text(encoding="utf-8")
            # This is only a basic lexical check; scripts/SelfTest.ps1 uses the real PowerShell parser.
            self.assertEqual(text.count("{"), text.count("}"), script.name)

if __name__ == "__main__":
    unittest.main()
