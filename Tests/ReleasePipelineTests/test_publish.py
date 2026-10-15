import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).resolve().parents[2] / "Scripts/publish-release.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublicationIntegrityTests(unittest.TestCase):
    def test_draft_assets_must_match_and_may_not_include_unrelated_files(self):
        expected = {"App.zip": {"sha256": "a" * 64, "size": 123}}
        valid = {"name": "App.zip", "digest": "sha256:" + "a" * 64, "size": 123, "state": "uploaded"}
        publisher.verify_assets({"assets": []}, expected)
        publisher.verify_assets({"assets": [valid]}, expected)
        for change in ({"name": "unrelated.zip"}, {"digest": "sha256:" + "b" * 64}, {"size": 124}, {"state": "open"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                publisher.verify_assets({"assets": [{**valid, **change}]}, expected)

    def test_local_invocation_cannot_publish(self):
        with patch.dict(publisher.os.environ, {}, clear=True), patch.object(publisher.subprocess, "run") as command:
            with self.assertRaisesRegex(ValueError, "release workflow"):
                publisher.main()
            command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
