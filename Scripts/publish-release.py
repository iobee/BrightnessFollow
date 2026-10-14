#!/usr/bin/env python3
"""Publish only the signed distribution verified by release.py on GitHub Actions."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "iobee/BrightnessFollow"


def gh(*args, optional=False):
    result = subprocess.run(["gh", *args], cwd=ROOT, capture_output=True, text=True)
    if optional and result.returncode and ("HTTP 404" in result.stderr or "release not found" in result.stderr.lower()):
        return None
    if result.returncode:
        raise RuntimeError(result.stderr)
    return (json.loads(result.stdout) if args[0] == "api" or "--json" in args else result.stdout.strip()) if result.stdout.strip() else None


def verify_assets(remote, expected):
    by_name = {asset["name"]: asset for asset in remote["assets"]}
    if set(by_name) - set(expected):
        raise ValueError("Draft has unrelated assets; refusing to publish it.")
    for name, asset in by_name.items():
        wanted = expected[name]
        if asset.get("digest") != "sha256:" + wanted["sha256"] or asset["size"] != wanted["size"] or asset["state"] != "uploaded":
            raise ValueError(f"GitHub asset differs from the verified local file: {name}")


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise ValueError("Publish from the BrightnessFollow release workflow.")
    subprocess.run([sys.executable, str(ROOT / "Scripts/release.py"), "--verify-only"], cwd=ROOT, check=True)
    with (ROOT / "Resources/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    output = ROOT / ".build/releases" / f"{version}-{build}-arm64"
    stem, tag = f"BrightnessFollow-{version}-arm64", f"v{version}"
    expected = {}
    for name in (stem + ".zip", stem + ".dmg", "SHA256SUMS", "release.json"):
        data = (output / name).read_bytes()
        expected[name] = {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    existing = gh("release", "view", tag, "--repo", REPOSITORY, "--json", "databaseId,isDraft", optional=True)
    if existing and not existing["isDraft"]:
        raise ValueError("This version is already published. Increment the version; never overwrite it.")
    latest = gh("api", f"repos/{REPOSITORY}/releases/latest", optional=True)
    if latest and tuple(map(int, latest["tag_name"].removeprefix("v").split("."))) >= tuple(map(int, version.split("."))):
        raise ValueError("Refusing to replace Latest with an equal or older version.")
    commit = os.environ["GITHUB_SHA"]
    tagged = subprocess.run(["git", "rev-parse", "--verify", tag + "^{commit}"], cwd=ROOT, text=True, capture_output=True)
    if tagged.returncode == 0 and tagged.stdout.strip() != commit:
        raise ValueError("The existing version tag points to a different source commit.")
    with tempfile.TemporaryDirectory(prefix="brightness-follow-publish-") as directory:
        notes = Path(directory) / "notes.md"
        notes.write_text(f"BrightnessFollow {version} for Apple Silicon (macOS 13+).\n\n"
                         "Developer ID signed and notarized by Apple. Both ZIP and DMG were verified by Gatekeeper.\n"
                         "When upgrading from the old locally signed app, macOS may require Accessibility permission again.\n")
        if not existing:
            gh("release", "create", tag, "--repo", REPOSITORY, "--draft", "--target", commit,
               "--title", f"BrightnessFollow {version}", "--notes-file", str(notes))
            existing = gh("release", "view", tag, "--repo", REPOSITORY, "--json", "databaseId,isDraft")
        endpoint = f"repos/{REPOSITORY}/releases/{existing['databaseId']}"
        remote = gh("api", endpoint)
        verify_assets(remote, expected)
        names = {item["name"] for item in remote["assets"]}
        for name in expected:
            if name not in names:
                gh("release", "upload", tag, str(output / name), "--repo", REPOSITORY)
        remote = gh("api", endpoint)
        verify_assets(remote, expected)
        if {item["name"] for item in remote["assets"]} != set(expected):
            raise ValueError("Not all verified release files were uploaded.")
        gh("release", "edit", tag, "--repo", REPOSITORY, "--draft=false", "--latest", "--notes-file", str(notes))
    latest = gh("api", f"repos/{REPOSITORY}/releases/latest")
    verify_assets(latest, expected)
    if latest["tag_name"] != tag or latest["draft"] or {asset["name"] for asset in latest["assets"]} != set(expected):
        raise ValueError("Published version is not confirmed as Latest.")
    print(latest["html_url"])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"Publication stopped: {error}", file=sys.stderr)
        sys.exit(1)
