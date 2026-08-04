#!/usr/bin/env bash
# Quit Mancia, reset its macOS privacy grants, rebuild the app, and relaunch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mancia"
BUNDLE="$ROOT/build/$APP_NAME.app"
PLIST="$ROOT/Support/Info.plist"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$PLIST")"

echo "==> closing $APP_NAME"
if pgrep -x "$APP_NAME" >/dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
    for _ in {1..20}; do
        if ! pgrep -x "$APP_NAME" >/dev/null; then
            break
        fi
        sleep 0.1
    done
fi

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "==> forcing $APP_NAME to close"
    pkill -TERM -x "$APP_NAME"
    for _ in {1..20}; do
        if ! pgrep -x "$APP_NAME" >/dev/null; then
            break
        fi
        sleep 0.1
    done
fi

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "==> killing unresponsive $APP_NAME"
    pkill -KILL -x "$APP_NAME"
fi

echo "==> resetting macOS permissions for $BUNDLE_ID"
tccutil reset All "$BUNDLE_ID"

"$ROOT/scripts/make_app.sh"

echo "==> launching $BUNDLE"
open "$BUNDLE"