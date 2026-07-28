#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="boringNotch"
BUNDLE_ID="theboringteam.boringnotch"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/boringNotch.xcodeproj"
DERIVED_DATA="$ROOT_DIR/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

build_app() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -disableAutomaticPackageResolution \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

if [[ "$MODE" == "--build" || "$MODE" == "build" ]]; then
  # Build-only mode keeps an installed copy running while Xcode does its thing.
  build_app
  exit 0
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
