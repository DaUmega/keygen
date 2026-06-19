#!/bin/bash
set -euo pipefail

cd /app

# ---------------------------------------------------------------------------
# Generate web/js/settings.js (gitignored upstream, required for the web UI)
# from the example template, pointing it at wherever the API is actually
# reachable from the browser. Override with -e KEYGEN_ENDPOINT=... on `docker
# run` if you publish the API on a different host/port than the default.
# ---------------------------------------------------------------------------
KEYGEN_ENDPOINT="${KEYGEN_ENDPOINT:-http://localhost:8080}"
sed "s#http://localhost:8080#${KEYGEN_ENDPOINT}#" web/js/settings.js.example > web/js/settings.js
echo "[entrypoint] generated web/js/settings.js -> keygen_endpoint = \"${KEYGEN_ENDPOINT}\""

# ---------------------------------------------------------------------------
# Build the key catalog if it's missing (already built at image-build time;
# this re-runs it when /app is bind-mounted over with a fresh checkout).
# ---------------------------------------------------------------------------
if [ ! -f build/keys.json ]; then
  echo "[entrypoint] build/keys.json missing, building it now..."
  make build/keys.json
fi

exec "$@"
