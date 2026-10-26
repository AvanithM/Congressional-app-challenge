# Congress App

A Flutter mobile app with a Java HTTP API and a local Python service for
AI-assisted daily check-ins, goal suggestions, support guidance, and progress
history.

## Project layout

- `mobile/` — Flutter app for Android, iOS, web, and desktop.
- `backend/src/App.java` — Java API server on port `8080`.
- `backend/ai_server.py` — Python API on loopback port `5000`; Java starts it
  when needed.
- `backend/memory_manager.py` and `backend/support_prompts.py` — local
  check-in summaries and support guidance.

## Local development

Install Java, Python 3, Flutter, and Ollama. From the project root, install the
Python dependencies:

```sh
python3 -m pip install -r backend/requirements.txt
```

Start Ollama and ensure the `llama3.1` model is installed:

```sh
ollama serve
ollama pull llama3.1
```

In another terminal, compile and start the Java API:

```sh
javac -d bin backend/src/App.java
java -cp bin App
```

The Java server must remain running while using the app. It starts the Python
service on demand. Generated check-in history, prompts, and memory data remain
local and are excluded from Git.

For Flutter setup, Android/iOS device instructions, and physical-phone Wi-Fi
configuration, see [mobile/README.md](mobile/README.md).

## Tests

Run the Flutter checks from the `mobile/` directory:

```sh
flutter analyze
flutter test
```

## AI-assisted development note

AI assisted with parts of the API integration and wiring. The project authors
are responsible for reviewing and validating behavior before use.