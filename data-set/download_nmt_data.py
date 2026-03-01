import json
import sys
import os
import ast

try:
    from datasets import load_dataset
except ImportError:
    print("pip install datasets required.")
    sys.exit(1)

# Maximum number of choices allowed per question.
# Questions with more than this are "matching" type questions,
# incompatible with a standard A/B/C/D quiz card UI.
MAX_CHOICES = 5


def build_consolidated_db():
    print("⏳ Downloading 'osyvokon/zno' for Language and History...")
    ds_osy = load_dataset("osyvokon/zno", split="train")

    print("⏳ Downloading 'NLPForUA/dumy-zno-ukrainian-math-history-geo-r1-o1' for Math and Geography...")
    ds_nlp = load_dataset("NLPForUA/dumy-zno-ukrainian-math-history-geo-r1-o1", split="train")

    all_normalized = []
    skipped_matching = 0

    print("⚙️  Processing osyvokon/zno...")
    for index, item in enumerate(ds_osy):
        choices = item.get('answers', [])
        if not choices:
            continue

        # Filter out matching/correspondence questions
        if len(choices) > MAX_CHOICES:
            skipped_matching += 1
            continue

        correct_answers = item.get('correct_answers', [])
        correct_index = None
        if correct_answers:
            correct_marker = correct_answers[0]
            for i, choice in enumerate(choices):
                if choice.get('marker') == correct_marker:
                    correct_index = i
                    break

        subject = item.get('subject', 'unknown')
        if subject == "ukrainian-language-and-literature":
            subject = "ukrainian_language"
        elif subject == "history-of-ukraine":
            subject = "history"

        all_normalized.append({
            "id": f"osy_{subject}_{index}",
            "subject": subject,
            "text": item.get('question', ''),
            "choices": [c.get('text', '') for c in choices],
            "correct_answer_index": correct_index,
            "exam_type": "ZNO_NMT_General"
        })

    print("⚙️  Processing NLPForUA dataset (Math + Geography)...")
    for index, item in enumerate(ds_nlp):
        # We only want math and geography — language/history already have rich data from osyvokon
        subject = item.get('subject', 'unknown')
        if subject not in ['math', 'geography']:
            continue

        # Skip questions that require images
        if item.get('with_photo'):
            continue

        # Parse answer options (stored as a Python literal string)
        raw_options = item.get('answer_options', '')
        if not raw_options:
            continue
        try:
            options_dict = ast.literal_eval(raw_options)
        except Exception:
            continue

        if not options_dict:
            continue

        # Resolve correct answer marker — can be a real list, a string, or a stringified list
        correct_marker = item.get('correct_answer')
        if isinstance(correct_marker, str) and correct_marker.startswith('[') and correct_marker.endswith(']'):
            try:
                parsed = ast.literal_eval(correct_marker)
                if isinstance(parsed, list) and parsed:
                    correct_marker = parsed[0]
            except Exception:
                pass
        if isinstance(correct_marker, list) and correct_marker:
            correct_marker = correct_marker[0]
        correct_marker = str(correct_marker).strip() if correct_marker else ""

        # Build choices list and find correct index
        choices = []
        correct_index = None

        if isinstance(options_dict, dict):
            for i, (marker, text) in enumerate(options_dict.items()):
                choices.append(str(text))
                if str(marker).strip() == correct_marker:
                    correct_index = i
        elif isinstance(options_dict, list):
            for i, val in enumerate(options_dict):
                if isinstance(val, dict) and 'answer' in val and 'text' in val:
                    choices.append(str(val['text']))
                    if str(val['answer']).strip() == correct_marker:
                        correct_index = i
                else:
                    choices.append(str(val))
                    markers = ["А", "Б", "В", "Г", "Д"]
                    if correct_marker in markers and markers.index(correct_marker) == i:
                        correct_index = i
                    elif correct_marker and correct_marker in str(val):
                        correct_index = i

        # Filter out matching/correspondence questions
        if len(choices) > MAX_CHOICES:
            skipped_matching += 1
            continue

        # Skip if we could not firmly identify the correct answer
        if correct_index is None:
            continue

        all_normalized.append({
            "id": f"nlp_{subject}_{index}",
            "subject": subject,
            "text": item.get('question', ''),
            "choices": choices,
            "correct_answer_index": correct_index,
            "exam_type": "ZNO_NMT_General"
        })

    print(f"\n💾 Consolidated Total: {len(all_normalized)} questions.")
    print(f"🚫 Skipped (matching/correspondence type): {skipped_matching}")

    # Ensure data directory exists
    os.makedirs('data', exist_ok=True)

    # Save master normalized file
    with open('data/nmt_database_normalized.json', 'w', encoding='utf-8') as f:
        json.dump(all_normalized, f, ensure_ascii=False, indent=2)
    print("✅ Saved data/nmt_database_normalized.json")

    # Save per-subject files
    subjects_data = {}
    for q in all_normalized:
        subjects_data.setdefault(q['subject'], []).append(q)

    for subject, questions in subjects_data.items():
        filename = f"data/nmt_database_{subject}.json"
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(questions, f, ensure_ascii=False, indent=2)
        print(f"✅ Saved {filename} ({len(questions)} questions)")


if __name__ == "__main__":
    build_consolidated_db()
