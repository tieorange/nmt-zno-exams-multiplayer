.PHONY: check check-be check-fe check-be-types check-fe-analyze seed-db help

# ─────────────────────────────────────────────────────────────────────────────
# Primary target: run all checks. Use this as the agent self-heal loop.
# Usage: make check
# ─────────────────────────────────────────────────────────────────────────────
check: check-be
	@echo ""
	@echo "✅ All checks passed — safe to advance to next phase."

# ─────────────────────────────────────────────────────────────────────────────
# Backend checks
# ─────────────────────────────────────────────────────────────────────────────
check-be: check-be-types
	@echo "✅ Backend OK"

check-be-types:
	@echo "--- Backend: TypeScript type check (tsc --noEmit) ---"
	cd backend && npx tsc --noEmit
	@echo "✅ Backend types OK"

# ─────────────────────────────────────────────────────────────────────────────
# Frontend checks (add when frontend is implemented)
# ─────────────────────────────────────────────────────────────────────────────
check-fe: check-fe-analyze
	@echo "✅ Frontend OK"

check-fe-analyze:
	@echo "--- Frontend: Flutter analyze ---"
	cd frontend && flutter analyze --no-fatal-infos
	@echo "✅ Flutter analyze OK"

# ─────────────────────────────────────────────────────────────────────────────
# Build checks (slower — run before deploy)
# ─────────────────────────────────────────────────────────────────────────────
build-be:
	@echo "--- Backend: tsc build ---"
	cd backend && npm run build
	@echo "✅ Backend build OK"

build-fe:
	@echo "--- Frontend: flutter build web (debug) ---"
	cd frontend && flutter build web --debug
	@echo "✅ Frontend build OK"

build: build-be
	@echo "✅ Backend build OK (add build-fe when frontend is ready)"

# ─────────────────────────────────────────────────────────────────────────────
# Dev helpers
# ─────────────────────────────────────────────────────────────────────────────
seed-db:
	@echo "--- Seeding Supabase with 3,595 questions ---"
	cd backend && npm run seed

# Quick smoke test: are the REST endpoints responding?
smoke-test:
	@echo "--- Smoke test: backend REST endpoints ---"
	curl -sf http://localhost:3000/api/subjects | python3 -m json.tool
	@echo "✅ /api/subjects OK"
	curl -sf -X POST http://localhost:3000/api/rooms \
	  -H 'Content-Type: application/json' \
	  -d '{"subject":"history","maxPlayers":2}' | python3 -m json.tool
	@echo "✅ POST /api/rooms OK"

help:
	@echo "Available targets:"
	@echo "  make check          — run backend type check"
	@echo "  make check-be       — TypeScript tsc --noEmit only"
	@echo "  make check-fe       — Flutter analyze only (requires frontend/)"
	@echo "  make build          — full tsc build"
	@echo "  make seed-db        — seed Supabase from data-set/questions/all.json"
	@echo "  make smoke-test     — curl BE endpoints (server must be running)"
