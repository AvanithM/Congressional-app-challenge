#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "Expected two arguments: the connected Android device ID and API base URL." >&2
  exit 2
fi

device_id=$1
api_base_url=${2%/}

if command -v adb >/dev/null 2>&1; then
  adb_bin=$(command -v adb)
elif [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
  adb_bin="$HOME/Library/Android/sdk/platform-tools/adb"
else
  echo "adb was not found. Add the Android SDK platform-tools directory to PATH." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter was not found. Add the Flutter SDK bin directory to PATH." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl was not found; it is required to verify the backend before launch." >&2
  exit 1
fi

if ! "$adb_bin" -s "$device_id" get-state 2>/dev/null | grep -qx device; then
  echo "Android device '$device_id' is not connected or is not authorized." >&2
  echo "Check 'adb devices' and accept the debugging authorization prompt." >&2
  exit 1
fi

case "$api_base_url" in
  http://*|https://*) ;;
  *)
    echo "API base URL must start with http:// or https://." >&2
    exit 2
    ;;
esac

if ! curl --fail --silent --show-error --max-time 5 \
  "$api_base_url/api/health" >/dev/null; then
  echo "Java backend is not healthy at $api_base_url/api/health." >&2
  echo "Check the URL, Wi-Fi, computer firewall, and that App.java is running." >&2
  exit 1
fi

"$adb_bin" -s "$device_id" reverse --remove tcp:8080 >/dev/null 2>&1 || true

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

flutter build apk --debug --dart-define=API_BASE_URL="$api_base_url"

"$adb_bin" -s "$device_id" install --no-streaming -r \
  build/app/outputs/flutter-apk/app-debug.apk
"$adb_bin" -s "$device_id" shell am force-stop com.example.congress_app
"$adb_bin" -s "$device_id" shell am start -n com.example.congress_app/.MainActivity
