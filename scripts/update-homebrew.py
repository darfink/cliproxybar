#!/usr/bin/env python3
"""Update the same-repository cask after a universal release is published."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
CASK = "Casks/cliproxybar.rb"


def release_version(tag):
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ValueError("Expected a stable release tag, such as v0.2.4")
    return tag[1:]


def checksum(path, version):
    fields = path.read_text().split()
    expected = f"CLIProxyBar-{version}-macOS-universal.zip"
    if len(fields) != 2 or not re.fullmatch(r"[a-f0-9]{64}", fields[0]) or fields[1] != expected:
        raise ValueError("Expected the SHA-256 checksum for this version's universal ZIP")
    return fields[0]


def updated_cask(source, version, digest):
    match = re.search(r'^  version "([0-9]+\.[0-9]+\.[0-9]+)"$', source, re.MULTILINE)
    if not match:
        raise ValueError("Cask version is missing")
    if tuple(map(int, match[1].split("."))) > tuple(map(int, version.split("."))):
        return source  # Re-running an old release must never downgrade the tap.
    source, count = re.subn(r'^  version "[^"]+"$', f'  version "{version}"', source, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("Expected one cask version")
    source, count = re.subn(r'^  sha256 "[a-f0-9]{64}"$', f'  sha256 "{digest}"', source, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("Expected one cask checksum")
    return source


def publish(repo, version, digest):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        raise ValueError("Invalid GitHub repository")
    endpoint = f"repos/{repo}/contents/{CASK}"
    current = json.loads(subprocess.check_output(["gh", "api", "--method", "GET", endpoint, "-f", "ref=main"]))
    source = base64.b64decode(current["content"]).decode()
    updated = updated_cask(source, version, digest)
    if updated == source:
        print("Homebrew cask is already current")
        return
    payload = {"message": f"Update Homebrew cask to {version}", "branch": "main", "sha": current["sha"],
               "content": base64.b64encode(updated.encode()).decode()}
    subprocess.run(["gh", "api", "--method", "PUT", endpoint, "--input", "-"],
                   input=json.dumps(payload).encode(), check=True, stdout=subprocess.DEVNULL)
    print(f"Published Homebrew cask for {version}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("checksum_file", type=Path)
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "darfink/cliproxybar"))
    args = parser.parse_args()
    version = release_version(args.tag)
    digest = checksum(args.checksum_file, version)
    if args.publish:
        publish(args.repo, version, digest)
    else:
        path = ROOT / CASK
        path.write_text(updated_cask(path.read_text(), version, digest))
        print(f"Updated local Homebrew cask for {version}")


if __name__ == "__main__":
    main()
