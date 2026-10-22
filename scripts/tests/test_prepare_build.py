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

    def test_sdk_26_uses_native_icon_without_siri_27_schema(self):
        spec = prepare_spec(self.source, 26)
        self.assertNotIn("Resources/LegacyIcon.xcassets", spec)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: Ledger\n", spec)
        self.assertNotIn("LEDGER_SIRI_AI", spec)

    def test_icon_does_not_double_apply_glass_or_shadows(self):
        import json
        icon = Path(__file__).resolve().parents[2] / "FinancialApp/Ledger.icon/icon.json"
        data = json.loads(icon.read_text())
        self.assertNotIn("refractivity", data.get("features", []))
        for group in data["groups"]:
            self.assertFalse(group["specular"])
            self.assertEqual(group["shadow"]["opacity"], 0)
            self.assertTrue(all(not layer["glass"] for layer in group["layers"]))

    def test_old_build_tools_are_rejected(self):
        with self.assertRaises(ValueError):
            prepare_spec(self.source, 16)

    def test_widget_and_control_targets_share_local_snapshot_and_intent_sources(self):
        root = Path(__file__).resolve().parents[2]
        self.assertEqual(self.source.count('- path: Shared'), 2)
        self.assertIn('LEDGER_WIDGET_EXTENSION', self.source)
        self.assertIn('LEDGER_APP_GROUP: group.com.mikhael.FinancialApp', self.source)
        import plistlib
        for file in ['FinancialApp/Info.plist', 'LedgerWidgets/Info.plist']:
            with open(root / file, 'rb') as stream:
                self.assertEqual(plistlib.load(stream)['LedgerAppGroup'], '$(LEDGER_APP_GROUP)')
        with open(root / 'Shared/Ledger.entitlements', 'rb') as stream:
            self.assertEqual(plistlib.load(stream)['com.apple.security.application-groups'], ['$(LEDGER_APP_GROUP)'])

    def test_app_identity_and_face_id_permission_are_present(self):
        import plistlib
        root = Path(__file__).resolve().parents[2]
        with open(root / 'FinancialApp/Info.plist', 'rb') as stream:
            info = plistlib.load(stream)
        self.assertEqual(info['CFBundleDisplayName'], 'Ledger')
        self.assertEqual(info['CFBundleName'], 'Ledger')
        self.assertTrue(info['NSFaceIDUsageDescription'].strip())
        self.assertEqual(info['CFBundleExecutable'], '$(EXECUTABLE_NAME)')
        self.assertIn('LocalAuthentication.framework', self.source)


if __name__ == "__main__":
    unittest.main()
