#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/opentranstype.xcodeproj"
SCHEME="opentranstype"
CONFIGURATION="Debug"
DERIVED_DATA="$ROOT_DIR/.derivedData"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/opentranstype.app"
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
  /bin/ps -axo pid=,command= | while read -r pid command; do
    case "$command" in
      "$LOCAL_PROCESS_PATTERN"*) printf '%s\n' "$pid" ;;
    esac
  done
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
  sleep 1
  [[ -n "$(local_app_pids)" ]]
fi
