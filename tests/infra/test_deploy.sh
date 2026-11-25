#!/usr/bin/env bash
# Test release staging using an isolated Git repository and a stub update entry.
# No Docker resources are created or changed by this test.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/scripts" "$tmp/repo/docker/web" "$tmp/repo/postgresql/init" "$tmp/deploy"
printf 'operator environment\n' > "$tmp/deploy/.env"
printf 'operator override\n' > "$tmp/deploy/docker-compose.override.yml"
cp "$tmp/deploy/.env" "$tmp/expected-env"
cp "$tmp/deploy/docker-compose.override.yml" "$tmp/expected-override"
echo 'matching compose' > "$tmp/repo/docker-compose.yml"
echo 'matching migration runner' > "$tmp/repo/docker/web/run-migrations.sh"
echo 'matching init SQL' > "$tmp/repo/postgresql/init/01.sql"
echo 'must not be deployed' > "$tmp/repo/.env"
cat > "$tmp/repo/scripts/infra-update.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
[[ $1 == update ]]
[[ $(cat "$INFRA_ROOT/docker-compose.yml") == 'matching compose' ]]
[[ $(cat "$INFRA_ROOT/postgresql/init/01.sql") == 'matching init SQL' ]]
[[ ! -f $INFRA_ROOT/.env ]]
[[ $(cat "$INFRA_ENV_FILE") == 'operator environment' ]]
[[ $(cat "$INFRA_OVERRIDE") == 'operator override' ]]
mkdir -p "$INFRA_STATE_DIR"
printf '%s\n' "$DEPLOY_COMMIT" > "$INFRA_STATE_DIR/observed-commit"
[[ ${FAIL_DEPLOY:-0} != 1 ]]
EOF
git -C "$tmp/repo" init -q
git -C "$tmp/repo" add .
git -C "$tmp/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture
expected=$(git -C "$tmp/repo" rev-parse HEAD)
git -C "$tmp/repo" tag fixture-release
# The workflow checkout has a newer updater, but application materials stay tagged.
echo 'wrong HEAD compose' > "$tmp/repo/docker-compose.yml"
echo 'echo current-updater > "$INFRA_STATE_DIR/updater"' >> "$tmp/repo/scripts/infra-update.sh"
git -C "$tmp/repo" add .
git -C "$tmp/repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm updater
unset INFRA_WRITERS_FENCED
export DEPLOY_PATH=$tmp/deploy DEPLOY_WEB_IMAGE=fixture:tag COMPOSE_PROJECT_NAME=fixture
export DEPLOY_RELEASE_REF=refs/tags/fixture-release
(cd "$tmp/repo" && bash "$ROOT/scripts/deploy-release.sh")
[[ $(cat "$tmp/deploy/state/observed-commit") == "$expected" ]]
[[ $(cat "$tmp/deploy/state/updater") == current-updater ]]
[[ $(cat "$tmp/deploy/current/docker-compose.yml") == 'matching compose' ]]
cmp "$tmp/expected-env" "$tmp/deploy/.env"
cmp "$tmp/expected-override" "$tmp/deploy/docker-compose.override.yml"
previous=$(readlink "$tmp/deploy/current")
if (cd "$tmp/repo" && FAIL_DEPLOY=1 bash "$ROOT/scripts/deploy-release.sh"); then
    echo 'failed update was not propagated' >&2; exit 1
fi
[[ $(readlink "$tmp/deploy/current") == "$previous" ]]
cmp "$tmp/expected-env" "$tmp/deploy/.env"
cmp "$tmp/expected-override" "$tmp/deploy/docker-compose.override.yml"
echo 'PASS deploy staging: matching commit, external state, preserved environment/override, failure propagation and unchanged publication pointer'
