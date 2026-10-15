#!/usr/bin/env python3
"""Build and verify a Developer ID release. Only the Python standard library is used."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

PROJECT = Path(__file__).resolve().parent.parent
APP_NAME = "BrightnessFollow.app"
BUNDLE_ID = "com.nick.brightnessfollow"


class ReleaseError(Exception):
    pass


class Pending(ReleaseError):
    pass


def run(*args, log=None, timeout=180):
    command = [str(arg) for arg in args]
    result = subprocess.run(command, cwd=PROJECT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    if log:
        Path(log).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise ReleaseError(f"{' '.join(command[:3])} failed ({result.returncode}):\n"
                           f"{result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def save(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def read(path):
    return json.loads(path.read_text())


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else _digest(stream)


def _digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        value.update(block)
    return value.hexdigest()


def settings():
    identity = os.environ.get("BRIGHTNESS_FOLLOW_SIGNING_IDENTITY", "")
    team = os.environ.get("BRIGHTNESS_FOLLOW_TEAM_ID", "")
    profile = os.environ.get("BRIGHTNESS_FOLLOW_NOTARY_PROFILE", "")
    match = re.fullmatch(r"Developer ID Application: .+ \(([A-Z0-9]{10})\)", identity)
    if not match or match[1] != team or not profile:
        raise ReleaseError("Configure a Developer ID Application identity, its matching team ID, "
                           "and a Keychain notary profile in .env.release.local. "
                           "See Scripts/release-config.example.sh.")
    return identity, team, profile


def app_info(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        return plistlib.load(stream)


def verify_app(app, expected, identity, team, notarized=False):
    info = app_info(app)
    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
        if info[key] != expected[key]:
            raise ReleaseError(f"Unexpected {key} in {app}: {info[key]}")
    run("codesign", "--verify", "--deep", "--strict", app)
    signature = run("codesign", "--display", "--verbose=4", app)
    for marker in (f"Authority={identity}\n", f"TeamIdentifier={team}\n", "(runtime)", "Timestamp="):
        if marker not in signature:
            raise ReleaseError(f"Missing release signing requirement {marker.strip()}: {app}")
    binary = app / "Contents/MacOS/BrightnessFollow"
    if run("lipo", "-archs", binary).strip() != "arm64":
        raise ReleaseError(f"Expected an arm64 executable: {binary}")
    if notarized:
        run("xcrun", "stapler", "validate", app)
        assessment = run("spctl", "--assess", "--type", "execute", "--verbose=2", app)
        if "source=Notarized Developer ID" not in assessment:
            raise ReleaseError(f"Gatekeeper did not confirm notarization: {assessment}")
    return digest(binary)


def zip_app(app, target):
    temporary = target.with_suffix(".partial.zip")
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, temporary)
    temporary.replace(target)


def verify_zip(archive, expected, identity, team, original_sha, notarized=False):
    with tempfile.TemporaryDirectory(prefix="brightness-follow-zip-") as directory:
        root = Path(directory)
        run("ditto", "-x", "-k", archive, root)
        if verify_app(root / APP_NAME, expected, identity, team, notarized) != original_sha:
            raise ReleaseError("The ZIP contains a different signed application.")


def notary_auth(profile):
    args = ["--keychain-profile", profile]
    keychain = os.environ.get("BRIGHTNESS_FOLLOW_NOTARY_KEYCHAIN")
    if keychain:
        args += ["--keychain", keychain]
    return args


def notarize(artifact, profile, wait_seconds, adopted_id=None):
    """Keep the submitted archive immutable; persist intent before the upload."""
    receipt_path = artifact.with_suffix(artifact.suffix + ".notary.json")
    sha = digest(artifact)
    receipt = read(receipt_path) if receipt_path.exists() else None
    if receipt and (receipt["sha256"] != sha or receipt["name"] != artifact.name):
        raise ReleaseError(f"Submitted archive changed. Use a new output directory: {artifact}")
    if adopted_id:
        uuid.UUID(adopted_id)
        if receipt and receipt.get("id") not in (None, adopted_id):
            raise ReleaseError("Cannot replace an existing submission ID.")
        info = json.loads(run("xcrun", "notarytool", "info", adopted_id,
                              *notary_auth(profile), "--output-format", "json"))
        if info["name"] != artifact.name:
            raise ReleaseError("The recovery submission belongs to another archive.")
        receipt = {"name": artifact.name, "sha256": sha, "id": adopted_id, "status": info["status"]}
        save(receipt_path, receipt)
    if receipt is None:
        receipt = {"name": artifact.name, "sha256": sha, "status": "Submitting"}
        save(receipt_path, receipt)
        # stdout goes directly to disk so a client crash cannot erase a returned ID.
        output = artifact.with_suffix(artifact.suffix + ".submit.json")
        print(f"Submitting {artifact.name} to Apple…", flush=True)
        with output.open("w") as stream:
            result = subprocess.run(["xcrun", "notarytool", "submit", str(artifact),
                                     *notary_auth(profile), "--output-format", "json"],
                                    stdout=stream, stderr=subprocess.PIPE, text=True, timeout=600)
        artifact.with_suffix(artifact.suffix + ".submit.stderr.log").write_text(result.stderr)
        # Deliberately do not retry an ambiguous upload, even after a nonzero exit.
    if not receipt.get("id"):
        output = artifact.with_suffix(artifact.suffix + ".submit.json")
        try:
            submission_id = read(output)["id"]
            uuid.UUID(submission_id)
        except (OSError, ValueError, KeyError):
            raise ReleaseError(f"Upload outcome is unknown; refusing a duplicate upload. Check "
                               f"notarytool history, then recover this archive with --app-submission "
                               f"or --dmg-submission. Receipt: {receipt_path}")
        receipt.update(id=submission_id, status="Submitted")
        save(receipt_path, receipt)
    deadline = time.monotonic() + wait_seconds
    while True:
        info = json.loads(run("xcrun", "notarytool", "info", receipt["id"],
                              *notary_auth(profile), "--output-format", "json"))
        receipt.update(status=info["status"], apple=info)
        save(receipt_path, receipt)
        print(f"{artifact.name}: {info['status']} ({receipt['id']})", flush=True)
        if info["status"] in ("Accepted", "Invalid", "Rejected"):
            log = json.loads(run("xcrun", "notarytool", "log", receipt["id"],
                                 *notary_auth(profile)))
            save(artifact.with_suffix(artifact.suffix + ".notary-log.json"), log)
            if log.get("sha256") != sha or log.get("archiveFilename") != artifact.name:
                raise ReleaseError("Apple's submission log does not match this exact archive.")
            if info["status"] != "Accepted":
                raise ReleaseError(f"Apple rejected {artifact.name}. See its .notary-log.json.")
            if log.get("issues"):
                print(f"Apple reported issues; review {artifact.name}.notary-log.json", flush=True)
            return receipt["id"]
        if info["status"] != "In Progress":
            raise ReleaseError(f"Unexpected Apple status: {info['status']}")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise Pending("Apple is still processing. Run the same release command to resume; "
                          "the existing signed app and submission will be reused.")
        time.sleep(min(20, remaining))


def verify_packages(output, expected, identity, team, original_sha):
    stem = f"BrightnessFollow-{expected['CFBundleShortVersionString']}-arm64"
    archive, image = output / f"{stem}.zip", output / f"{stem}.dmg"
    verify_zip(archive, expected, identity, team, original_sha, True)
    with tempfile.TemporaryDirectory(prefix="brightness-follow-verify-") as directory:
        root = Path(directory)
        run("hdiutil", "verify", image)
        run("codesign", "--verify", "--strict", image)
        signature = run("codesign", "--display", "--verbose=4", image)
        if f"Authority={identity}\n" not in signature or f"TeamIdentifier={team}\n" not in signature:
            raise ReleaseError("The DMG uses an unexpected signing identity.")
        run("xcrun", "stapler", "validate", image)
        run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature",
            "--verbose=2", image)
        mount = root / "volume"
        mount.mkdir()
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, image)
        try:
            if verify_app(mount / APP_NAME, expected, identity, team, True) != original_sha:
                raise ReleaseError("The DMG contains a different signed application.")
            if not (mount / "Applications").is_symlink() or os.readlink(mount / "Applications") != "/Applications":
                raise ReleaseError("The DMG is missing its Applications shortcut.")
        finally:
            run("hdiutil", "detach", mount)
    return {item.name: {"sha256": digest(item), "bytes": item.stat().st_size}
            for item in (archive, image)}


def release(args, identity, team, profile, expected, output):
    work = output / ".notary"
    work.mkdir(exist_ok=True)
    app = output / APP_NAME
    build_receipt = work / "build.json"
    manifest_path = output / "release.json"
    if args.verify_only or manifest_path.exists():
        manifest = read(manifest_path)
        original = verify_app(app, expected, identity, team, True)
        if original != manifest["executableSha256"]:
            raise ReleaseError("The release app changed after validation.")
        assets = verify_packages(output, expected, identity, team, original)
        if assets != manifest["assets"]:
            raise ReleaseError("Release asset hashes changed after validation.")
        print(f"Verified signed, notarized release: {output}", flush=True)
        return
    signing_keychain = os.environ.get("BRIGHTNESS_FOLLOW_SIGNING_KEYCHAIN")
    available = run("security", "find-identity", "-v", "-p", "codesigning", *([signing_keychain] if signing_keychain else []))
    if f'"{identity}"' not in available:
        raise ReleaseError(f"Missing usable identity and private key: {identity}")
    if not args.prepare_only:
        run("xcrun", "notarytool", "history", *notary_auth(profile), "--output-format", "json")
    if not build_receipt.exists():
        if app.exists():
            raise ReleaseError("An unrecorded app already exists; choose a new --output directory.")
        print("Running Swift tests and building a Developer ID app…", flush=True)
        run("swift", "test", "--disable-sandbox", log=work / "swift-test.log", timeout=600)
        os.environ["BRIGHTNESS_FOLLOW_RELEASE"] = "1"
        run(PROJECT / "Scripts/build-app.sh", app, log=work / "build.log", timeout=600)
        original = verify_app(app, expected, identity, team)
        build = {"info": expected, "executableSha256": original,
                 "sourceCommit": run("git", "rev-parse", "HEAD").strip(),
                 "sourceStatus": run("git", "status", "--short")}
        save(build_receipt, build)
    build = read(build_receipt)
    if build["info"] != expected or verify_app(app, expected, identity, team) != build["executableSha256"]:
        raise ReleaseError("Build receipt mismatch. Use a new version or --output directory.")
    stem = f"BrightnessFollow-{expected['CFBundleShortVersionString']}-arm64"
    submitted_zip = work / f"{stem}.zip"
    if not submitted_zip.exists():
        zip_app(app, submitted_zip)
    verify_zip(submitted_zip, expected, identity, team, build["executableSha256"])
    if args.prepare_only:
        print(f"Prepared signed app and notarization ZIP (not uploaded): {submitted_zip}", flush=True)
        print(f"SHA-256: {digest(submitted_zip)}", flush=True)
        return
    app_submission = notarize(submitted_zip, profile, args.wait_seconds, args.app_submission)
    run("xcrun", "stapler", "staple", app)
    verify_app(app, expected, identity, team, True)
    archive = output / f"{stem}.zip"
    if not archive.exists():
        zip_app(app, archive)
    submitted_dmg = work / f"{stem}.dmg"
    if not submitted_dmg.exists():
        with tempfile.TemporaryDirectory(prefix="brightness-follow-dmg-") as directory:
            staging = Path(directory)
            run("ditto", app, staging / APP_NAME)
            (staging / "Applications").symlink_to("/Applications")
            partial = work / f"{stem}.partial.dmg"
            run("hdiutil", "create", "-ov", "-volname", "BrightnessFollow", "-srcfolder", staging,
                "-format", "UDZO", "-fs", "HFS+", partial)
            run("codesign", "--force", "--sign", identity, "--timestamp", partial)
            run("codesign", "--verify", "--strict", partial)
            partial.replace(submitted_dmg)
    dmg_submission = notarize(submitted_dmg, profile, args.wait_seconds, args.dmg_submission)
    image = output / f"{stem}.dmg"
    if not image.exists():
        partial = output / f"{stem}.partial.dmg"
        shutil.copy2(submitted_dmg, partial)
        run("xcrun", "stapler", "staple", partial)
        partial.replace(image)
    assets = verify_packages(output, expected, identity, team, build["executableSha256"])
    manifest = {"version": expected["CFBundleShortVersionString"], "build": expected["CFBundleVersion"],
                "bundleIdentifier": BUNDLE_ID, "architecture": "arm64", "signingIdentity": identity,
                "teamId": team, "notarization": {"app": app_submission, "dmg": dmg_submission},
                "executableSha256": build["executableSha256"], "assets": assets,
                "sourceCommit": build["sourceCommit"], "sourceStatus": build["sourceStatus"]}
    sums = "".join(f"{value['sha256']}  {name}\n" for name, value in assets.items())
    (output / "SHA256SUMS").write_text(sums)
    save(manifest_path, manifest)
    print(f"Signed and notarized release ready: {output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Release directory (reused when resuming).")
    parser.add_argument("--wait-seconds", type=int, default=600, help="Wait per submission; 0 queries once.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-only", action="store_true", help="Test, sign and create the app ZIP; do not upload to Apple.")
    mode.add_argument("--verify-only", action="store_true", help="Verify an already completed release.")
    parser.add_argument("--app-submission", help="Recover an ambiguous app ZIP upload by its Apple ID.")
    parser.add_argument("--dmg-submission", help="Recover an ambiguous DMG upload by its Apple ID.")
    args = parser.parse_args()
    if args.wait_seconds < 0:
        parser.error("--wait-seconds must be nonnegative")
    identity, team, profile = settings()
    with (PROJECT / "Resources/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    expected = {key: info[key] for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion")}
    version, build = expected["CFBundleShortVersionString"], expected["CFBundleVersion"]
    if expected["CFBundleIdentifier"] != BUNDLE_ID or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version) or not build.isdecimal():
        raise ReleaseError("Unexpected bundle identifier or invalid release version/build.")
    output = (args.output or PROJECT / ".build/releases" / f"{version}-{build}-arm64").resolve()
    output.mkdir(parents=True, exist_ok=True)
    with (output / ".release.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ReleaseError(f"Another release command is using {output}")
        release(args, identity, team, profile, expected, output)


if __name__ == "__main__":
    try:
        main()
    except Pending as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
    except (ReleaseError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        sys.exit(1)
