.PHONY: help supabase-start supabase-stop supabase-push backend frontend all seed install lint lint-backend lint-frontend kill-port-3000 kill-port-5000 iphone

# --- Auto-read Supabase credentials from backend/.env ---
SUPABASE_URL      := $(shell grep -E '^SUPABASE_URL='      backend/.env | cut -d= -f2-)
SUPABASE_ANON_KEY := $(shell grep -E '^SUPABASE_ANON_KEY=' backend/.env | cut -d= -f2-)
API_URL           := http://localhost:3000

FLUTTER_DEFINES := \
	--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
	--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) \
	--dart-define=API_URL=$(API_URL)

# --- Mobile / Local-network variables ---
FRONTEND_PORT       := 5000
IPHONE_PORT         := 8080
LOCAL_IP            := $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "localhost")
# Replace localhost/127.0.0.1 with the Mac's LAN IP so mobile devices can reach local Supabase
SUPABASE_URL_MOBILE := $(shell echo "$(SUPABASE_URL)" | sed 's|localhost|$(LOCAL_IP)|g; s|127\.0\.0\.1|$(LOCAL_IP)|g')

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
	@echo "  make iphone           - Run on local network + print QR code for iPhone/Safari"

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

kill-port-5000:
	@if lsof -ti:5000 > /dev/null 2>&1; then \
		echo "Killing existing process on port 5000..."; \
		lsof -ti:5000 | xargs kill -9 2>/dev/null || true; \
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
	npx --yes concurrently --kill-others --prefix-colors "cyan,magenta" --names "BE,FE" \
		"cd backend && npm run dev" \
		"cd frontend && flutter run -d chrome --web-port=5000 $(FLUTTER_DEFINES)"

# --- iPhone / Mobile Testing ---
# Serves the app on 0.0.0.0 so any device on the same WiFi can open it.
# Replaces localhost in URLs with the Mac's LAN IP automatically.
# Flutter logs appear in this terminal. For JS console logs on iPhone:
#   Safari > Develop > [your iPhone's name] > [page]
iphone: supabase-start kill-port-3000
	@echo ""
	@echo "📱 iPhone testing mode — local network"
	@echo "   Mac IP   : $(LOCAL_IP)"
	@echo "   Frontend : http://$(LOCAL_IP):$(IPHONE_PORT)"
	@echo "   Backend  : http://$(LOCAL_IP):3000"
	@echo "   Supabase : $(SUPABASE_URL_MOBILE)"
	@echo ""
	@echo "Scan this QR code with your iPhone camera:"
	@echo ""
	@npx --yes qrcode --small "http://$(LOCAL_IP):$(IPHONE_PORT)"
	@echo ""
	@echo "Starting backend + Flutter web server (both in this terminal)..."
	@echo ""
	npx --yes concurrently --kill-others --prefix-colors "cyan,magenta" --names "BE,FE" \
		"cd backend && npm run dev" \
		"cd frontend && flutter run -d web-server --web-hostname=0.0.0.0 --web-port=$(IPHONE_PORT) --dart-define=SUPABASE_URL=$(SUPABASE_URL_MOBILE) --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON_KEY) --dart-define=API_URL=http://$(LOCAL_IP):3000"

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
