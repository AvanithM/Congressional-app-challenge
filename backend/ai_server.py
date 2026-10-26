import json
from datetime import datetime
from pathlib import Path
from threading import Lock

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)
API_URL = "http://localhost:11434/v1/chat/completions"
DQP = (
    "Generate one thoughtful follow-up question based on the user's response. "
    "Return only the question."
)
DSP = (
    "Generate one practical, supportive suggestion based on the user's response. "
    "Return only the suggestion."
)
DCP = (
    "Analyze the user's response for expressed emotions, communication tones, and safety concerns. "
    "This is a text classification, not a diagnosis. Use only evidence in the response. "
    "Return exactly one JSON object with this schema: "
    '{"emotions":["..."],"tones":["..."],"danger_level":"none|concerning|urgent",'
    '"dangerous":false,"danger_type":null}. '
    "Use brief lowercase labels for emotions and tones; either list may be empty. "
    "Set danger_level to none and dangerous to false when there is no specific safety concern, "
    "and danger_type to null. Set dangerous to true and provide a concise danger_type when "
    "danger_level is concerning or urgent. Use concerning for a specific but non-immediate "
    "risk, and urgent only for an explicit or clearly immediate risk of serious harm to the "
    "user or another person. Do not treat ordinary sadness, stress, or frustration alone as "
    "a danger event. Return JSON only, with no markdown or extra text."
)
DGP = (
    "Generate one possible goal the user could choose for themselves. "
    "Return exactly one JSON object with exactly these two fields: "
    '{"goal":"...","time_span_days":7}. '
    "The time_span_days value must be a positive integer representing a "
    "definite duration in days. Do not include other fields, markdown, or text."
)
INPUT_FILE = Path("ai_server.in")
OUTPUT_FILE = Path("ai_server.out")
HISTORY_FILE = Path("checkin_history.jsonl")
process_lock = Lock()


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200
#checks if the python server is available before passing calls

def request_ai_response(prompt, json_mode=False):
    payload = {
        "model": "llama3.1",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 100,
        "temperature": 0.7,
    }
    if json_mode:
        payload["response_format"] = {"type": "json_object"}

    try:
        response = requests.post(API_URL, json=payload, timeout=30)
    except requests.RequestException as error:
        return None, f"Could not connect to Ollama: {error}", 502

    try:
        result = response.json()
    except ValueError:
        return None, f"Non-JSON response from Ollama: {response.text}", 502

    if response.status_code != 200:
        error = result.get("error", "Unknown error") if isinstance(result, dict) else result
        message = error.get("message", str(error)) if isinstance(error, dict) else str(error)
        return None, f"Ollama request failed: {message}", response.status_code

    try:
        answer = result["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        return None, "Ollama returned an unexpected response structure.", 502

    if not isinstance(answer, str):
        return None, "Ollama returned a response that was not text.", 502
    return answer, None, 200


def parse_classification(answer):
    try:
        classification = json.loads(answer)
    except json.JSONDecodeError:
        return None, "Classification response was not valid JSON."

    if not isinstance(classification, dict):
        return None, "Classification response must be a JSON object."

    emotions = classification.get("emotions")
    tones = classification.get("tones")
    danger_level = classification.get("danger_level")
    dangerous = classification.get("dangerous")
    danger_type = classification.get("danger_type")

    for name, labels in (("emotions", emotions), ("tones", tones)):
        if not isinstance(labels, list) or any(
            not isinstance(label, str) or not label.strip() for label in labels
        ):
            return None, f"Classification field '{name}' must be a list of non-empty strings."

    if danger_level not in ("none", "concerning", "urgent"):
        return None, "Classification field 'danger_level' must be none, concerning, or urgent."
    if not isinstance(dangerous, bool):
        return None, "Classification field 'dangerous' must be a boolean."
    if dangerous != (danger_level != "none"):
        return None, "Classification fields 'dangerous' and 'danger_level' conflict."
    if dangerous:
        if not isinstance(danger_type, str) or not danger_type.strip():
            return None, "A dangerous classification must include a non-empty danger_type."
        danger_type = danger_type.strip().casefold()
    elif danger_type is not None:
        return None, "danger_type must be null when danger_level is none."

    return {
        "emotions": list(dict.fromkeys(label.strip().casefold() for label in emotions)),
        "tones": list(dict.fromkeys(label.strip().casefold() for label in tones)),
        "danger_level": danger_level,
        "dangerous": dangerous,
        "danger_type": danger_type,
    }, None


def parse_goal(answer):
    try:
        goal = json.loads(answer)
    except json.JSONDecodeError:
        return None, "Goal response was not valid JSON."

    if not isinstance(goal, dict) or set(goal) != {"goal", "time_span_days"}:
        return None, "Goal response must contain only 'goal' and 'time_span_days'."
    if not isinstance(goal["goal"], str) or not goal["goal"].strip():
        return None, "Goal must be a non-empty string."
    time_span_days = goal["time_span_days"]
    if (
        not isinstance(time_span_days, int)
        or isinstance(time_span_days, bool)
        or time_span_days < 1
    ):
        return None, "time_span_days must be a positive integer."

    return {
        "goal": goal["goal"].strip(),
        "time_span_days": time_span_days,
    }, None


@app.route("/process_input", methods=["POST"])
def process_input():
    data = request.get_json(silent=True) if request.data else {}
    
    if not isinstance(data, dict):
        return jsonify({"error": "Expected a JSON object with optional prompt strings."}), 400
    user_id = data.get("user_id")
    timestamp = data.get("timestamp")
    timezone_offset_minutes = data.get("timezone_offset_minutes")
    if not isinstance(user_id, str) or not user_id.strip():
        return jsonify({"error": "A non-empty user_id is required."}), 400
    if not isinstance(timestamp, str):
        return jsonify({"error": "An ISO-8601 timestamp is required."}), 400
    try:
        parsed_timestamp = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError:
        return jsonify({"error": "timestamp must be a valid ISO-8601 timestamp."}), 400
    if parsed_timestamp.tzinfo is None:
        return jsonify({"error": "timestamp must include a timezone."}), 400
    if (
        not isinstance(timezone_offset_minutes, int)
        or isinstance(timezone_offset_minutes, bool)
        or timezone_offset_minutes < -14 * 60
        or timezone_offset_minutes > 14 * 60
    ):
        return jsonify({"error": "timezone_offset_minutes must be a valid UTC offset."}), 400


    with process_lock:
        try:
            lines = INPUT_FILE.read_text(encoding="utf-8").splitlines()
        except OSError as error:
            return jsonify({"error": f"Could not read {INPUT_FILE}: {error}"}), 500

        results = []
        for line_number, line in enumerate(lines, start=1):
            text = line.strip()
            if not text:
                continue
            goal_response, error, status_code = request_ai_response(
                f"{DGP}\n\nUser response:\n{text}", json_mode=True
            )
            if error is not None:
                return jsonify({"error": f"Could not generate a goal for input Line {line_number}: {error}"}), status_code
            goal, error = parse_goal(goal_response)
            if error is not None:
                return jsonify({"error": f"Could not parse a goal for input line {line_number}: {error}"}), 502
            #sends the question prompt
            question, error, status_code = request_ai_response(f"{DQP}\n\nUser response:\n{text}")
            if error is not None:
                return jsonify({"error": f"Could not generate a question for input line {line_number}: {error}"}), status_code
            #sends the suggestion prompt
            suggestion, error, status_code = request_ai_response(f"{DSP}\n\nUser response:\n{text}")

            if error is not None:
                return jsonify({"error": f"Could not generate a suggestion for input line {line_number}: {error}"}), status_code
            #sends the classification prompt
            classification_response, error, status_code = request_ai_response(f"{DCP}\n\nUser response:\n{text}",json_mode=True,)
            if error is not None:
                return jsonify({"error": f"Could not classify input line {line_number}: {error}"}), status_code
            classification, error = parse_classification(classification_response)
            if error is not None:
                return jsonify({ "error": f"Could not classify input line {line_number}: {error}"}), 502
            # ai_server.out output for development uses
            results.append({
                "input": text,
                "question": question,
                "suggestion": suggestion,
                "classification": classification,
                "goal": goal,
                "user_id": user_id,
                "timestamp": timestamp,
                "timezone_offset_minutes": timezone_offset_minutes,
            })
        #splits the data into seperate json files
        questions = [
            {"input": item["input"], "question": item["question"]}
            for item in results
        ]
        suggestions = [
            {"input": item["input"], "suggestion": item["suggestion"]}
            for item in results
        ]
        classifications = [
            {"input": item["input"], "classification": item["classification"]}
            for item in results
        ]
        goals = [
            {"input": item["input"], "goal": item["goal"]}
            for item in results
        ]
        history_entries = [
            {
                "user_id": item["user_id"],
                "timestamp": item["timestamp"],
                "timezone_offset_minutes": item["timezone_offset_minutes"],
                "emotions": item["classification"]["emotions"],
                "danger_level": item["classification"]["danger_level"],
            }
            for item in results
        ]
        try:
            for filename, data in (
                ("questions.json", questions),
                ("suggestions.json", suggestions),
                ("classifications.json", classifications),
                ("goals.json", goals),
            ):
                Path(filename).write_text(json.dumps(data,ensure_ascii=False, indent=2), encoding="utf-8",)
        except OSError as error:
            return jsonify({"error": f"could not write split output files: {error}"}), 500
        try:
            with HISTORY_FILE.open("a", encoding="utf-8") as history_file:
                for entry in history_entries:
                    history_file.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError as error:
            return jsonify({"error": f"Could not append {HISTORY_FILE}: {error}"}), 500
        #original full jsonified output
        try:
            output = {
                "status": "ok",
                "processed": len(results),
                "user_id": user_id,
                "timestamp": timestamp,
                "timezone_offset_minutes": timezone_offset_minutes,
                "results": results,
                "goals": goals,
            }
            OUTPUT_FILE.write_text(
                json.dumps(output, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except OSError as error:
            return jsonify({"error": f"Could not write {OUTPUT_FILE}: {error}"}), 500

        return jsonify({"status": "ok", "processed": len(results)}), 200

@app.route("/progress/history", methods=["GET"])
def getProgressHistory():
    user_id = request.args.get("user_id", "").strip()
    if not user_id:
        return jsonify({"error": "user_id is required."})
    records = []
    try:
        if HISTORY_FILE.exists():
            with HISTORY_FILE.open(encoding="utf-8") as histroy_file:
                for line in histroy_file:
                    if not line.strip():
                        continue
                    record = json.loads(line)
                    if record.get("user_id") == user_id:
                        records.append(record)
    except(OSError, json.JSONDecodeError) as error:
        return jsonify({"error": f"could not read check-in history: {error}"}), 500

    records.sort(key=lambda record: record["timestamp"])
    return jsonify({"records": records}), 200

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
