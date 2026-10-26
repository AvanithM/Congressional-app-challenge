# Flutter app

The mobile client provides four sections: Home for daily check-ins and
follow-up prompts, Goals for a saved goal queue and suggestions, Progress for
check-in history and trends, and Settings for reminder and privacy
information. Goals and daily check-in results are stored locally on the
device. Goal reminders and safety notifications are supported on Android and
iOS; browser notifications are not implemented.

## Requirements

- Flutter and Dart compatible with `pubspec.yaml`.
- Android development: Android Studio and the Android SDK.
- iOS development: macOS, Xcode, and CocoaPods.
- Backend features: Java, Python 3, and Ollama with the `llama3.1` model.

From the repository root, install the Python requirements and start Ollama and
the Java API as described in the root [README](../README.md). The Java API
listens on port `8080`; it starts the Python service on loopback port `5000`
when needed. Keep the Java process running while using the app.

From the repository root, install Flutter dependencies and list available
devices:

```sh
cd mobile && flutter pub get && flutter devices
```

## Run on an Android emulator

The default Android API address is `http://10.0.2.2:8080`, which lets an
Android emulator reach the development computer. With the Java backend
running, start the app from `mobile/`:

```sh
cd mobile && flutter run
```

## Run on an Android phone over Wi-Fi

Connect the phone and development computer to the same trusted Wi-Fi network.
Start the backend and get the computer's current Wi-Fi IPv4 address. On macOS,
the following command prints that address:

```sh
ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"
```

Connect the phone to ADB over USB or Android Wireless Debugging, then use the
device ID shown by `flutter devices`. The helper builds and installs a debug
APK with the supplied backend address:

```sh
cd mobile && flutter devices
cd ..
printf "Android device ID: "
read -r DEVICE_ID
printf "Computer Wi-Fi IPv4 address: "
read -r BACKEND_IP
sh mobile/run_android_wifi.sh "$DEVICE_ID" "http://${BACKEND_IP}:8080"
```

The helper checks the backend health endpoint before building. The phone and
computer must be able to reach each other on the network, and the computer
firewall must allow incoming connections on port `8080`. The computer's
address may change; rerun the helper with its current address when it does.
The app's API address is a compile-time Flutter setting, so attach or launch
the app with the same address used to build it.

ADB wireless pairing is only for installing and debugging the app. It is
separate from the app's Wi-Fi connection to the backend.

## Run on an Android phone over USB

Enable USB debugging, connect the phone, approve its debugging prompt, and
confirm it is listed by `flutter devices`. Then run the helper from the
repository root:

```sh
cd mobile && flutter devices
cd ..
printf "Android device ID: "
read -r DEVICE_ID
sh mobile/run_android_usb.sh "$DEVICE_ID"
```

This sets up `adb reverse` for port `8080` and starts Flutter with the
`127.0.0.1` API address. USB reverse forwarding is removed when the phone
disconnects, so run the helper again after reconnecting.

## Run on iOS

For the iOS simulator, run `flutter run` from `mobile/` with the backend
running on the same computer. For a physical iPhone, connect the Mac and phone
to the same Wi-Fi network, approve the app's local-network permission prompt,
and pass the Mac's Wi-Fi IPv4 address as `API_BASE_URL`:

```sh
cd mobile
flutter devices
printf "iPhone device ID: "
read -r DEVICE_ID
printf "Mac Wi-Fi IPv4 address: "
read -r BACKEND_IP
flutter run -d "$DEVICE_ID" \
  --dart-define=API_BASE_URL="http://${BACKEND_IP}:8080"
```

In Xcode, configure signing for the Runner target before installing on a
physical device or making a release build.

## Run in a browser

With the backend running on the same computer, start the web client from
`mobile/`:

```sh
cd mobile && flutter run -d chrome
```

The browser build uses `http://127.0.0.1:8080` by default. Local scheduled
reminders and system notifications are not supported in the browser build.

## API configuration

`API_BASE_URL` can override the platform defaults at build or launch time.
Android emulators default to `http://10.0.2.2:8080`; other platforms default
to `http://127.0.0.1:8080`. A physical phone cannot use either address to
reach the development computer, so use the Wi-Fi helper or a USB reverse
mapping. The app cannot start a Java server on another computer.

The Java API handles health checks, service startup, check-in processing,
memory counts, support guidance, and progress history. Check-in processing
uses Ollama to produce follow-up questions, suggestions, goals, and
classifications. These AI results can be incorrect and are not a diagnosis or
safety assessment.

## Tests and builds

Run from `mobile/`:

```sh
cd mobile
flutter analyze
flutter test
flutter build apk
flutter build appbundle
flutter build ios
```

Release publishing is not configured. Android currently uses the development
application ID `com.example.congress_app` and debug signing; iOS release
signing requires Xcode signing configuration and an Apple Developer account.
Use publisher-owned application identifiers and release signing before
distribution. Source authorship and AI assistance are described in the root
[README](../README.md).
