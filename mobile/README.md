# Congress App mobile

## Requirements

- Flutter and Dart versions supported by `pubspec.yaml`.
- Android development: Android Studio with the Android SDK and an emulator, or
  a USB-connected Android device.
- iOS development: macOS with full Xcode installed, Xcode command-line tools
  selected, CocoaPods installed, and an iOS simulator or connected device.

Check the local setup with:

```sh
flutter doctor -v
flutter pub get
flutter devices
```

## Running the app

Install the backend's Python dependencies and start the Java API from the
repository root:

```sh
python3 -m pip install -r backend/requirements.txt
javac -d backend/bin backend/src/App.java
java -cp backend/bin App
```

The Java API listens on port `8080` and starts the Python service on port `5000`
when needed. Java must already be running: the Flutter app checks the Java
health endpoint and asks Java to start Python, but it cannot launch the Java
process on your computer. Keep the terminal running `App.java` open while
testing. Check-in, follow-up, support-guidance, and progress features call the
API directly.

The API client defaults to `http://10.0.2.2:8080` on Android emulators (the
emulator's address for reaching the host computer) and
`http://127.0.0.1:8080` on other platforms. Android phones do not have the
emulator's `10.0.2.2` host address. Configure a physical phone with the
computer's Wi-Fi address using `API_BASE_URL`; the Wi-Fi setup below does this
and checks the backend before launching. For a deployed backend, configure
`API_BASE_URL` to its HTTPS URL:

```sh
flutter run -d <device-id> \
  --dart-define=API_BASE_URL=https://your-api.example.com
```

For a physical device on a development network, use the development computer's
LAN address and ensure the device can reach port `8080`. On iOS, approve the
local-network prompt when it appears. Android allows cleartext HTTP only in
debug builds. Prefer HTTPS outside local development.

For a physical device or a published app, configure `API_BASE_URL` to a
reachable, deployed HTTPS API. The emulator and localhost defaults are for
development only; they will not reach your development computer from a
downloaded app.

### Run on a physical phone over Wi-Fi (recommended)

Connect the phone and development computer to the same trusted, non-guest
Wi-Fi network. Start the Java backend using the instructions above. Find the
computer's current Wi-Fi IPv4 address (on macOS, run
`ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"`).
The phone cannot use `127.0.0.1` or Android emulator address `10.0.2.2` to
reach the computer. From the repository root, run:

```sh
flutter devices
sh mobile/run_android_wifi.sh <device-id> http://<computer-wifi-ip>:8080
```

The device can be attached to ADB by USB or Android Wireless Debugging; the
app's API traffic itself goes over Wi-Fi, not `adb reverse`. The helper checks
that the backend is healthy, builds the app with the supplied `API_BASE_URL`,
removes any stale USB reverse mapping, installs the APK, and launches it. It
uses ADB's non-streaming install mode to avoid intermittent streamed-install
failures. The computer's Wi-Fi IP may change, so rebuild and reinstall with its
current address when that happens. If the health check fails from the computer
or phone, check that Java is running, both devices are on the same network,
client isolation is disabled, and the computer firewall allows incoming
connections on port `8080`.

`API_BASE_URL` is a compile-time Flutter setting. When attaching the Flutter
debugger or launching the app manually, pass the same URL every time:

```sh
flutter attach -d <device-id> \
  --dart-define=API_BASE_URL=http://<computer-wifi-ip>:8080
```

Omitting that define on an Android phone falls back to `10.0.2.2`, which is
only reachable from an Android emulator and can make a hot restart appear to
break a previously working Wi-Fi build.

For Android Wireless Debugging, enable it in Developer options and use Android
Studio's Pair Devices Using Wi-Fi flow (or `adb pair <phone-ip>:<pairing-port>`
with the pairing code shown on the phone). Then connect with
`adb connect <phone-ip>:<debug-port>` and use the resulting device ID with the
Wi-Fi helper. ADB wireless pairing is for installing/debugging the app; it is
separate from the app's Wi-Fi connection to the backend.

### Run on a physical phone over USB

The phone runs only the Flutter app. Keep the Java API process running in a
terminal on your development computer; Java starts the Python service when
needed. The Python service calls
`http://localhost:11434/v1/chat/completions`, so Ollama and the `llama3.1`
model must be available on that same computer; replacing Ollama with a hosted
model API is not required for local phone testing.

First, from the repository root, install Python dependencies:

```sh
python3 -m pip install -r backend/requirements.txt
```

If Ollama is not already running on the computer, start it in a separate
terminal:

```sh
ollama serve
```

Download the model once if it is not already installed:

```sh
ollama pull llama3.1
```

In another terminal at the repository root, compile and run the Java API:

```sh
javac -d backend/bin backend/src/App.java
java -cp backend/bin App
```

Keep both services running. The Java API starts the Python service
automatically when the Flutter app connects.

For Android over USB, enable Developer options and USB debugging on the phone,
connect it to the computer, and accept the debugging authorization prompt.
On macOS, add the Android SDK tools to `PATH` in the terminal you use to run
the app. If Android Studio installed the SDK in its default location:

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
adb devices
```

Once the phone appears as `device` (not `unauthorized`), run this from the
repository root:

```sh
sh mobile/run_android_usb.sh <device-id>
```

The helper verifies that Java is responding, creates the USB port-forward for
that phone, and runs the Flutter app with the matching `127.0.0.1` API URL.
USB forwarding is removed when the phone disconnects, so run the helper again
after reconnecting. The debug Android manifest permits cleartext HTTP for local
development only; release builds do not inherit that setting.

For Android phones over Wi-Fi, keep the phone and computer on the same
non-guest network and run from `mobile` with the computer's current LAN
address:

```sh
flutter run -d <device-id> \
  --dart-define=API_BASE_URL=http://<computer-lan-ip>:8080
```

Allow incoming Java connections through the computer's firewall. LAN addresses
can change, and Wi-Fi client isolation may block devices from reaching each
other. For an app that should work on phones without a development computer or
USB setup, deploy the backend at a stable HTTPS address and configure
`API_BASE_URL` to that address; a Flutter app cannot automatically start a
Java server running on your computer.

For an iPhone, connect it by USB, tap Trust on the phone, and enable Developer
Mode if prompted. In Xcode, open `ios/Runner.xcworkspace`, select the Runner
target's Signing & Capabilities tab, enable automatic signing, choose your
Apple development team, and set a unique bundle identifier. Keep the Mac and
iPhone on the same Wi-Fi network, then run this from `mobile`:

```sh
flutter pub get
flutter devices
flutter run -d <device-id> \
  --dart-define=API_BASE_URL=http://<mac-lan-ip>:8080
```

Replace `<mac-lan-ip>` with the Mac's Wi-Fi IPv4 address (System Settings >
Wi-Fi > Details > TCP/IP). Approve the app's local-network access prompt on
the iPhone. Allow incoming connections for Java in the macOS firewall if the
phone cannot reach the server. Keep the phone and computer on the same
non-guest Wi-Fi network. Do not use this local HTTP setup for a public release;
use a deployed HTTPS API instead.

Dangerous check-in guidance is retrieved from `/api/checkins/support` before
the app advances. Android and iOS show it as a local notification; when system
notifications are unavailable or denied, the app displays the guidance in a
dialog. Goal reminders are scheduled locally for 9:00 a.m. the day before a
goal is due on Android and iOS. Scheduled reminders and system notifications
are not supported in the browser build.

## Verification and builds

```sh
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
flutter build ios --release
```

iOS release builds require Xcode signing and an Apple Developer account.
Android store releases require a private release signing key; the current
Android Gradle setup uses the debug key as a development placeholder. The
Android application ID and iOS bundle ID are still example identifiers and
must be replaced with identifiers owned by the publisher before distribution
or Firebase configuration. A direct Android APK download can be hosted as a
file; iOS distribution requires Apple signing and distribution through
TestFlight, the App Store, or an appropriately provisioned device build.

The app includes Firebase dependencies but does not initialize Firebase. Set
up Firebase options before adding Firebase-backed features.
