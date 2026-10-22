import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_build import prepare_spec


class BuildSpecTests(unittest.TestCase):
    def setUp(self):
        self.source = (Path(__file__).resolve().parents[2] / "project.yml").read_text(encoding="utf-8")

    def test_sdk_27_keeps_native_icon_and_enables_siri_schema(self):
        spec = prepare_spec(self.source, 27)
        self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) LEDGER_SIRI_AI"', spec)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: Ledger\n", spec)
        self.assertNotIn("Resources/LegacyIcon.xcassets", spec)

    def test_sdk_26_excludes_new_icon_and_uses_exported_appearances(self):
        spec = prepare_spec(self.source, 26)
        self.assertIn("excludes: [Info.plist, Ledger.icon]", spec)
        self.assertIn("Resources/LegacyIcon.xcassets", spec)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: LedgerFallback", spec)
        self.assertNotIn("LEDGER_SIRI_AI", spec)

    def test_old_build_tools_are_rejected(self):
        with self.assertRaises(ValueError):
            prepare_spec(self.source, 16)


if __name__ == "__main__":
    unittest.main()
