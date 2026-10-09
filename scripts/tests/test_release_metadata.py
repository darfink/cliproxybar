import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("update_homebrew", ROOT / "scripts/update-homebrew.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseMetadataTests(unittest.TestCase):
    def test_only_stable_tags_are_accepted(self):
        self.assertEqual(release.release_version("v0.2.4"), "0.2.4")
        for tag in ["0.2.4", "v0.2.4-beta", "v01.2.4", "v1.2", "v1.2.3/../../main"]:
            with self.assertRaises(ValueError):
                release.release_version(tag)

    def test_checksum_must_belong_to_the_matching_universal_archive(self):
        digest = "a" * 64
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "checksum"
            path.write_text(f"{digest}  CLIProxyBar-0.2.4-macOS-universal.zip\n")
            self.assertEqual(release.checksum(path, "0.2.4"), digest)
            for filename in ["CLIProxyBar-0.2.3-macOS-universal.zip", "CLIProxyBar-0.2.4-macOS-arm64.zip", "another-app.zip"]:
                path.write_text(f"{digest}  {filename}\n")
                with self.assertRaises(ValueError):
                    release.checksum(path, "0.2.4")

    def test_old_releases_cannot_downgrade_the_tap(self):
        current = (ROOT / release.CASK).read_text()
        newer = release.updated_cask(current, "1.0.0", "b" * 64)
        self.assertEqual(release.updated_cask(newer, "0.2.4", "c" * 64), newer)
        self.assertEqual(release.updated_cask(newer, "1.0.0", "b" * 64), newer)
        self.assertIn('sha256 "' + "b" * 64 + '"', newer)


if __name__ == "__main__":
    unittest.main()
