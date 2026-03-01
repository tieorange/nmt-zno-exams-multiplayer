# 🤖 AI Agent Instructions (AGENTS.md)

Welcome, Agent! This file provides the technical context and instructions for working on the **NMT Quiz Multiplayer** project. This project is a real-time competitive trivia game for Ukrainian high school students preparing for the NMT (НМТ) exam.

## 🏗️ Project Overview
- **Tech Stack**: Node.js (Express, TypeScript) Backend, Flutter Web Frontend, Supabase (Postgres + Realtime).
- **Core Goal**: Social, educational, and fun multiplayer quiz experience.
- **Language Policy**: 
  - **UI (Labels, Buttons, Messages)**: 🇺🇦 Ukrainian
  - **Code (Variables, Functions, Comments, Logs)**: 🇬🇧 English

## 📂 Repository Structure
- `/backend`: Node.js Express server. Authoritative game engine.
- `/frontend`: Flutter Web application.
- `/data-set`: **[READ-ONLY]** Source of truth for questions and shared types. **Never modify files here.**
- `/docs`: Architecture plans and implementation guides.

## 🛠️ Commands (via Makefile)
| Command | Description |
|---|---|
| `make supabase-start` | Starts local Supabase Docker containers. |
| `make supabase-stop` | Stops local Supabase. |
| `make backend` | Runs the Node.js backend in development mode (port 3000). |
| `make frontend` | Runs the Flutter Web app (port 5000+). |
| `make seed` | Seeds the database with question data from `/data-set`. |
| `make install` | Installs dependencies for both backend and frontend. |
| `make lint` | Runs linters for the entire project. |

## 🔌 MCP Server Support
This project is configured with two primary MCP servers to assist development:

### 1. `local-db` (Local Postgres)
- **Purpose**: Directly query and manage the local Supabase Docker database.
- **Connection**: `postgresql://postgres:postgres@localhost:54322/postgres`
- **Use for**: Schema inspection, data verification, and local debugging.

### 2. `supabase` (Cloud)
- **Purpose**: Manage the remote Supabase project (migrations, project settings).
- **Requires**: `SUPABASE_ACCESS_TOKEN` environment variable.
- **Use for**: Syncing local changes to cloud, managing remote RLS policies.

## 📜 Development Guidelines
1. **Security**: Never broadcast `correct_answer_index` to clients. This field must be stripped by the backend before sending questions.
2. **Game Logic**: Round timers (5 min) and scoring are server-authoritative.
3. **Logging**: 
   - Backend: Use `pino` for structured English logs.
   - Frontend: Use `logger` package with feature-specific tags.
4. **State Management**:
   - Backend: In-memory `roundState` for active games.
   - Frontend: `flutter_bloc` (Cubits).
5. **Real-time**: 
   - Client -> Server: REST (HTTP POST)
   - Server -> Client: Supabase Realtime (Broadcast)

## 🤖 Specific Agent Instructions
- **Vibe-coding**: Prioritize bouncy animations and a premium dark-mode aesthetic for the frontend.
- **Error Handling**: Use `fpdart` (`Either<Failure, T>`) for functional error handling in Flutter.
- **Logs**: Always provide structured logs when reporting state changes.

Happy coding, colleague! 🚀
