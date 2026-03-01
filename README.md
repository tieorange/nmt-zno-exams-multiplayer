# 🇺🇦 NMT Quiz Multiplayer 🎓🚀

![Promo Banner](docs/promo.png) <!-- Replace with an actual image link if you have one -->

Welcome to **NMT Quiz Multiplayer** — a real-time, competitive trivia game built specifically for Ukrainian high school students preparing for the National Multi-subject Test (НМТ). It's like **QuizUp**, but for NMT prep! 🤩

---

## ✨ Features

- **🎮 Real-time Multiplayer:** Play live with up to 4 friends!
- **🌐 4 Available Subjects:** 
  - 📖 Ukrainian Language and Literature
  - 🏰 History of Ukraine
  - 🌍 Geography
  - 📐 Mathematics (Demo)
- **⚡ Fast and Reliable:** Built with a thin Node.js Engine and Supabase Realtime for instant broadcasts.
- **🎨 Flutter Web Frontend:** Bouncy animations, vibrant colors, and fully playable in the browser. 
- **👻 Random Funny Avatars:** Nobody needs to sign up — you automatically become a «Веселий Кит» (Happy Whale) or «Смілива Лисиця» (Brave Fox) with a random color!

---

## 🛠️ Tech Stack

This project is built using modern, scalable, and cross-platform tools.

### 🔙 Backend (Node.js + Express + Supabase)
- **Node.js (TypeScript)** serves as the authoritative engine, handling game rooms, precise 5-minute round timers, and scoring.
- **Supabase PostgreSQL** stores all the `questions`, `rooms`, and `players`.
- **Supabase Realtime** broadcasts state changes (`game:start`, `question:new`, `round:reveal`) instantly.

### 📱 Frontend (Flutter Web)
- **Flutter** ensures a single cross-platform codebase.
- **Flutter Bloc (Cubit)** seamlessly manages application state across logic layers.
- **Go Router** handles browser-native back/forward navigation and shareable deep links (e.g., `/room/A9X`).
- **Shadcn Flutter & Flutter Animate** provide a beautiful dark-mode first design with satisfying micro-animations.

---

## 🚀 How to Run Locally

### 1️⃣ Setting up the Database (Supabase)
Create a free Supabase project. Head over to the SQL Editor and run the table creation statements found in `docs/plan.md`.

### 2️⃣ Backend Initialization
```bash
cd backend
cp .env.example .env
# Fill in your SUPABASE_URL and SUPABASE_SERVICE_KEY inside .env
npm install
npm run seed  # Loads 3,595 questions into Supabase
npm run dev   # Starts the Express Game Engine on port 3000
```

### 3️⃣ Frontend Initialization
```bash
cd frontend
flutter pub get
flutter run -d chrome \
  --dart-define=SUPABASE_URL=YOUR_SUPABASE_PROJECT_URL \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY \
  --dart-define=API_URL=http://localhost:3000
```

---

## 🏗️ Project Structure
- `data-set/` — Source of truth for questions (`all.json`) and core Typescript definitions.
- `backend/` — Express server doing all the heavy lifting for real-time validation and database updates.
- `frontend/` — Flutter Web application bringing the competitive quiz interface to life.
- `docs/` — Core architecture choices, step-by-step implementation guide, and logs (`plan.md`, `planClaude.md`, `planImplementation.md`).

---

## 🐛 Fixing Bugs / Contributing
Check `Makefile` for handy dev scripts! Use `make check` to verify both the backend and frontend are healthy.

Happy Studying & Have Fun! 🎉🇺🇦
