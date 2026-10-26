#!/bin/sh
# Exercise source-DMG identification without ejecting or trashing user files.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ambaplay-cleanup-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
swiftc -parse-as-library -swift-version 6 \
    "$repo/app/Sources/AmbaplayInstaller/InstallerCleanup.swift" \
    "$repo/installer/tests/native-installer-cleanup-smoke.swift" \
    -o "$work/cleanup-tests"
"$work/cleanup-tests"
