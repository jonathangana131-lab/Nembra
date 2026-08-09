#!/usr/bin/env python3
from pathlib import Path
import plistlib, unittest
ROOT = Path(__file__).resolve().parents[3]
PLIST = ROOT/'NembraApp'/'Info.plist'
PROJECT = ROOT/'Nembra.xcodeproj'/'project.pbxproj'
SIM = ROOT/'scripts'/'ci'/'xcode27_simulator_capture.sh'
FIELD = ROOT/'scripts'/'ci'/'xcode27_signed_field_candidate.sh'
class TransportTests(unittest.TestCase):
    def test_plist_and_project(self):
        with PLIST.open('rb') as f: info=plistlib.load(f)
        self.assertEqual(info,{
          'NembraCaptureBuildIdentifier':'$(NEMBRA_CAPTURE_BUILD_IDENTIFIER)',
          'NembraCaptureBuildInstanceID':'$(NEMBRA_CAPTURE_BUILD_INSTANCE_ID)',
          'NembraCaptureBuildCommitSHA':'$(NEMBRA_CAPTURE_BUILD_COMMIT_SHA)',
          'NembraCaptureFieldRecipe':'$(NEMBRA_CAPTURE_FIELD_RECIPE)'})
        p=PROJECT.read_text(); self.assertEqual(p.count('INFOPLIST_FILE = NembraApp/Info.plist;'),2)
    def test_simulator_transport(self):
        s=SIM.read_text()
        for value in ['NEMBRA_CAPTURE_BUILD_IDENTIFIER=$CAPTURE_BUILD_IDENTIFIER','NEMBRA_CAPTURE_BUILD_INSTANCE_ID=$CAPTURE_BUILD_INSTANCE_ID','NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$CAPTURE_BUILD_COMMIT_SHA']: self.assertIn(value,s)
        self.assertNotIn('INFOPLIST_KEY_NembraCaptureBuild',s)
        for key in ['Print :NembraCaptureBuildIdentifier','Print :NembraCaptureBuildInstanceID','Print :NembraCaptureBuildCommitSHA']: self.assertIn(key,s)
    def test_signed_field_transport(self):
        s=FIELD.read_text()
        for value in ['NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_IDENTIFIER','NEMBRA_CAPTURE_BUILD_INSTANCE_ID=$BUILD_INSTANCE_ID','NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA','NEMBRA_CAPTURE_FIELD_RECIPE=$FIELD_RECIPE_ID']: self.assertIn(value,s)
        self.assertNotIn('INFOPLIST_KEY_NembraCaptureBuild',s); self.assertNotIn('INFOPLIST_KEY_NembraCaptureFieldRecipe',s)
        self.assertIn('info.get("NembraCaptureFieldRecipe") != field_recipe',s); self.assertIn('raw_info_plist',s)
if __name__=='__main__': unittest.main()
