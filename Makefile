.PHONY: help supabase-start supabase-stop supabase-push backend frontend all seed install lint lint-backend lint-frontend kill-port-3000

# --- Auto-read Supabase credentials from backend/.env ---
SUPABASE_URL      := $(shell grep -E '^SUPABASE_URL='      backend/.env | cut -d= -f2-)
SUPABASE_ANON_KEY := $(shell grep -E '^SUPABASE_ANON_KEY=' backend/.env | cut -d= -f2-)
API_URL           := http://localhost:3000

FLUTTER_DEFINES := \
	--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
	--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
	--dart-define=API_URL=$(API_URL)

help:
	@echo "🎮 NMT Quiz Multiplayer — Make Commands"
	@echo ""
	@echo "Toolchain requirements:"
	@echo "  Flutter/Dart : >=3.9.2  (run: flutter --version)"
	@echo "  Node.js      : >=20     (run: node --version)"
	@echo "  Docker       : required for local Supabase"
	@echo ""
	@echo "Available commands:"
	@echo "  make supabase-start   - Start local Supabase Docker containers"
	@echo "  make supabase-stop    - Stop local Supabase"
	@echo "  make supabase-push    - Push database migrations"
	@echo "  make backend          - Run Node.js backend (dev mode, port 3000)"
	@echo "  make frontend         - Run Flutter Web frontend (pinned port 5000)"
	@echo "  make all              - Run Supabase, Backend, and Frontend together"
	@echo "  make seed             - Seed the local database with questions"
	@echo "  make lint             - Run linter for both Backend and Frontend"
	@echo "  make install          - Install npm and flutter packages"

# --- Supabase Commands ---
supabase-start:
	@echo "Starting local Supabase..."
	npx supabase start

supabase-stop:
	@echo "Stopping local Supabase..."
	npx supabase stop

supabase-push:
	@echo "Pushing database migrations..."
	npx supabase db push

# --- Helper Functions ---
# Kill any process using port 3000 to avoid EADDRINUSE
kill-port-3000:
	@if lsof -ti:3000 > /dev/null 2>&1; then \
		echo "Killing existing process on port 3000..."; \
		lsof -ti:3000 | xargs kill -9 2>/dev/null || true; \
	fi

# --- Application Services ---
backend: supabase-start kill-port-3000
	@echo "Starting backend server..."
	cd backend && npm run dev

frontend:
	@echo "Starting frontend web app..."
	@echo "  → SUPABASE_URL=$(SUPABASE_URL)"
	@echo "  → API_URL=$(API_URL)"
	cd frontend && flutter run -d chrome --web-port=5000 $(FLUTTER_DEFINES)

# --- Combined & Helper Commands ---
all: supabase-start kill-port-3000
	@echo "Starting everything! 🚀"
	@echo "Starting Backend and Frontend in parallel..."
	@# Run backend in the background, run frontend in the foreground
	@(cd backend && npm run dev &) && (cd frontend && flutter run -d chrome --web-port=5000 $(FLUTTER_DEFINES))

seed:
	@echo "Seeding local database..."
	cd backend && npm run seed

install:
	@echo "Installing Backend dependencies..."
	cd backend && npm install
	@echo "Getting Frontend dependencies..."
	cd frontend && flutter pub get

lint-backend:
	@echo "Linting backend..."
	cd backend && npm run typecheck

lint-frontend:
	@echo "Linting frontend..."
	cd frontend && flutter analyze

lint: lint-backend lint-frontend
	@echo "✅ Linting complete!"
