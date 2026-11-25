#!/usr/bin/env bash
# Destructive ONLY to assets created by this test's random project prefix.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d /tmp/luaaidiary-infra-test.XXXXXX)
COMPOSE_PROJECT_NAME=infra-test-$(date +%s)-$RANDOM
export COMPOSE_PROJECT_NAME
export INFRA_ROOT=$WORK/release INFRA_STATE_DIR=$WORK/state INFRA_ENV_FILE=$WORK/env
export INFRA_OVERRIDE=$WORK/override.yml DEPLOY_WEB_IMAGE=nginx:alpine
unset INFRA_WRITERS_FENCED
mkdir -p "$INFRA_ROOT/scripts" "$INFRA_ROOT/docker/web"
cp "$ROOT/docker-compose.yml" "$INFRA_ROOT/"
cp "$ROOT/scripts/infra-update.sh" "$INFRA_ROOT/scripts/"
cp "$ROOT/docker/web/run-migrations.sh" "$INFRA_ROOT/docker/web/"
cp -r "$ROOT/postgresql" "$INFRA_ROOT/"
cat > "$INFRA_ENV_FILE" <<'EOF'
POSTGRES_USER=fixture
POSTGRES_PASSWORD=test-only-not-production
POSTGRES_DB=fixture
POSTGRES_DESIRED_VERSION=18
VALKEY_DESIRED_VERSION=9.0.0
EOF
cat > "$INFRA_OVERRIDE" <<'EOF'
services:
  web:
    ports: !override ["127.0.0.1::80"]
EOF
echo "Test project: $COMPOSE_PROJECT_NAME; evidence: $WORK"
cleanup() {
    local status=$? id name
    echo "Test exit=$status; evidence retained at $WORK"
    # No existing assets or images are removed. Prefix is generated above, not user input.
    while read -r id; do [[ -z $id ]] || docker rm -f "$id" >/dev/null; done < <(docker ps -aq --filter "name=$COMPOSE_PROJECT_NAME")
    while read -r name; do [[ -z $name ]] || docker volume rm "$name" >/dev/null; done < <(docker volume ls -q | grep "^${COMPOSE_PROJECT_NAME}[_-]" || true)
    while read -r id; do [[ -z $id ]] || docker network rm "$id" >/dev/null; done < <(docker network ls -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME")
}
trap cleanup EXIT
update() { bash "$INFRA_ROOT/scripts/infra-update.sh" update "$@"; }
dc() { bash "$INFRA_ROOT/scripts/infra-update.sh" compose "$@"; }
psql_fixture() { dc exec -T db psql -X -At -v ON_ERROR_STOP=1 -U fixture -d fixture -c "$1"; }
update --initialize
psql_fixture "CREATE ROLE retained_role; CREATE TABLE retained (id bigserial PRIMARY KEY, payload text); INSERT INTO retained(payload) VALUES ('preserved'); ALTER TABLE retained OWNER TO retained_role; SELECT setval('retained_id_seq', 100, true);"
dc exec -T valkey valkey-cli SET session:infra-test retained EX 3600
old_pg=$(jq -r .PG_VOLUME "$INFRA_STATE_DIR/active.json")
old_vk=$(jq -r .VALKEY_VOLUME "$INFRA_STATE_DIR/active.json")
# Recreate ONLY this disposable project's services as a legacy published install.
# Adoption must discover mounts/PGDATA from containers, without an active pin.
cat > "$WORK/legacy.yml" <<'EOF'
services:
  db:
    ports: ["127.0.0.1::5432"]
  valkey:
    ports: ["127.0.0.1::6379"]
EOF
export PG_IMAGE VALKEY_IMAGE WEB_IMAGE PG_VOLUME VALKEY_VOLUME PG_DATA
PG_IMAGE=$(jq -r .PG_IMAGE "$INFRA_STATE_DIR/active.json")
VALKEY_IMAGE=$(jq -r .VALKEY_IMAGE "$INFRA_STATE_DIR/active.json")
WEB_IMAGE=$(jq -r .WEB_IMAGE "$INFRA_STATE_DIR/active.json")
PG_VOLUME=$old_pg; VALKEY_VOLUME=$old_vk
PG_DATA=$(jq -r .PG_DATA "$INFRA_STATE_DIR/active.json")
docker compose -p "$COMPOSE_PROJECT_NAME" --project-directory "$INFRA_ROOT" --env-file "$INFRA_ENV_FILE" \
    -f "$INFRA_ROOT/docker-compose.yml" -f "$INFRA_OVERRIDE" -f "$WORK/legacy.yml" up -d --no-build --pull never --wait
mv "$INFRA_STATE_DIR" "$WORK/pre-adoption-state"
assert_private() {
    local name id
    for name in db valkey; do
        id=$(docker ps -aq --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" --filter "label=com.docker.compose.service=$name")
        docker inspect "$id" | jq -e '.[0] | (.HostConfig.PortBindings // {} | length)==0 and .State.Running' >/dev/null
    done
}
for name in db valkey web; do
    id=$(docker ps -aq --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" --filter "label=com.docker.compose.service=$name")
    docker inspect "$id" | jq -e '.[0].HostConfig.PortBindings | length>0' >/dev/null
done
# Unknown network/volume writers must be rejected before any downtime.
network=$(docker network ls -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME")
docker run -d --name "$COMPOSE_PROJECT_NAME-peer" --network "$network" nginx:alpine >/dev/null
if update >"$WORK/peer.log" 2>&1; then exit 1; fi
grep -q 'unexpected network peer' "$WORK/peer.log"
docker rm -f "$COMPOSE_PROJECT_NAME-peer" >/dev/null
docker run -d --name "$COMPOSE_PROJECT_NAME-writer" --network none -v "$old_pg:/foreign" nginx:alpine >/dev/null
if update >"$WORK/writer.log" 2>&1; then exit 1; fi
grep -q 'unexpected data volume user' "$WORK/writer.log"
docker rm -f "$COMPOSE_PROJECT_NAME-writer" >/dev/null
echo 'PASS unknown network and volume writer rejection'
# Inject faults only into this disposable test's subprocess, never the daemon.
mkdir -p "$WORK/bin"
export INFRA_TEST_DOCKER
INFRA_TEST_DOCKER=$(command -v docker)
cat > "$WORK/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ $1 == stop && ! -e $INFRA_TEST_FAULT_MARKER ]]; then
    touch "$INFRA_TEST_FAULT_MARKER"
    if [[ $INFRA_TEST_FAULT == term ]]; then kill -TERM "$PPID"; fi
    exit 42
fi
exec "$INFRA_TEST_DOCKER" "$@"
EOF
chmod +x "$WORK/bin/docker"
for fault in stop-failure term; do
    if PATH="$WORK/bin:$PATH" INFRA_TEST_FAULT=$fault INFRA_TEST_FAULT_MARKER="$WORK/$fault.marker" \
        update >"$WORK/$fault.log" 2>&1; then exit 1; fi
    [[ -f $WORK/$fault.marker ]]
    [[ $(jq -r .phase "$INFRA_STATE_DIR/transaction.json") == stopping ]]
    for name in db valkey web; do
        id=$(jq -r --arg name "$name" '.old[$name].Id' "$INFRA_STATE_DIR/transaction.json")
        docker inspect "$id" | jq -e '.[0] | .State.Running==false and .HostConfig.RestartPolicy.Name=="no"' >/dev/null
    done
    if dc up -d >"$WORK/$fault-resume.log" 2>&1; then exit 1; fi
    grep -q 'unfinished transaction' "$WORK/$fault-resume.log"
    bash "$INFRA_ROOT/scripts/infra-update.sh" recover
    [[ $(psql_fixture 'SELECT payload FROM retained') == preserved ]]
    [[ $(dc exec -T valkey valkey-cli GET session:infra-test) == retained ]]
    echo "PASS $fault before copy: fail closed, blocked resume, retained data and explicit recovery"
done
# Failure while adopting published legacy services must close all old endpoints.
echo 'SELECT deliberately_missing_function();' > "$INFRA_ROOT/postgresql/migrations/999_failure.sql"
if update >"$WORK/legacy-failure.log" 2>&1; then exit 1; fi
[[ $(jq -r .phase "$INFRA_STATE_DIR/transaction.json") == restored ]]
for name in db valkey web; do
    id=$(jq -r --arg name "$name" '.old[$name].Id' "$INFRA_STATE_DIR/transaction.json")
    docker inspect "$id" | jq -e '.[0] | .State.Running==false and .HostConfig.RestartPolicy.Name=="no"' >/dev/null
done
docker volume inspect "$old_pg" "$old_vk" >/dev/null
if dc up -d >"$WORK/legacy-interruption.log" 2>&1; then exit 1; fi
grep -q 'unfinished transaction' "$WORK/legacy-interruption.log"
bash "$INFRA_ROOT/scripts/infra-update.sh" recover
assert_private
[[ $(psql_fixture 'SELECT payload FROM retained') == preserved ]]
[[ $(dc exec -T valkey valkey-cli GET session:infra-test) == retained ]]
rm "$INFRA_ROOT/postgresql/migrations/999_failure.sql"
echo 'PASS published legacy adoption failure, fail closed, explicit private recovery'
# Exercise successful migration directly from published ports as well.
docker compose -p "$COMPOSE_PROJECT_NAME" --project-directory "$INFRA_ROOT" --env-file "$INFRA_ENV_FILE" \
    -f "$INFRA_ROOT/docker-compose.yml" -f "$INFRA_OVERRIDE" -f "$WORK/legacy.yml" up -d --no-build --pull never --wait
sed -i 's/POSTGRES_DESIRED_VERSION=18/POSTGRES_DESIRED_VERSION=19/; s/VALKEY_DESIRED_VERSION=9.0.0/VALKEY_DESIRED_VERSION=latest/' "$INFRA_ENV_FILE"
update
assert_private
[[ $(psql_fixture 'SHOW server_version') == 19.* ]]
[[ $(psql_fixture 'SELECT payload FROM retained') == preserved ]]
[[ $(psql_fixture "SELECT nextval('retained_id_seq')") == 101 ]]
[[ $(psql_fixture "SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='retained'::regclass") == retained_role ]]
[[ $(psql_fixture 'SELECT count(*) FROM schema_migrations') == 2 ]]
[[ $(dc exec -T valkey valkey-cli GET session:infra-test) == retained ]]
ttl=$(dc exec -T valkey valkey-cli TTL session:infra-test)
[[ $ttl -gt 0 && $ttl -lt 3600 ]]
docker volume inspect "$old_pg" "$old_vk" >/dev/null
echo 'PASS major migration, roles/owner/sequence/migrations/session TTL/old volumes'
# Same-major updates also preserve a recovery copy, even if digest did not change.
previous=$(jq -r .PG_VOLUME "$INFRA_STATE_DIR/active.json")
update
[[ $(jq -r .PG_VOLUME "$INFRA_STATE_DIR/active.json") != "$previous" ]]
docker volume inspect "$previous" >/dev/null
echo 'PASS same-major recovery copy'
# Only the desired Web image changes; unchanged data-image targets must not
# require a declaration or a special deployment path.
previous_pg_image=$(jq -r .PG_IMAGE "$INFRA_STATE_DIR/active.json")
previous_vk_image=$(jq -r .VALKEY_IMAGE "$INFRA_STATE_DIR/active.json")
DEPLOY_WEB_IMAGE=nginx:stable-alpine update
[[ $(jq -r .PG_IMAGE "$INFRA_STATE_DIR/active.json") == "$previous_pg_image" ]]
[[ $(jq -r .VALKEY_IMAGE "$INFRA_STATE_DIR/active.json") == "$previous_vk_image" ]]
[[ $(psql_fixture 'SELECT payload FROM retained') == preserved ]]
[[ $(dc exec -T valkey valkey-cli GET session:infra-test) == retained ]]
[[ $(jq -r .phase "$INFRA_STATE_DIR/transaction.json") == complete ]]
echo 'PASS Web-only desired-image update with unchanged data images and preserved data'
# Unsupported extra database must fail before stopping Web.
psql_fixture 'CREATE DATABASE unsupported_extra'
if update >"$WORK/extra-db.log" 2>&1; then exit 1; fi
grep -q 'unsupported database feature' "$WORK/extra-db.log"
psql_fixture 'DROP DATABASE unsupported_extra'
echo 'PASS extra DB rejection'
# Target-version downgrade must fail before mutation.
sed -i 's/POSTGRES_DESIRED_VERSION=19/POSTGRES_DESIRED_VERSION=18/' "$INFRA_ENV_FILE"
if update >"$WORK/downgrade.log" 2>&1; then exit 1; fi
grep -q 'downgrade refused' "$WORK/downgrade.log"
sed -i 's/POSTGRES_DESIRED_VERSION=18/POSTGRES_DESIRED_VERSION=19/' "$INFRA_ENV_FILE"
echo 'PASS downgrade rejection'
# An unavailable desired tag must never silently fall back to the running version.
sed -i 's/POSTGRES_DESIRED_VERSION=19/POSTGRES_DESIRED_VERSION=999999/' "$INFRA_ENV_FILE"
if update >"$WORK/unavailable.log" 2>&1; then exit 1; fi
[[ $(jq -r .phase "$INFRA_STATE_DIR/transaction.json") == complete ]]
[[ $(psql_fixture 'SELECT payload FROM retained') == preserved ]]
sed -i 's/POSTGRES_DESIRED_VERSION=999999/POSTGRES_DESIRED_VERSION=19/' "$INFRA_ENV_FILE"
echo 'PASS unavailable desired version fails without fallback or downtime'
# A real SQL error must propagate and leave old Web stopped; no automatic rollback.
echo 'SELECT deliberately_missing_function();' > "$INFRA_ROOT/postgresql/migrations/999_failure.sql"
if update >"$WORK/migration-failure.log" 2>&1; then exit 1; fi
[[ $(jq -r .phase "$INFRA_STATE_DIR/transaction.json") == restored ]]
web=$(docker ps -aq --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" --filter label=com.docker.compose.service=web)
[[ $(docker inspect "$web" | jq -r '.[0].State.Running') == false ]]
if dc up -d >"$WORK/interruption.log" 2>&1; then exit 1; fi
grep -q 'unfinished transaction' "$WORK/interruption.log"
echo 'PASS SQL failure and fail-closed interrupted restart'
bash "$INFRA_ROOT/scripts/infra-update.sh" recover
[[ $(psql_fixture 'SELECT payload FROM retained') == preserved ]]
[[ $(dc exec -T valkey valkey-cli GET session:infra-test) == retained ]]
echo 'PASS explicit pre-publication recovery'
# Simulate a crash after publication intent; even explicit recovery must refuse.
jq '.phase="publishing"' "$INFRA_STATE_DIR/transaction.json" > "$WORK/journal.tmp"
mv "$WORK/journal.tmp" "$INFRA_STATE_DIR/transaction.json"
if bash "$INFRA_ROOT/scripts/infra-update.sh" recover >"$WORK/post-publication.log" 2>&1; then exit 1; fi
grep -q 'recovery forbidden' "$WORK/post-publication.log"
echo 'PASS post-publication rollback forbidden'
echo 'PASS Docker integration suite'
