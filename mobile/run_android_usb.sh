#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Expected one argument: the connected Android device ID." >&2
  exit 2
fi

device_id=$1

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

if ! "$adb_bin" -s "$device_id" get-state 2>/dev/null | grep -qx device; then
  echo "Android device '$device_id' is not connected or is not authorized." >&2
  echo "Check 'adb devices' and accept the USB debugging prompt on the phone." >&2
  exit 1
fi

if ! curl --fail --silent --show-error --max-time 3 \
  http://127.0.0.1:8080/api/health >/dev/null; then
  echo "Java backend is not responding at http://127.0.0.1:8080." >&2
  echo "Start App.java from the repository root, then run this helper again." >&2
  exit 1
fi

"$adb_bin" -s "$device_id" reverse tcp:8080 tcp:8080

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

exec flutter run -d "$device_id" \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080
