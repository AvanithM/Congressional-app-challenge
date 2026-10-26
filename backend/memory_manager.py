import hashlib
import json
from pathlib import Path

CLASSIFICATIONS_FILE = Path("classifications.json")
MEMORY_FILE = Path("memory_counts.json")


def empty_memory():
    return {
        "total_checkins": 0,
        "dangerous_checkins": 0,
        "emotions": {},
        "tones": {},
        "danger_levels": {},
        "danger_types": {},
        "processed_entries": {},
    }


def load_memory():
    if not MEMORY_FILE.exists():
        return empty_memory()

    memory = json.loads(MEMORY_FILE.read_text(encoding="utf-8"))
    if not isinstance(memory, dict):
        raise ValueError(f"{MEMORY_FILE} must contain a JSON object.")

    required_counts = (
        "emotions",
        "tones",
        "danger_levels",
        "danger_types",
    )
    for name in required_counts:
        counts = memory.get(name)
        if not isinstance(counts, dict):
            raise ValueError(f"{MEMORY_FILE} has an invalid '{name}' count.")
        if any(
            not isinstance(count, int) or isinstance(count, bool) or count < 0
            for count in counts.values()
        ):
            raise ValueError(f"{MEMORY_FILE} has an invalid '{name}' count.")
    if (
        not isinstance(memory.get("total_checkins"), int)
        or isinstance(memory["total_checkins"], bool)
        or memory["total_checkins"] < 0
    ):
        raise ValueError(f"{MEMORY_FILE} has an invalid total_checkins count.")
    if (
        not isinstance(memory.get("dangerous_checkins"), int)
        or isinstance(memory["dangerous_checkins"], bool)
        or memory["dangerous_checkins"] < 0
    ):
        raise ValueError(f"{MEMORY_FILE} has an invalid dangerous_checkins count.")
    entries = memory.get("processed_entries")
    if not isinstance(entries, dict) or any(
        not isinstance(entry, str)
        or not isinstance(count, int)
        or isinstance(count, bool)
        or count < 0
        for entry, count in entries.items()
    ):
        raise ValueError(f"{MEMORY_FILE} has invalid processed entry counts.")

    return memory


def add_labels(counts, labels, item_number, field_name):
    if not isinstance(labels, list):
        raise ValueError(f"Entry {item_number}: '{field_name}' must be a list.")

    unique_labels = []
    for label in labels:
        if not isinstance(label, str) or not label.strip():
            raise ValueError(
                f"Entry {item_number}: '{field_name}' must contain non-empty strings."
            )
        label = label.strip().casefold()
        if label not in unique_labels:
            unique_labels.append(label)

    for label in unique_labels:
        counts[label] = counts.get(label, 0) + 1


def print_frequencies(title, counts, total):
    print(f"\n{title}:")
    if not counts:
        print("  No occurrences.")
        return

    for label, count in sorted(counts.items()):
        percentage = count / total * 100 if total else 0
        print(f"  {label}: {count} check-ins ({percentage:.1f}%)")


def add_classification(memory, classification, item_number):
    add_labels(
        memory["emotions"],
        classification.get("emotions"),
        item_number,
        "emotions",
    )
    add_labels(
        memory["tones"],
        classification.get("tones"),
        item_number,
        "tones",
    )

    danger_level = classification.get("danger_level")
    if danger_level not in ("none", "concerning", "urgent"):
        raise ValueError(f"Entry {item_number} has an invalid danger_level.")
    memory["danger_levels"][danger_level] = (
        memory["danger_levels"].get(danger_level, 0) + 1
    )

    dangerous = classification.get("dangerous")
    if not isinstance(dangerous, bool):
        raise ValueError(f"Entry {item_number}: 'dangerous' must be true or false.")
    if dangerous != (danger_level != "none"):
        raise ValueError(f"Entry {item_number}: dangerous and danger_level conflict.")

    if dangerous:
        danger_type = classification.get("danger_type")
        if not isinstance(danger_type, str) or not danger_type.strip():
            raise ValueError(
                f"Entry {item_number}: dangerous entries need a danger_type."
            )
        danger_type = danger_type.strip().casefold()
        memory["dangerous_checkins"] += 1
        memory["danger_types"][danger_type] = (
            memory["danger_types"].get(danger_type, 0) + 1
        )
    elif classification.get("danger_type") is not None:
        raise ValueError(
            f"Entry {item_number}: danger_type must be null when not dangerous."
        )

    memory["total_checkins"] += 1


def main():
    try:
        classifications = (
            json.loads(CLASSIFICATIONS_FILE.read_text(encoding="utf-8"))
            if CLASSIFICATIONS_FILE.exists()
            else []
        )
        if not isinstance(classifications, list):
            raise ValueError(f"{CLASSIFICATIONS_FILE} must contain a JSON array.")

        memory = load_memory()
        batch_occurrences = {}
        new_checkins = 0
        for item_number, item in enumerate(classifications, start=1):
            if not isinstance(item, dict):
                raise ValueError(f"Entry {item_number} must be a JSON object.")

            classification = item.get("classification")
            if not isinstance(classification, dict):
                raise ValueError(
                    f"Entry {item_number} must contain a classification object."
                )

            entry_text = json.dumps(item, sort_keys=True, ensure_ascii=False)
            entry_id = hashlib.sha256(entry_text.encode("utf-8")).hexdigest()
            batch_occurrences[entry_id] = batch_occurrences.get(entry_id, 0) + 1
            previous_occurrences = memory["processed_entries"].get(entry_id, 0)

            if batch_occurrences[entry_id] <= previous_occurrences:
                continue

            add_classification(memory, classification, item_number)
            new_checkins += 1

        for entry_id, occurrences in batch_occurrences.items():
            memory["processed_entries"][entry_id] = max(
                memory["processed_entries"].get(entry_id, 0),
                occurrences,
            )

        if new_checkins or not MEMORY_FILE.exists():
            MEMORY_FILE.write_text(json.dumps(memory, ensure_ascii=False, indent=2),encoding="utf-8",)
        print(f"Counted {new_checkins} new check-ins from {CLASSIFICATIONS_FILE}.")

    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise SystemExit(f"Could not update memory: {error}") from error

    total = memory["total_checkins"]
    print(f"\nTotal check-ins: {total}")
    print(f"Dangerous check-ins: {memory['dangerous_checkins']}")
    print_frequencies("Emotions", memory["emotions"], total)
    print_frequencies("Tones", memory["tones"], total)
    print_frequencies("Danger levels", memory["danger_levels"], total)
    print_frequencies("Danger types", memory["danger_types"], total)
    print(f"\nSaved cumulative counts in {MEMORY_FILE}.")


if __name__ == "__main__":
    main()
