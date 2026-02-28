import json
import sys

# Check for the required library before starting
try:
    from datasets import load_dataset
except ImportError:
    print("❌ Error: The 'datasets' library is not installed.")
    print("Please run the following command in your terminal: pip install datasets")
    sys.exit(1)

def download_and_format_zno():
    print("⏳ Downloading the general ZNO/NMT database from Hugging Face (osyvokon/zno)...")
    
    try:
        # Load the public osyvokon/zno dataset
        dataset = load_dataset("osyvokon/zno")
    except Exception as e:
        print(f"❌ Error during dataset download: {e}")
        return

    all_questions = []
    
    print("⚙️ Processing questions... Since year metadata is unavailable, downloading all questions.")
    print("💡 ZNO questions are fully relevant for NMT preparation.")

    # Determine the split (usually 'train')
    split_name = 'train' if 'train' in dataset else list(dataset.keys())[0]

    # Iterate through the dataset and map fields
    for index, item in enumerate(dataset[split_name]):
        subject = item.get('subject', 'unknown')
        text = item.get('question', '')
        choices = item.get('answers', [])
        correct_answers = item.get('correct_answers', [])
        
        # Filter out questions that don't have any choices
        if not choices:
            continue

        # Calculate the 0-based index of the correct answer to make it easier to use in frontend apps
        correct_answer_index = None
        if correct_answers and len(correct_answers) > 0:
            correct_marker = correct_answers[0]
            for i, choice in enumerate(choices):
                if choice.get('marker') == correct_marker:
                    correct_answer_index = i
                    break
        
        # Generate a unique ID based on subject and index
        unique_id = f"nmt_prep_{subject}_{index}"
        
        question = {
            "id": unique_id,
            "subject": subject,
            "text": text,
            "choices": choices,
            "correct_answers": correct_answers,
            "correct_answer_index": correct_answer_index,
            "exam_type": "ZNO_NMT_General" # Indicating general type as year is unknown
        }
        all_questions.append(question)

    output_filename = 'nmt_database.json'
    
    print(f"💾 Found {len(all_questions)} questions. Saving to {output_filename}...")
    
    # Save the data in JSON format
    try:
        with open(output_filename, 'w', encoding='utf-8') as f:
            json.dump(all_questions, f, ensure_ascii=False, indent=2)
        print(f"✅ Done! Database successfully saved to: {output_filename}")
        print("You can now use this data for your web application.")
    except Exception as e:
        print(f"❌ Error during file saving: {e}")

if __name__ == "__main__":
    download_and_format_zno()
