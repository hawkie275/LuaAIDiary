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
unset INFRA_WRITERS_FENCED
export DEPLOY_PATH=$tmp/deploy DEPLOY_WEB_IMAGE=fixture:tag
(cd "$tmp/repo" && bash "$ROOT/scripts/deploy-release.sh")
[[ $(cat "$tmp/deploy/state/observed-commit") == "$expected" ]]
[[ $(cat "$tmp/deploy/current/docker-compose.yml") == 'matching compose' ]]
cmp "$tmp/expected-env" "$tmp/deploy/.env"
cmp "$tmp/expected-override" "$tmp/deploy/docker-compose.override.yml"
# A stale legacy setting must also remain harmless.
(cd "$tmp/repo" && INFRA_WRITERS_FENCED=0 bash "$ROOT/scripts/deploy-release.sh")
previous=$(readlink "$tmp/deploy/current")
if (cd "$tmp/repo" && FAIL_DEPLOY=1 bash "$ROOT/scripts/deploy-release.sh"); then
    echo 'failed update was not propagated' >&2; exit 1
fi
[[ $(readlink "$tmp/deploy/current") == "$previous" ]]
cmp "$tmp/expected-env" "$tmp/deploy/.env"
cmp "$tmp/expected-override" "$tmp/deploy/docker-compose.override.yml"
echo 'PASS deploy staging: matching commit, external state, preserved environment/override, failure propagation and unchanged publication pointer'
