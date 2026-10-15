"""Exercise interrupted uploads and tamper detection without Apple credentials."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release", ROOT / "Scripts/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
SUBMISSION = "d98208e8-aa5c-4c6c-bfa4-b9349743116f"


class NotaryRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.archive = Path(self.directory.name) / "BrightnessFollow-0.3.6-arm64.zip"
        self.archive.write_bytes(b"a frozen signed archive")
        self.status = "In Progress"

    def submit(self, command, **kwargs):
        self.assertNotIn("--wait", command)
        json.dump({"id": SUBMISSION}, kwargs["stdout"])
        return SimpleNamespace(returncode=0, stderr="")

    def query(self, *command, **kwargs):
        if command[:3] == ("xcrun", "notarytool", "info"):
            return json.dumps({"id": SUBMISSION, "name": self.archive.name, "status": self.status})
        if command[:3] == ("xcrun", "notarytool", "log"):
            return json.dumps({"status": self.status, "sha256": release.digest(self.archive),
                               "archiveFilename": self.archive.name,
                               "issues": [] if self.status == "Accepted" else ["invalid signature"]})
        self.fail(f"Unexpected command: {command}")

    def test_pending_resumes_same_submission_and_finishes_without_reupload(self):
        with patch.object(release.subprocess, "run", side_effect=self.submit) as upload, \
                patch.object(release, "run", side_effect=self.query):
            for _ in range(2):
                with self.assertRaises(release.Pending):
                    release.notarize(self.archive, "test-profile", 0)
            self.status = "Accepted"
            self.assertEqual(release.notarize(self.archive, "test-profile", 0), SUBMISSION)
            upload.assert_called_once()

    def test_every_notary_request_uses_the_configured_file_keychain(self):
        self.status = "Accepted"
        with patch.dict(os.environ, {"BRIGHTNESS_FOLLOW_NOTARY_KEYCHAIN": "/tmp/ci-signing.keychain-db"}), \
                patch.object(release.subprocess, "run", side_effect=self.submit) as upload, \
                patch.object(release, "run", side_effect=self.query) as requests:
            release.notarize(self.archive, "test-profile", 0)
            commands = [upload.call_args.args[0]] + [call.args for call in requests.call_args_list]
            for command in commands:
                self.assertIn("--keychain", command)
                self.assertEqual(command[command.index("--keychain") + 1], "/tmp/ci-signing.keychain-db")

    def test_changed_archive_is_rejected_before_apple_call(self):
        with patch.object(release.subprocess, "run", side_effect=self.submit), \
                patch.object(release, "run", side_effect=self.query):
            with self.assertRaises(release.Pending):
                release.notarize(self.archive, "test-profile", 0)
        self.archive.write_bytes(b"a different build")
        with patch.object(release, "run") as query, patch.object(release.subprocess, "run") as upload:
            with self.assertRaisesRegex(release.ReleaseError, "archive changed"):
                release.notarize(self.archive, "test-profile", 0)
            query.assert_not_called()
            upload.assert_not_called()

    def test_ambiguous_upload_is_not_automatically_repeated(self):
        with patch.object(release.subprocess, "run", side_effect=subprocess.TimeoutExpired("notarytool", 600)):
            with self.assertRaises(subprocess.TimeoutExpired):
                release.notarize(self.archive, "test-profile", 0)
        with patch.object(release.subprocess, "run") as upload:
            with self.assertRaisesRegex(release.ReleaseError, "refusing a duplicate"):
                release.notarize(self.archive, "test-profile", 0)
            upload.assert_not_called()
        with patch.object(release, "run", side_effect=self.query):
            with self.assertRaises(release.Pending):
                release.notarize(self.archive, "test-profile", 0, SUBMISSION)

    def test_recovery_rejects_a_submission_for_different_archive_bytes(self):
        self.status = "Accepted"
        def wrong_archive_log(*command, **kwargs):
            value = json.loads(self.query(*command, **kwargs))
            if command[:3] == ("xcrun", "notarytool", "log"):
                value["sha256"] = "another build with the same file name"
            return json.dumps(value)
        with patch.object(release, "run", side_effect=wrong_archive_log):
            with self.assertRaisesRegex(release.ReleaseError, "does not match this exact archive"):
                release.notarize(self.archive, "test-profile", 0, SUBMISSION)

    def test_invalid_submission_saves_apple_log(self):
        self.status = "Invalid"
        with patch.object(release.subprocess, "run", side_effect=self.submit), \
                patch.object(release, "run", side_effect=self.query):
            with self.assertRaisesRegex(release.ReleaseError, "Apple rejected"):
                release.notarize(self.archive, "test-profile", 0)
        log = release.read(self.archive.with_suffix(".zip.notary-log.json"))
        self.assertEqual(log["issues"], ["invalid signature"])

    def test_client_crash_after_returning_id_still_recovers(self):
        def crashing_submit(command, **kwargs):
            self.submit(command, **kwargs)
            return SimpleNamespace(returncode=-10, stderr="client crashed")
        with patch.object(release.subprocess, "run", side_effect=crashing_submit) as upload, \
                patch.object(release, "run", side_effect=self.query):
            with self.assertRaises(release.Pending):
                release.notarize(self.archive, "test-profile", 0)
            with self.assertRaises(release.Pending):
                release.notarize(self.archive, "test-profile", 0)
            upload.assert_called_once()


class ReleaseConfigurationTests(unittest.TestCase):
    def test_prepare_only_never_contacts_notary_service(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            work = output / ".notary"
            work.mkdir()
            expected = {"CFBundleIdentifier": release.BUNDLE_ID,
                        "CFBundleShortVersionString": "0.3.6", "CFBundleVersion": "9"}
            release.save(work / "build.json", {"info": expected, "executableSha256": "same-app"})
            (work / "BrightnessFollow-0.3.6-arm64.zip").write_bytes(b"prepared archive")
            args = SimpleNamespace(prepare_only=True, verify_only=False)
            identity = "Developer ID Application: Example (AAAAAAAAAA)"
            with patch.object(release, "run", return_value=f'"{identity}"') as command, \
                    patch.object(release, "verify_app", return_value="same-app"), \
                    patch.object(release, "verify_zip"), patch.object(release, "notarize") as notarize:
                release.release(args, identity, "AAAAAAAAAA", "unused", expected, output)
                command.assert_called_once_with("security", "find-identity", "-v", "-p", "codesigning")
                notarize.assert_not_called()

    def test_local_identity_and_mismatched_team_cannot_release(self):
        for identity in ("BrightnessFollow Local Code Signing", "Developer ID Application: Example (AAAAAAAAAA)"):
            with self.subTest(identity=identity), patch.dict(os.environ, {
                "BRIGHTNESS_FOLLOW_SIGNING_IDENTITY": identity,
                "BRIGHTNESS_FOLLOW_TEAM_ID": "BBBBBBBBBB",
                "BRIGHTNESS_FOLLOW_NOTARY_PROFILE": "test-profile",
            }, clear=True):
                with self.assertRaises(release.ReleaseError):
                    release.settings()


if __name__ == "__main__":
    unittest.main()
