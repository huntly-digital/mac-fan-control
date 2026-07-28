#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MFanControlApp"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/Products/MFanControl.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
BUNDLE_ID="io.clover.mfancontrol"

stop_running_app() {
  local process_ids
  local pgrep_status

  set +e
  process_ids="$(/usr/bin/pgrep -x "$APP_NAME" 2>&1)"
  pgrep_status=$?
  set -e

  case "$pgrep_status" in
    0)
      if ! /usr/bin/pkill -x "$APP_NAME"; then
        echo "Could not stop the running $APP_NAME process." >&2
        exit 1
      fi
      ;;
    1)
      return
      ;;
    *)
      echo "Could not inspect the running $APP_NAME process:" >&2
      echo "$process_ids" >&2
      exit 1
      ;;
  esac

  for _ in {1..50}; do
    set +e
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1
    pgrep_status=$?
    set -e
    case "$pgrep_status" in
      1)
        return
        ;;
      0)
        /bin/sleep 0.1
        ;;
      *)
        echo "Could not verify that $APP_NAME stopped." >&2
        exit 1
        ;;
    esac
  done

  echo "$APP_NAME did not stop before its app bundle was rebuilt." >&2
  exit 1
}

stop_running_app
make -C "$ROOT_DIR" app

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

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
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
