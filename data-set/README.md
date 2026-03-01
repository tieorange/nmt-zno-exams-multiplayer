# 📚 NMT Quiz Dataset

Production-ready question database for the **NMT/ZNO Multiplayer Quiz App** (Ukrainian exam prep).  
All questions are multiple-choice, validated, and safe to load directly into a backend or MongoDB seed.

---

## 📁 Folder Structure

```
data-set/
├── README.md               ← You are here
├── schema.json             ← JSON Schema for a single question object
├── types.ts                ← TypeScript types for the backend (copy into your Node.js project)
├── download_nmt_data.py    ← Script to re-download & regenerate all datasets from HuggingFace
└── questions/
    ├── all.json            ← Master file: all 3,595 questions combined
    ├── ukrainian_language.json   ← 1,923 questions
    ├── history.json              ← 1,138 questions
    ├── geography.json            ←   476 questions
    └── math.json                 ←    58 questions (demo pool, limited)
```

---

## 🧩 Question Schema

Each question is a JSON object with the following fields:

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Unique ID. Prefix `osy_` = language/history source. Prefix `nlp_` = math/geo source. |
| `subject` | `string` | One of: `ukrainian_language`, `history`, `geography`, `math` |
| `text` | `string` | Question text in Ukrainian. May contain plain-text math (e.g. `x^2`, `log_2(x)`). |
| `choices` | `string[]` | 2–5 answer options. Index 0=А, 1=Б, 2=В, 3=Г, 4=Д. |
| `correct_answer_index` | `number` | Zero-based index of the correct answer in `choices`. |
| `exam_type` | `string` | Always `"ZNO_NMT_General"` (year metadata unavailable in source datasets). |

### Example Question

```json
{
  "id": "osy_history_42",
  "subject": "history",
  "text": "Коли була проголошена незалежність України?",
  "choices": [
    "24 серпня 1991 року",
    "1 грудня 1991 року",
    "16 липня 1990 року",
    "22 січня 1918 року"
  ],
  "correct_answer_index": 0,
  "exam_type": "ZNO_NMT_General"
}
```

---

## ⚠️ Security Rule

> **Never send `correct_answer_index` to the client during an active game round.**
>
> Strip it server-side when broadcasting a question. Only reveal it via a dedicated
> Socket.io event (e.g. `round:reveal`) **after** the round timer expires.

See `types.ts` for the `ClientQuestion` type (with `correct_answer_index` omitted).

---

## 📊 Subject Summary

| Subject | File | Questions | Game-ready |
|---|---|---|---|
| Ukrainian Language & Literature | `ukrainian_language.json` | 1,923 | ✅ |
| History of Ukraine | `history.json` | 1,138 | ✅ |
| Geography | `geography.json` | 476 | ✅ |
| Mathematics | `math.json` | 58 | ⚠️ Demo only |

---

## 🗄️ Loading into MongoDB (Node.js seed script)

```typescript
import { MongoClient } from 'mongodb';
import fs from 'fs';

const questions = JSON.parse(fs.readFileSync('./data-set/questions/all.json', 'utf-8'));

const client = new MongoClient(process.env.MONGO_URI!);
await client.connect();
const db = client.db('nmt_quiz');
await db.collection('questions').insertMany(questions);
console.log(`Seeded ${questions.length} questions`);
await client.close();
```

**Recommended MongoDB index** (for fast subject-based random sampling):
```javascript
db.collection('questions').createIndex({ subject: 1 });
```

**Random 10-question query for a game room:**
```javascript
db.collection('questions').aggregate([
  { $match: { subject: 'history' } },
  { $sample: { size: 10 } },
  { $project: { correct_answer_index: 0 } } // strip from client payload
]);
```

---

## 🔄 Regenerating the Dataset

Run the download script to pull fresh data from HuggingFace and overwrite the `questions/` folder:

```bash
cd <project-root>
pip install datasets
python3 data-set/download_nmt_data.py
```

**Sources:**
- `osyvokon/zno` → Ukrainian Language & History questions
- `NLPForUA/dumy-zno-ukrainian-math-history-geo-r1-o1` → Math & Geography questions

**Filtering applied automatically:**
- Questions with more than 5 choices (matching/correspondence type) are excluded
- Questions requiring images (`with_photo: true`) are excluded
- Questions with unresolvable correct answers are excluded

---

## 🗂️ Backend Integration Checklist

- [ ] Copy `types.ts` into your Node.js project (`src/types/question.ts`)
- [ ] Run the MongoDB seed script above
- [ ] Create index on `{ subject: 1 }`
- [ ] Use `$sample` aggregation to draw 10 random questions per game room
- [ ] Always project out `correct_answer_index` from client-bound payloads
- [ ] Emit `correct_answer_index` only via `round:reveal` Socket.io event after timer ends
