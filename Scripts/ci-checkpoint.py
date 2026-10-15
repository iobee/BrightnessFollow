#!/usr/bin/env python3
"""Preserve exact signed builds across macOS GitHub Actions runs, without keys."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True)


def metadata(directory):
    return {"schema": 1, "commit": os.environ["GITHUB_SHA"],
            "repository": os.environ["GITHUB_REPOSITORY"], "directory": directory,
            "workflow": ".github/workflows/release-macos.yml"}


def validate_run(run_info, expected):
    if (run_info.get("head_sha") != expected["commit"]
            or run_info.get("path") != expected["workflow"]
            or run_info.get("event") not in ("push", "workflow_dispatch")
            or run_info.get("head_repository", {}).get("full_name") != expected["repository"]):
        raise ValueError("Resume only this release workflow at the exact same source commit.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("initialize", "snapshot"))
    parser.add_argument("directory", choices=("out", ".build/releases"))
    args = parser.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("This helper only runs in GitHub Actions.")
    output = Path(args.directory)
    expected = metadata(args.directory)
    record = output / ".ci-source.json"
    if args.action == "initialize":
        resume = os.environ.get("RESUME_RUN_ID", "").strip()
        if resume:
            if not resume.isdecimal():
                raise ValueError("resume_run_id must be a numeric GitHub Actions run ID.")
            info = json.loads(run("gh", "api", f"repos/{expected['repository']}/actions/runs/{resume}"))
            validate_run(info, expected)
            if output.exists():
                raise ValueError("Refusing to restore over an existing output directory.")
            with tempfile.TemporaryDirectory(prefix="release-resume-") as directory:
                temporary = Path(directory)
                run("gh", "run", "download", resume, "--repo", expected["repository"],
                    "--name", "release-checkpoint", "--dir", temporary / "download")
                run("ditto", "-x", "-k", temporary / "download/release-checkpoint.zip", temporary / "restore")
                restored = temporary / "restore" / output.name
                if json.loads((restored / ".ci-source.json").read_text()) != expected:
                    raise ValueError("Checkpoint metadata does not match this release.")
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(restored), output)
            print(f"Restored the signed build from run {resume}.")
        else:
            if output.exists():
                raise ValueError("Use a fresh output directory or an explicit resume run.")
            output.mkdir(parents=True)
            record.write_text(json.dumps(expected, indent=2) + "\n")
        return
    if not record.exists():
        return
    if json.loads(record.read_text()) != expected:
        raise ValueError("Refusing to snapshot an unrelated build.")
    archive = Path(os.environ["RUNNER_TEMP"]) / "release-checkpoint.zip"
    archive.unlink(missing_ok=True)
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", output, archive)
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.write("ready=true\n")


if __name__ == "__main__":
    main()
