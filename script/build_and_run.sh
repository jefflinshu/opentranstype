#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/opentranstype.xcodeproj"
SCHEME="opentranstype"
CONFIGURATION="Debug"
DERIVED_DATA="$ROOT_DIR/.derivedData"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/opentranstype.app"
BUNDLE_ID="com.curisaas.www.opentranstype"
PROCESS_PATTERN=".app/Contents/MacOS/opentranstype"
LOCAL_PROCESS_PATTERN="$APP_PATH/Contents/MacOS/opentranstype"

cd "$ROOT_DIR"

app_pids() {
  /bin/ps -axo pid=,command= | while read -r pid command; do
    case "$command" in
      /*"$PROCESS_PATTERN"*) printf '%s\n' "$pid" ;;
    esac
  done
}

local_app_pids() {
  bundle_app_pids
  local_process_pids
}

bundle_app_pids() {
  /usr/bin/osascript -l JavaScript <<OSA 2>/dev/null || true
ObjC.import('AppKit')
const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier('$BUNDLE_ID')
for (let i = 0; i < apps.count; i++) {
  const app = apps.objectAtIndex(i)
  const bundleURL = app.bundleURL
  if (bundleURL && ObjC.unwrap(bundleURL.path) === '$APP_PATH') {
    console.log(app.processIdentifier)
  }
}
OSA
}

local_process_pids() {
  /bin/ps -axo pid=,command= | while read -r pid command; do
    case "$command" in
      "$LOCAL_PROCESS_PATTERN"*|*"$LOCAL_PROCESS_PATTERN"*) printf '%s\n' "$pid" ;;
    esac
  done
}

wait_for_local_app() {
  for _ in {1..100}; do
    [[ -n "$(local_app_pids)" ]] && return 0
    sleep 0.1
  done
  return 1
}

existing_pids="$(app_pids)"
if [[ -n "$existing_pids" ]]; then
  while read -r pid; do
    [[ -n "$pid" ]] && /bin/kill "$pid" 2>/dev/null || true
  done <<< "$existing_pids"

  for _ in {1..20}; do
    [[ -z "$(app_pids)" ]] && break
    sleep 0.1
  done

  remaining_pids="$(app_pids)"
  if [[ -n "$remaining_pids" ]]; then
    while read -r pid; do
      [[ -n "$pid" ]] && /bin/kill -9 "$pid" 2>/dev/null || true
    done <<< "$remaining_pids"
  fi
fi

/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  build

/usr/bin/open -n "$APP_PATH"

if [[ "${1:-}" == "--verify" ]]; then
  wait_for_local_app
fi
