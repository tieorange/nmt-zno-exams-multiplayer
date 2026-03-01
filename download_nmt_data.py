import json
import sys
import os

try:
    from datasets import load_dataset
except ImportError:
    print("pip install datasets required.")
    sys.exit(1)

def build_consolidated_db():
    print("⏳ Downloading 'osyvokon/zno' for Language and History...")
    ds_osy = load_dataset("osyvokon/zno", split="train")
    
    print("⏳ Downloading 'NLPForUA/dumy-zno-ukrainian-math-history-geo-r1-o1' for Math and Geography...")
    ds_nlp = load_dataset("NLPForUA/dumy-zno-ukrainian-math-history-geo-r1-o1", split="train")

    all_normalized = []
    
    print("⚙️ Processing osyvokon/zno...")
    for index, item in enumerate(ds_osy):
        choices = item.get('answers', [])
        if not choices: continue
        
        correct_answers = item.get('correct_answers', [])
        correct_index = None
        if correct_answers and len(correct_answers) > 0:
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

    print("⚙️ Processing NLPForUA dataset...")
    for index, item in enumerate(ds_nlp):
        # We only want math and geography, since we already have rich history/language from osyvokon
        subject = item.get('subject', 'unknown')
        if subject not in ['math', 'geography']:
            continue
            
        # Parse choices
        raw_options = item.get('answer_options', '{}')
        if not raw_options: continue
        import ast
        try:
            options_dict = ast.literal_eval(raw_options)
        except Exception as e:
            continue
            
        choices = []
        correct_index = None
        
        correct_marker = item.get('correct_answer')
        
        # correct_answer can sometimes be a string that looks like a list "['Б']"
        # or it can be a real list. We need to handle both.
        if isinstance(correct_marker, str) and correct_marker.startswith('[') and correct_marker.endswith(']'):
            try:
                import ast
                parsed_list = ast.literal_eval(correct_marker)
                if isinstance(parsed_list, list) and len(parsed_list) > 0:
                    correct_marker = parsed_list[0]
            except Exception:
                pass
                
        if isinstance(correct_marker, list) and len(correct_marker) > 0:
            correct_marker = correct_marker[0]
            
        correct_marker = str(correct_marker).strip() if correct_marker else ""
        
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
                    
        # Skip if correct answer isn't firmly identified
        if correct_index is None:
            if subject == 'math' and len(choices) > 0:
                print(f"Skipped because correct_index is None. options_dict: {options_dict}, correct_marker: {correct_marker}")
            continue
            
        # Ensure no images are required
        if item.get('with_photo') == True:
            if subject == 'math':
                print("Skipped because with_photo is True")
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
    
    # Ensure data directory exists
    os.makedirs('data', exist_ok=True)
    
    # Save the huge normalized master file
    with open('data/nmt_database_normalized.json', 'w', encoding='utf-8') as f:
        json.dump(all_normalized, f, ensure_ascii=False, indent=2)
    print("✅ Saved data/nmt_database_normalized.json")

    # Split by subject
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
