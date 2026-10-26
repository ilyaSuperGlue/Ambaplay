#!/bin/sh
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
    echo "This smoke test requires macOS." >&2
    exit 2
fi

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/ambaplay-installer.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

xcrun --find swiftc >/dev/null
xcrun swiftc -swift-version 6 \
    "$repo_root"/app/Sources/AmbaplayInstallerCore/*.swift \
    "$repo_root"/installer/tests/native-installer-core-smoke.swift \
    -o "$work_dir/native-installer-core-smoke"

"$work_dir/native-installer-core-smoke" "$work_dir/fixtures"
