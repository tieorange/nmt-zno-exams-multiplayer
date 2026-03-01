.PHONY: help supabase-start supabase-stop backend frontend all seed install lint lint-backend lint-frontend

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
	@echo "Available commands:"
	@echo "  make supabase-start   - Start local Supabase Docker containers"
	@echo "  make supabase-stop    - Stop local Supabase"
	@echo "  make backend          - Run Node.js backend (dev mode)"
	@echo "  make frontend         - Run Flutter Web frontend (auto-injects Supabase env)"
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

# --- Application Services ---
backend: supabase-start
	@echo "Starting backend server..."
	cd backend && npm run dev

frontend:
	@echo "Starting frontend web app..."
	@echo "  → SUPABASE_URL=$(SUPABASE_URL)"
	@echo "  → API_URL=$(API_URL)"
	cd frontend && flutter run -d chrome $(FLUTTER_DEFINES)

# --- Combined & Helper Commands ---
all: supabase-start
	@echo "Starting everything! 🚀"
	@echo "Starting Backend and Frontend in parallel..."
	@# Run backend in the background, run frontend in the foreground
	@(cd backend && npm run dev &) && (cd frontend && flutter run -d chrome $(FLUTTER_DEFINES))

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
