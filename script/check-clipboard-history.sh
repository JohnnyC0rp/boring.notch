#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-clipboard-check.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
swiftc -swift-version 5 -o "$build_dir/clipboard-history-tests" \
  "$repo_dir/boringNotch/models/ClipboardHistoryItem.swift" \
  "$repo_dir/boringNotch/managers/ClipboardHistoryManager.swift" \
  "$repo_dir/tests/ClipboardHistoryTests.swift"
"$build_dir/clipboard-history-tests"
