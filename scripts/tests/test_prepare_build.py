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
        self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) TRACKR_SIRI_AI"', spec)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: Trackr\n", spec)
        self.assertNotIn("Resources/LegacyIcon.xcassets", spec)

    def test_sdk_26_uses_native_icon_without_siri_27_schema(self):
        spec = prepare_spec(self.source, 26)
        self.assertNotIn("Resources/LegacyIcon.xcassets", spec)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: Trackr\n", spec)
        self.assertNotIn("TRACKR_SIRI_AI", spec)

    def test_icon_does_not_double_apply_glass_or_shadows(self):
        import json
        icon = Path(__file__).resolve().parents[2] / "Trackr/Trackr.icon/icon.json"
        data = json.loads(icon.read_text())
        self.assertNotIn("refractivity", data.get("features", []))
        for group in data["groups"]:
            self.assertFalse(group["specular"])
            self.assertEqual(group["shadow"]["opacity"], 0)
            self.assertTrue(all(not layer["glass"] for layer in group["layers"]))

    def test_trackr_blue_is_default_in_all_entry_points(self):
        root = Path(__file__).resolve().parents[2]
        for path in ['Trackr/App/TrackrApp.swift', 'Trackr/Views/TrackrSettingsView.swift', 'Trackr/Views/TrackrSecurityHost.swift']:
            text = (root / path).read_text(encoding='utf-8')
            self.assertIn('private var accent = "blue"', text)
            self.assertNotIn('private var accent = "teal"', text)
        import plistlib
        with open(root / 'Trackr/Settings.bundle/Root.plist', 'rb') as stream:
            preferences = plistlib.load(stream)['PreferenceSpecifiers']
        self.assertEqual(next(row['DefaultValue'] for row in preferences if row.get('Key') == 'trackr.accent'), 'blue')

    def test_icon_assets_and_workflow_use_trackr_identity(self):
        root = Path(__file__).resolve().parents[2]
        import json
        icon = root / 'Trackr/Trackr.icon'
        data = json.loads((icon / 'icon.json').read_text())
        self.assertTrue(all(color.endswith(',1.00000') for color in data['fill']['linear-gradient']))
        for group in data['groups']:
            self.assertFalse(group['refractivity']['enabled'])
            self.assertFalse(group['translucency']['enabled'])
            for layer in group['layers']:
                self.assertTrue((icon / 'Assets' / layer['image-name']).is_file())
                self.assertTrue(layer['image-name'].endswith('.svg'))
        workflow = (root / '.github/workflows/build-ipa.yml').read_text()
        for reference in ['Trackr.xcodeproj', '-scheme Trackr', 'Payload/Trackr.app', 'TrackrWidgets.appex/TrackrWidgets', 'build/Trackr.ipa']:
            self.assertIn(reference, workflow)
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER: com.mikhael.trackr', self.source)

    def test_old_build_tools_are_rejected(self):
        with self.assertRaises(ValueError):
            prepare_spec(self.source, 16)

    def test_widget_and_control_targets_share_local_snapshot_and_intent_sources(self):
        root = Path(__file__).resolve().parents[2]
        self.assertEqual(self.source.count('- path: Shared'), 2)
        self.assertIn('TRACKR_WIDGET_EXTENSION', self.source)
        self.assertIn('TRACKR_APP_GROUP: group.com.mikhael.trackr', self.source)
        import plistlib
        for file in ['Trackr/Info.plist', 'TrackrWidgets/Info.plist']:
            with open(root / file, 'rb') as stream:
                self.assertEqual(plistlib.load(stream)['TrackrAppGroup'], '$(TRACKR_APP_GROUP)')
        with open(root / 'Shared/Trackr.entitlements', 'rb') as stream:
            self.assertEqual(plistlib.load(stream)['com.apple.security.application-groups'], ['$(TRACKR_APP_GROUP)'])

    def test_ipa_upload_is_a_single_direct_file_without_zip_wrapper(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root / '.github/workflows/build-ipa.yml').read_text()
        upload = workflow.split('- name: Upload Trackr.ipa', 1)[1].split('- name: Upload test results', 1)[0]
        self.assertIn('uses: actions/upload-artifact@v7', upload)
        self.assertIn('path: build/Trackr.ipa', upload)
        self.assertIn('archive: false', upload)
        self.assertNotIn('Trackr-unsigned', workflow)
        self.assertNotIn('.zip', upload)
        # Packaging Payload into the IPA is still required by the iOS format.
        self.assertIn('zip -qry ../Trackr.ipa Payload', workflow)

    def test_google_drive_configuration_does_not_require_credentials_to_build(self):
        import plistlib
        root = Path(__file__).resolve().parents[2]
        self.assertIn("TRACKR_GOOGLE_CLIENT_ID:", self.source)
        import re
        client = re.search(r"(?m)^    TRACKR_GOOGLE_CLIENT_ID:\s*([^\n]*)$", self.source).group(1).strip().strip("\"'")
        scheme = re.search(r"(?m)^    TRACKR_GOOGLE_REVERSED_CLIENT_ID:\s*([^\n]*)$", self.source).group(1).strip().strip("\"'")
        if client:
            self.assertTrue(client.endswith('.apps.googleusercontent.com'))
            self.assertEqual(scheme, '.'.join(reversed(client.split('.'))))
        self.assertIn('exactVersion: 9.0.0', self.source)
        self.assertIn('product: GoogleSignIn', self.source)
        self.assertIn('BackgroundTasks.framework', self.source)
        with open(root / 'Trackr/Info.plist', 'rb') as stream:
            info = plistlib.load(stream)
        self.assertEqual(info['GIDClientID'], '$(TRACKR_GOOGLE_CLIENT_ID)')
        self.assertIn('fetch', info['UIBackgroundModes'])
        self.assertIn('com.mikhael.trackr.backup.refresh', info['BGTaskSchedulerPermittedIdentifiers'])
        self.assertTrue(any('$(TRACKR_GOOGLE_REVERSED_CLIENT_ID)' in item['CFBundleURLSchemes'] for item in info['CFBundleURLTypes']))
        self.assertNotIn('GoogleSignIn', self.source.split('  TrackrWidgets:')[1])

    def test_app_identity_and_face_id_permission_are_present(self):
        import plistlib
        root = Path(__file__).resolve().parents[2]
        with open(root / 'Trackr/Info.plist', 'rb') as stream:
            info = plistlib.load(stream)
        self.assertEqual(info['CFBundleDisplayName'], 'Trackr')
        self.assertEqual(info['CFBundleName'], 'Trackr')
        self.assertTrue(info['NSFaceIDUsageDescription'].strip())
        self.assertEqual(info['CFBundleExecutable'], '$(EXECUTABLE_NAME)')
        self.assertIn('LocalAuthentication.framework', self.source)


if __name__ == "__main__":
    unittest.main()
