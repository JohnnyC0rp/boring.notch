#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

xcrun swiftc -parse-as-library \
    -I "$repo_root/DerivedData/Build/Products/Release" \
    "$repo_root/boringNotch/extensions/PanGesture.swift" \
    "$repo_root/boringNotch/components/Calendar/CalendarTimelineGeometry.swift" \
    "$repo_root/boringNotch/components/Calendar/HomeCalendarGeometry.swift" \
    "$repo_root/boringNotch/components/Calendar/HomeCalendarScrollView.swift" \
    "$repo_root/tests/PanGestureScrollRoutingTests.swift" \
    "$repo_root/DerivedData/Build/Products/Release/Defaults.o" \
    -o "$test_directory/calendar-wheel-tests"
"$test_directory/calendar-wheel-tests"
