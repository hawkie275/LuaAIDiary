#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/hawkie275/luaaidiary"
SAFE_DEFAULT_DEPLOY_PATH="${HOME}/LuaAIDiary"
SAFE_DEFAULT_LOCAL_DNS="1.1.1.1,8.8.8.8"

log() {
  echo "[deploy] $*"
}

fail() {
  echo "[deploy][error] $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "required command not found: $cmd"
  fi
}

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  fail "version argument is required (usage: ./deploy.sh vX.Y.Z)"
fi

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "invalid version format: '$VERSION' (expected: vX.Y.Z)"
fi

# DEPLOY_PATH は「安全なデフォルト」を明示して採用
DEPLOY_PATH="${DEPLOY_PATH:-$SAFE_DEFAULT_DEPLOY_PATH}"
if [ ! -d "$DEPLOY_PATH" ]; then
  fail "deploy path does not exist: $DEPLOY_PATH"
fi

OVERRIDE_FILE="${DEPLOY_PATH}/docker-compose.override.yml"
LOCAL_DNS_RAW="${LOCAL_DNS:-$SAFE_DEFAULT_LOCAL_DNS}"

log "Checking required commands..."
require_cmd docker
require_cmd sed
if ! docker compose version >/dev/null 2>&1; then
  fail "required command not available: docker compose"
fi

if [ -z "$LOCAL_DNS_RAW" ]; then
  fail "LOCAL_DNS is empty"
fi

write_override_file() {
  local app_version="$1"

  {
    echo "services:"
    echo "  web:"
    echo "    image: ${IMAGE}:${VERSION}"
    if [ -n "$app_version" ]; then
      echo "    environment:"
      echo "      - APP_VERSION=${app_version}"
    fi
    echo "    dns:"

    IFS=',' read -r -a dns_items <<< "$LOCAL_DNS_RAW"
    usable_count=0
    for dns in "${dns_items[@]}"; do
      dns_trimmed="$(echo "$dns" | xargs)"
      if [ -n "$dns_trimmed" ]; then
        echo "      - ${dns_trimmed}"
        usable_count=$((usable_count + 1))
      fi
    done

    if [ "$usable_count" -eq 0 ]; then
      fail "LOCAL_DNS did not contain any usable DNS entries"
    fi
  } > "$OVERRIDE_FILE"
}

log "Writing override file (initial): ${OVERRIDE_FILE}"
write_override_file ""

log "Pulling and restarting web service..."
cd "$DEPLOY_PATH"
if ! docker compose pull web; then
  fail "docker compose pull web failed"
fi

IMAGE_REF="${IMAGE}:${VERSION}"
APP_VERSION="$(docker image inspect "$IMAGE_REF" --format '{{index .RepoTags 0}}' 2>/dev/null | sed -E 's|^.+:v?([0-9]+\.[0-9]+\.[0-9]+)$|\1|')"
if [ -z "$APP_VERSION" ]; then
  fail "failed to derive APP_VERSION from image inspect: ${IMAGE_REF}"
fi

log "Derived APP_VERSION from image inspect: ${APP_VERSION}"
log "Rewriting override file with APP_VERSION"
write_override_file "$APP_VERSION"

if ! grep -q "APP_VERSION=${APP_VERSION}" "$OVERRIDE_FILE"; then
  fail "override file verification failed: APP_VERSION not found in ${OVERRIDE_FILE}"
fi

if ! docker compose up -d web; then
  fail "docker compose up -d web failed"
fi

CONTAINER_APP_VERSION="$(docker compose exec -T web sh -lc 'printf %s "$APP_VERSION"' 2>/dev/null || true)"
if [ -z "$CONTAINER_APP_VERSION" ]; then
  fail "runtime verification failed: APP_VERSION is empty in web container"
fi

if [ "$CONTAINER_APP_VERSION" != "$APP_VERSION" ]; then
  fail "runtime verification failed: APP_VERSION mismatch (expected=${APP_VERSION}, actual=${CONTAINER_APP_VERSION})"
fi

log "Deployment completed: ${IMAGE}:${VERSION}"
