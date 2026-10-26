import json
import sys
from pathlib import Path

cFILE = Path("classifications.json")


def load_classifications():
    if not cFILE.exists():
        return []

    try:
        classifications = json.loads(cFILE.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Could not read {cFILE}: {error}") from error

    if not isinstance(classifications, list):
        raise ValueError(f"{cFILE} must contain a JSON array.")
    for index, item in enumerate(classifications, start=1):
        if (
            not isinstance(item, dict)
            or not isinstance(item.get("classification"), dict)
            or item["classification"].get("danger_level")
            not in ("none", "concerning", "urgent")
        ):
            raise ValueError(
                f"Entry {index} has a missing or invalid danger_level."
            )
    return classifications


def show_support_prompt(entry_number, danger_level, input_fn=input, output_fn=print):
    output_fn(f"\n--- Safety check-in for entry {entry_number} ---")

    if danger_level == "none":
        output_fn(
            "No elevated danger level was flagged in this entry. "
            "This AI result can be wrong and is not a safety assessment."
        )
        return

    output_fn(
        f"This entry was flagged as {danger_level} by an AI classifier. "
        "The classifier can be wrong; this prototype does not monitor you "
        "or contact anyone."
    )
    if danger_level == "urgent":
        output_fn(
            "If you are in immediate danger, contact your local emergency "
            "number now. In the U.S., call 911 for immediate danger or call "
            "or text 988 for crisis support."
        )
        check_in = input_fn(
            "Are you in immediate danger right now? (y/N): "
        ) if input_fn is not None else None
    else:
        output_fn(
            "If you feel unsafe or need support, consider reaching out to "
            "someone you trust or a local crisis service."
        )
        check_in = input_fn(
            "Do you feel safe right now? (y/N): "
        ) if input_fn is not None else None

    if check_in is None:
        return

    if check_in.strip().casefold() in ("n", "no"):
        output_fn(
            "If you may be in immediate danger, contact your local emergency "
            "number now. In the U.S., call 911 for immediate danger or call "
            "or text 988 for crisis support."
        )
    elif danger_level == "urgent" and check_in.strip().casefold() in ("y", "yes"):
        output_fn(
            "Please contact your local emergency number now. In the U.S., "
            "call 911 for immediate danger."
        )

    answer = input_fn("Would you like to contact someone you trust now? (y/N): ")
    if answer.strip().casefold() in ("y", "yes"):
        output_fn(
            "Use your phone to call or message a trusted person. "
            "This prototype does not place calls or send messages."
        )
    else:
        output_fn(
            "You can choose to reach out later. If you may be in immediate "
            "danger, contact emergency help now."
        )


def main():
    try:
        classifications = load_classifications()
        input_fn = input if sys.stdin.isatty() else None
        for entry_number, item in enumerate(classifications, start=1):
            show_support_prompt(
                entry_number,
                item["classification"]["danger_level"],
                input_fn=input_fn,
            )
    except ValueError as error:
        raise SystemExit(f"Could not show support prompts: {error}") from error


if __name__ == "__main__":
    main()
