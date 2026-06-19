#!/usr/bin/env bash
# manage.sh — build & run the keygen Docker container (no docker-compose)
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-keygen:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-keygen}"

# Host ports the two in-container services are published on.
WEB_HOST_PORT="${WEB_HOST_PORT:-8000}"
API_HOST_PORT="${API_HOST_PORT:-8080}"

# URL the *browser* will use to reach the API — baked into web/js/settings.js
# at container start. Override if running on a remote host or behind a proxy
# (e.g. KEYGEN_ENDPOINT=https://keys.example.com/api ./manage.sh start).
KEYGEN_ENDPOINT="${KEYGEN_ENDPOINT:-http://localhost:${API_HOST_PORT}}"

# Origin(s) the API will allow via Access-Control-Allow-Origin. Default "*"
# is fine for local/LAN use; tighten it (e.g. to the web UI's real URL) for
# anything more exposed.
CORS_ALLOW_ORIGIN="${CORS_ALLOW_ORIGIN:-*}"

usage() {
  cat <<EOF
Usage: ./manage.sh <command>

Commands:
  build           Build the Docker image ($IMAGE_NAME)
  start           Run the container (web UI: http://localhost:${WEB_HOST_PORT})
  stop            Stop and remove the running container
  restart         stop + start
  logs [api|web]  Tail logs (default: all container output)
  status          Show container status + supervisord process status
  shell           Open a shell inside the running container
  rebuild-keys    Re-run 'make build/keys.json' inside the running container
  clean           Stop the container and remove the built image
  help            Show this message

Environment overrides:
  IMAGE_NAME, CONTAINER_NAME, WEB_HOST_PORT, API_HOST_PORT, KEYGEN_ENDPOINT,
  CORS_ALLOW_ORIGIN
EOF
}

require_docker() {
  command -v docker >/dev/null 2>&1 || { echo "docker is not installed or not on PATH" >&2; exit 1; }
}

is_running() {
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
}

exists() {
  docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
}

cmd_build() {
  require_docker
  docker build -t "$IMAGE_NAME" .
}

cmd_start() {
  require_docker
  if exists; then
    echo "Container '$CONTAINER_NAME' already exists. Run './manage.sh stop' first, or './manage.sh restart'." >&2
    exit 1
  fi
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${WEB_HOST_PORT}:8000" \
    -p "${API_HOST_PORT}:8080" \
    -e "KEYGEN_ENDPOINT=${KEYGEN_ENDPOINT}" \
    -e "CORS_ALLOW_ORIGIN=${CORS_ALLOW_ORIGIN}" \
    --restart unless-stopped \
    "$IMAGE_NAME" >/dev/null
  echo "keygen started."
  echo "  Web UI : http://localhost:${WEB_HOST_PORT}"
  echo "  API    : ${KEYGEN_ENDPOINT}"
}

cmd_stop() {
  require_docker
  if exists; then
    docker rm -f "$CONTAINER_NAME" >/dev/null
    echo "Stopped and removed '$CONTAINER_NAME'."
  else
    echo "No container named '$CONTAINER_NAME'."
  fi
}

cmd_restart() {
  cmd_stop
  cmd_start
}

cmd_logs() {
  require_docker
  case "${1:-}" in
    api) docker exec "$CONTAINER_NAME" supervisorctl tail -f keygen-api ;;
    web) docker exec "$CONTAINER_NAME" supervisorctl tail -f keygen-web ;;
    *)   docker logs -f "$CONTAINER_NAME" ;;
  esac
}

cmd_status() {
  require_docker
  docker ps -a --filter "name=^${CONTAINER_NAME}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  if is_running; then
    echo
    docker exec "$CONTAINER_NAME" supervisorctl status
  fi
}

cmd_shell() {
  require_docker
  docker exec -it "$CONTAINER_NAME" bash
}

cmd_rebuild_keys() {
  require_docker
  docker exec "$CONTAINER_NAME" make build/keys.json
  docker exec "$CONTAINER_NAME" supervisorctl restart keygen-api
}

cmd_clean() {
  cmd_stop
  require_docker
  docker rmi "$IMAGE_NAME" >/dev/null 2>&1 || true
}

case "${1:-help}" in
  build)        cmd_build ;;
  start)        cmd_start ;;
  stop)         cmd_stop ;;
  restart)      cmd_restart ;;
  logs)         shift; cmd_logs "${1:-}" ;;
  status)       cmd_status ;;
  shell)        cmd_shell ;;
  rebuild-keys) cmd_rebuild_keys ;;
  clean)        cmd_clean ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: ${1:-}" >&2; usage; exit 1 ;;
esac
