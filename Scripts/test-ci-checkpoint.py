import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("checkpoint", Path(__file__).with_name("ci-checkpoint.py"))
checkpoint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checkpoint)


class CheckpointTrustTests(unittest.TestCase):
    def test_resume_requires_same_commit_workflow_and_repository(self):
        expected = {"commit": "a" * 40, "repository": "owner/app", "workflow": ".github/workflows/release-macos.yml"}
        valid = {"head_sha": expected["commit"], "path": expected["workflow"],
                 "head_repository": {"full_name": expected["repository"]}, "event": "workflow_dispatch"}
        checkpoint.validate_run(valid, expected)
        for update in ({"head_sha": "b" * 40}, {"path": ".github/workflows/ci.yml"},
                       {"event": "pull_request"}, {"head_repository": {"full_name": "fork/app"}}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                checkpoint.validate_run({**valid, **update}, expected)


if __name__ == "__main__":
    unittest.main()
