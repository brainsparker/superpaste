#!/usr/bin/env python3
"""Fail-closed release checks. Commands are injectable for tests; no publishing here."""
import argparse
import base64
import json
from pathlib import Path
import plistlib
import re
import subprocess


class PolicyError(RuntimeError):
    pass


def build_number(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise PolicyError("Build versions must contain one to three numeric components")
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3-len(parts))


def validate_versions(version, build, published):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise PolicyError("Release version must be a numeric major.minor.patch")
    current = build_number(build)
    if current <= (0, 0, 0):
        raise PolicyError("Build number must be positive")
    for tag, previous in published:
        if tag == 'v'+version:
            raise PolicyError("Published releases are immutable; choose a new version")
        if current <= build_number(previous):
            raise PolicyError("CFBundleVersion must exceed every published build")


def command(args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True).stdout


def preflight(repo, local=False, skip_notarize=False, run=command):
    info = plistlib.loads((repo/'SuperPaste/Resources/Info.plist').read_bytes())
    validate_versions(info['CFBundleShortVersionString'], info['CFBundleVersion'], [])
    if local:
        return
    if skip_notarize:
        raise PolicyError("--skip-notarize is allowed only with --local")
    if run(['git', 'status', '--porcelain'], repo).strip():
        raise PolicyError("Public releases require a clean source tree")
    identity = run(['security', 'find-identity', '-v', '-p', 'codesigning'], repo)
    if '"Developer ID Application:' not in identity:
        raise PolicyError("Public releases require a Developer ID Application identity")
    run(['xcrun', 'notarytool', 'history', '--keychain-profile', 'superpaste-notary'], repo)
    name = json.loads(run(['gh', 'repo', 'view', '--json', 'nameWithOwner'], repo))['nameWithOwner']
    releases = json.loads(run(['gh', 'release', 'list', '--limit', '1000', '--json', 'tagName,isDraft'], repo))
    published = []
    for release in releases:
        if release['isDraft']:
            continue
        tag = release['tagName']
        # Read the immutable tag's version metadata. Failure blocks public publishing.
        result = json.loads(run(['gh', 'api', f'repos/{name}/contents/SuperPaste/Resources/Info.plist?ref={tag}'], repo))
        previous = plistlib.loads(base64.b64decode(result['content']))['CFBundleVersion']
        published.append((tag, previous))
    validate_versions(info['CFBundleShortVersionString'], info['CFBundleVersion'], published)
    head = run(['git', 'rev-parse', 'HEAD'], repo).strip()
    tag = 'v'+info['CFBundleShortVersionString']
    remote = run(['git', 'ls-remote', 'origin', f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}'], repo).splitlines()
    refs = dict(line.split() for line in remote)
    tagged = next((sha for sha, ref in refs.items() if ref.endswith('^{}')), None)
    tagged = tagged or next(iter(refs), None)
    if tagged and tagged != head:
        raise PolicyError("Release tag must identify the exact source commit being packaged")


def verify_architectures(app, run=command):
    binaries = []
    magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce'}
    for path in app.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as source:
            if source.read(4) in magic:
                binaries.append(path)
    if app/"Contents/MacOS/SuperPaste" not in binaries:
        raise PolicyError("The app executable is missing or is not Mach-O")
    for binary in binaries:
        run(['lipo', str(binary), '-verify_arch', 'arm64', 'x86_64'], app.parent)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--local', action='store_true')
    parser.add_argument('--skip-notarize', action='store_true')
    parser.add_argument('--verify-app', type=Path)
    args = parser.parse_args()
    try:
        if args.verify_app:
            verify_architectures(args.verify_app)
        else:
            preflight(args.repo, args.local, args.skip_notarize)
    except (PolicyError, subprocess.CalledProcessError, ValueError, KeyError) as error:
        raise SystemExit(f'Release blocked: {error}')
