#!/usr/bin/env bash
# Single Compose host, Bash 5+, jq 1.6+, GNU coreutils, util-linux flock.
set -Eeuo pipefail
umask 077

die() { echo "[infra] ERROR: $*" >&2; exit 1; }
log() { echo "[infra] $*" >&2; }
atomic() {
    local file=$1 tmp
    tmp=$(mktemp "${file}.XXXXXX")
    cat > "$tmp"
    jq -e . "$tmp" >/dev/null
    sync -f "$tmp"
    mv -f "$tmp" "$file"
    sync -f "$(dirname "$file")"
}
stable_version() {
    local text=$1
    if [[ $text =~ PostgreSQL\)?[[:space:]]+([0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ $text =~ v=([0-9]+\.[0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        die "unrecognized/nonstable version: $text"
    fi
}
no_downgrade() {
    [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1) == "$1" ]] || die "downgrade refused: $1 -> $2"
}
phase() {
    jq --arg phase "$1" '.phase=$phase' "$STATE/transaction.json" | atomic "$STATE/transaction.json"
    log "$1"
}
compose() { "${COMPOSE[@]}" "$@"; }
service() {
    local ids
    ids=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=$1")
    [[ $(wc -w <<< "$ids") -le 1 ]] || die "multiple containers for $1"
    if [[ -n $ids ]]; then docker inspect "$ids" | jq '.[0]'; else echo null; fi
}
load_active() {
    local key value
    while IFS=$'\t' read -r key value; do
        case "$key" in PG_IMAGE|VALKEY_IMAGE|WEB_IMAGE|PG_VOLUME|VALKEY_VOLUME|PG_DATA) export "$key=$value";; *) die "unknown runtime key: $key";; esac
    done < <(jq -r 'to_entries[] | [.key,.value] | @tsv' "$STATE/active.json")
}
pin_compose() {
    jq '{services:{db:{image:.PG_IMAGE,environment:{PGDATA:.PG_DATA}},valkey:{image:.VALKEY_IMAGE},web:{image:.WEB_IMAGE}},volumes:{db_data:{external:true,name:.PG_VOLUME},redis_data:{external:true,name:.VALKEY_VOLUME}}}' "$STATE/active.json" | atomic "$STATE/pinned-compose.json"
}
config_identity() {
    jq -S 'del(.services.web.image,.services.web.build,.services.db.image,.services.valkey.image,
        .services.db.environment.PGDATA,.volumes.db_data.name,.volumes.redis_data.name,."x-infra")'
}
pull_image() {
    docker pull "$1" >&2
    docker image inspect "$1" | jq -er '.[0].RepoDigests[0] | select(contains("@sha256:"))'
}
new_volume() {
    ! docker volume inspect "$1" >/dev/null 2>&1 || die "destination volume exists: $1"
    docker volume create --label "luaaidiary.transaction=$TX" "$1" >/dev/null
}
copy_volume() {
    new_volume "$2"
    docker run --rm --network none --user 0 -v "$1:/source:ro" -v "$2:/destination" \
        --entrypoint sh "$NEXT_PG" -ec 'cp -a /source/. /destination/; sync'
}
sql() {
    local container=$1 query=$2 user=${3:-$DB_USER} database=${4:-$DB_NAME}
    docker exec "$container" psql -X -At -v ON_ERROR_STOP=1 -U "$user" -d "$database" -c "$query"
}
start_pg() {
    local name=$1 image=$2 volume=$3 pgdata=$4 user=$5 initialize=${6:-no}
    local -a opts=()
    if [[ $initialize == yes ]]; then
        opts+=(-e "POSTGRES_DB=$DB_NAME" -v "$ROOT/postgresql/init:/docker-entrypoint-initdb.d:ro")
    else
        opts+=(-e POSTGRES_DB=postgres)
    fi
    docker run -d --name "$name" --network none --restart no \
        -e "PGDATA=$pgdata" -e "POSTGRES_USER=$user" -e "POSTGRES_PASSWORD=$DB_PASSWORD" \
        -v "$volume:/var/lib/postgresql" "${opts[@]}" "$image" >/dev/null
    TEMPS+=("$name")
    local i
    for ((i=0; i<120; i++)); do
        # TCP is unavailable on the entrypoint's temporary initialization server.
        if docker exec "$name" pg_isready -h 127.0.0.1 -U "$user" -d postgres >/dev/null 2>&1 &&
           sql "$name" 'SELECT 1' "$user" postgres >/dev/null 2>&1; then return; fi
        sleep 1
    done
    die "database startup timeout: $name (inspect its logs)"
}
client() {
    local container=$1; shift
    docker run --rm -i --network "container:$container" -e "PGPASSWORD=$DB_PASSWORD" "$NEXT_PG" "$@"
}
supported_db() {
    local container=$1 query database result
    result=$(sql "$container" 'SELECT rolsuper FROM pg_roles WHERE rolname=current_user')
    [[ $result == t ]] || die 'backup user must be superuser'
    for query in \
        "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname NOT IN ('postgres','$DB_NAME')" \
        "SELECT datname FROM pg_database WHERE datistemplate AND datname NOT IN ('template0','template1')" \
        "SELECT spcname FROM pg_tablespace WHERE spcname NOT IN ('pg_default','pg_global')" \
        'SELECT slot_name FROM pg_replication_slots' 'SELECT gid FROM pg_prepared_xacts' \
        'SELECT subname FROM pg_subscription' 'SELECT pubname FROM pg_publication' \
        'SELECT srvname FROM pg_foreign_server' \
        "SELECT setdatabase FROM pg_db_role_setting WHERE setdatabase<>0 AND setdatabase<>(SELECT oid FROM pg_database WHERE datname='$DB_NAME')" \
        "SELECT datname FROM pg_database WHERE datname IN ('postgres','template0','template1') AND ((datname='postgres' AND datacl IS NOT NULL) OR datdba<>10)" \
        "SELECT extname FROM pg_extension WHERE extname NOT IN ('plpgsql','pg_trgm')"; do
        result=$(sql "$container" "$query")
        [[ -z $result ]] || die "unsupported database feature: $query"
    done
    for database in postgres template1; do
        result=$(sql "$container" "SELECT nspname FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname NOT IN ('public','information_schema') UNION ALL SELECT relname FROM pg_class WHERE relnamespace='public'::regnamespace UNION ALL SELECT extname FROM pg_extension WHERE extname <> 'plpgsql' UNION ALL SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace UNION ALL SELECT typname FROM pg_type WHERE typnamespace='public'::regnamespace UNION ALL SELECT oid::text FROM pg_largeobject_metadata" "$DB_USER" "$database")
        [[ -z $result ]] || die "custom objects in $database unsupported"
    done
}
fingerprint() {
    local container=$1 object tables sequences
    sql "$container" "SELECT n.nspname,c.relname,r.rolname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_roles r ON r.oid=c.relowner WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' ORDER BY 1,2"
    sql "$container" 'SELECT extname,extversion FROM pg_extension ORDER BY 1'
    sql "$container" "SELECT rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconnlimit,rolvaliduntil,rolpassword FROM pg_authid WHERE oid=10 OR rolname !~ '^pg_' ORDER BY rolname"
    sql "$container" "SELECT r.rolname,m.rolname,g.rolname,a.admin_option,a.inherit_option,a.set_option FROM pg_auth_members a JOIN pg_roles r ON r.oid=a.roleid JOIN pg_roles m ON m.oid=a.member JOIN pg_roles g ON g.oid=a.grantor WHERE m.rolname !~ '^pg_' ORDER BY 1,2,3"
    tables=$(sql "$container" "SELECT quote_ident(schemaname)||'.'||quote_ident(tablename) FROM pg_tables WHERE schemaname !~ '^pg_' AND schemaname <> 'information_schema' ORDER BY 1")
    while IFS= read -r object; do
        [[ -n $object ]] || continue
        printf 'table:%s:' "$object"
        sql "$container" "SELECT count(*) FROM $object"
    done <<< "$tables"
    sequences=$(sql "$container" "SELECT quote_ident(sequence_schema)||'.'||quote_ident(sequence_name) FROM information_schema.sequences ORDER BY 1")
    while IFS= read -r object; do
        [[ -n $object ]] || continue
        printf 'sequence:%s:' "$object"
        sql "$container" "SELECT last_value,is_called FROM $object"
    done <<< "$sequences"
}
mount_name() {
    jq -er --arg target "$2" '[.Mounts[] | select(.Destination==$target and .Type=="volume")] | select(length==1) | .[0].Name' <<< "$1"
}
fail_closed() {
    local status=$? id
    trap - EXIT
    # Best effort on catchable interruption during fencing. Never start/rollback.
    # SIGKILL/host failure requires the durable journal's explicit recovery path.
    if (( status != 0 )) && [[ ${FENCING:-no} == yes && -f $STATE/transaction.json ]] &&
       [[ $(jq -r .phase "$STATE/transaction.json") == stopping ]]; then
        while read -r id; do
            docker update --restart=no "$id" >/dev/null 2>&1 || true
            docker stop --time 120 "$id" >/dev/null 2>&1 || true
        done < <(jq -r '.old | [.web,.db,.valkey][] | select(.!=null) | .Id' "$STATE/transaction.json")
    fi
    exit "$status"
}
assert_offline() {
    local id
    for id in "$@"; do
        docker inspect "$id" | jq -e '.[0] | .State.Running==false and
            .State.ExitCode==0 and .State.OOMKilled==false and
            .HostConfig.RestartPolicy.Name=="no"' >/dev/null || die "source not safely offline: $id"
    done
}
assert_sources_offline() {
    local id
    while read -r id; do
        assert_offline "$id"
    done < <(jq -r '.[] | select(.!=null) | .Id' <<< "$OLD")
}
stop_clean() {
    docker stop --time 120 "$1" >/dev/null
    docker inspect "$1" | jq -e '.[0].State | .ExitCode==0 and .OOMKilled==false' >/dev/null || die "unclean stop: $1"
}
recover() {
    # Explicit operator action ONLY before the publication boundary; never automatic.
    local journal=$STATE/transaction.json current old name id tx
    current=$(jq -er .phase "$journal")
    case "$current" in prepared|stopping|offline|restored|validated|switching|recovering) ;; *) die "recovery forbidden at phase $current; forward repair required";; esac
    old=$(jq -e '.old | select(.db!=null and .valkey!=null and .web!=null)' "$journal") || die 'no complete old installation to recover'
    compose config --format json | config_identity > "$STATE/recovery-config.json"
    cmp "$STATE/recovery-config.json" "$(jq -r .backup "$journal")/config-identity.json" || die 'configuration changed since update; restore original configuration before recovery'
    tx=$(jq -er .transaction "$journal")
    phase recovering
    for name in web db valkey; do
        id=$(service "$name" | jq -r '.Id // empty')
        if [[ -n $id ]]; then docker update --restart=no "$id" >/dev/null; docker stop --time 120 "$id" >/dev/null; fi
    done
    for name in "$tx-source" "$tx-target" "$tx-cache"; do
        if docker inspect "$name" >/dev/null 2>&1; then docker stop --time 120 "$name" >/dev/null; fi
    done
    # Source images/actual data mounts were recorded before any mutation.
    jq '{PG_IMAGE:.db.Image,VALKEY_IMAGE:.valkey.Image,WEB_IMAGE:.web.Image,
        PG_VOLUME:(.db.Mounts[]|select(.Destination=="/var/lib/postgresql")|.Name),
        VALKEY_VOLUME:(.valkey.Mounts[]|select(.Destination=="/data")|.Name),
        PG_DATA:(.db.Config.Env[]|select(startswith("PGDATA="))|ltrimstr("PGDATA="))}' <<< "$old" | atomic "$STATE/active.json"
    load_active; pin_compose
    COMPOSE+=(-f "$STATE/pinned-compose.json")
    compose up -d --no-deps --no-build --pull never --wait db valkey
    phase publishing-recovery
    compose up -d --no-deps --no-build --pull never --wait web
    cp "$journal" "$(jq -r .backup "$journal")/recovery.json"
    phase complete
    log 'old installation recovered; all target/backup volumes retained'
}

main() {
    local action=${1:-update}; shift || true
    local initialize=no
    [[ ${1:-} != --initialize ]] || { initialize=yes; shift; }
    for cmd in docker jq flock sync realpath sort mktemp; do command -v "$cmd" >/dev/null || die "missing dependency: $cmd"; done
    ROOT=$(realpath "${INFRA_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}")
    PROJECT=${COMPOSE_PROJECT_NAME:-luaaidiary}
    [[ $PROJECT =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die 'invalid project name'
    STATE=$(realpath -m "${INFRA_STATE_DIR:-$ROOT/../.luaaidiary-state}")
    [[ $STATE != "$ROOT" && $STATE != "$ROOT/"* ]] || die 'state must be outside checkout/release'
    mkdir -p "$STATE"; chmod 700 "$STATE"
    # One deployment Unix account per Docker host; stable project lock across release paths.
    exec 8>"/tmp/luaaidiary-${UID}-${PROJECT}.lock"
    flock -n 8 || die 'another host deployment is running'
    exec 9>"$STATE/lock"
    flock -n 9 || die 'state is locked'
    if [[ -f $STATE/transaction.json ]]; then
        [[ $action == recover || $(jq -r .phase "$STATE/transaction.json") == complete ]] || die "unfinished transaction; manual recovery required: $STATE/transaction.json"
    fi
    export PG_IMAGE=postgres:19 VALKEY_IMAGE=valkey/valkey:latest
    export PG_VOLUME=${PROJECT}_db_data VALKEY_VOLUME=${PROJECT}_redis_data PG_DATA=/var/lib/postgresql/managed
    [[ ! -f $STATE/active.json ]] || load_active
    COMPOSE=(docker compose --project-name "$PROJECT" --project-directory "$ROOT" --env-file "${INFRA_ENV_FILE:-$ROOT/.env}" -f "$ROOT/docker-compose.yml")
    local override=${INFRA_OVERRIDE:-$ROOT/docker-compose.override.yml}
    [[ ! -f $override ]] || COMPOSE+=(-f "$override")
    if [[ $action == recover ]]; then recover; return; fi
    if [[ $action == compose ]]; then
        [[ -f $STATE/active.json ]] || die 'no pinned runtime; use infra-update first'
        pin_compose
        COMPOSE+=(-f "$STATE/pinned-compose.json")
        compose "$@"; return
    fi
    [[ $action == update && $# == 0 ]] || die 'usage: infra-update.sh update [--initialize] | compose ARGS'
    # Legacy INFRA_WRITERS_FENCED values are ignored. Stop only the update targets;
    # other containers and direct writers to their volumes are not inspected.
    local config db valkey web pg_want vk_want pg_version vk_version old_pg old_vk old_data old_version image
    config=$(compose config --format json)
    jq -e '.services.db.volumes | map(select(.target=="/var/lib/postgresql")) | length==1 and .[0].type=="volume" and .[0].source=="db_data"' <<< "$config" >/dev/null || die 'DB volume override unsupported'
    jq -e '.services.valkey.volumes | map(select(.target=="/data")) | length==1 and .[0].type=="volume" and .[0].source=="redis_data"' <<< "$config" >/dev/null || die 'Valkey volume override unsupported'
    jq -e --arg pg "$PG_VOLUME" --arg vk "$VALKEY_VOLUME" '.volumes.db_data.name==$pg and .volumes.redis_data.name==$vk' <<< "$config" >/dev/null || die 'data volume name override unsupported; use actual existing containers for adoption'
    DB_USER=$(jq -er .services.db.environment.POSTGRES_USER <<< "$config")
    DB_NAME=$(jq -er .services.db.environment.POSTGRES_DB <<< "$config")
    DB_PASSWORD=$(jq -er .services.db.environment.POSTGRES_PASSWORD <<< "$config")
    [[ $DB_USER =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && $DB_NAME =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die 'configured user/database must be simple SQL identifiers'
    [[ $DB_NAME != postgres && $DB_NAME != template[01] && -n $DB_PASSWORD ]] || die 'separate application database and password required'
    db=$(service db); valkey=$(service valkey); web=$(service web)
    OLD=$(jq -n --argjson db "$db" --argjson valkey "$valkey" --argjson web "$web" '{db:$db,valkey:$valkey,web:$web}')
    if [[ $db == null ]]; then
        [[ $valkey == null && $web == null && $initialize == yes && ! -f $STATE/active.json ]] || die 'partial/missing installation; explicit initialization only for new installs'
        for image in "$PG_VOLUME" "$VALKEY_VOLUME"; do
            ! docker volume inspect "$image" >/dev/null 2>&1 || die 'unowned existing volume; refusing initialization'
        done
    else
        [[ $valkey != null && $initialize == no ]] || die 'partial/existing installation cannot be initialized'
        old_pg=$(mount_name "$db" /var/lib/postgresql)
        old_vk=$(mount_name "$valkey" /data)
        old_data=$(jq -er '.Config.Env[] | select(startswith("PGDATA=")) | ltrimstr("PGDATA=")' <<< "$db")
        [[ $old_data == /var/lib/postgresql/* && $old_data != *..* ]] || die 'unknown PGDATA'
        DB_ID=$(jq -r .Id <<< "$db"); VK_ID=$(jq -r .Id <<< "$valkey")
        old_version=$(docker exec "$DB_ID" cat "$old_data/PG_VERSION")
        [[ $old_version =~ ^[0-9]+$ ]] || die 'unknown nonempty PostgreSQL layout'
        [[ $(sql "$DB_ID" 'SHOW data_directory') == "$old_data" ]] || die 'PGDATA differs from live data directory'
        supported_db "$DB_ID"
        [[ $(sql "$DB_ID" 'SELECT oid FROM pg_roles WHERE rolname=current_user') == 10 ]] || die 'configured user must be original initdb bootstrap role'
        [[ $(docker exec "$VK_ID" valkey-cli CONFIG GET appendonly | tail -n1) == no ]] || die 'Valkey AOF is outside supported scope'
        [[ $(docker exec "$VK_ID" valkey-cli CONFIG GET dir | tail -n1) == /data ]] || die 'unknown Valkey data directory'
        [[ $(docker exec "$VK_ID" valkey-cli CONFIG GET dbfilename | tail -n1) == dump.rdb ]] || die 'nonstandard Valkey snapshot filename'
        [[ $(docker exec "$VK_ID" valkey-cli INFO replication | tr -d '\r' | grep '^role:') == role:master ]] || die 'Valkey replication unsupported'
        [[ $(docker exec "$VK_ID" valkey-cli INFO replication | tr -d '\r' | grep '^connected_slaves:') == connected_slaves:0 ]] || die 'Valkey replicas unsupported'
        [[ $(docker exec "$VK_ID" valkey-cli INFO cluster | tr -d '\r' | grep '^cluster_enabled:') == cluster_enabled:0 ]] || die 'Valkey cluster unsupported'
        docker exec "$VK_ID" valkey-cli --json MODULE LIST | jq -e 'all(.[]; .name=="lua" and .path=="lua" and .ver==1 and .args==[])' >/dev/null || die 'external Valkey modules unsupported'
    fi
    pg_want=$(jq -er '."x-infra".postgres | strings | select(length>0)' <<< "$config") || die 'missing desired PostgreSQL version'
    vk_want=$(jq -er '."x-infra".valkey | strings | select(length>0)' <<< "$config") || die 'missing desired Valkey version'
    [[ $pg_want =~ ^(latest|[0-9]+(\.[0-9]+)*)$ && $vk_want =~ ^(latest|[0-9]+(\.[0-9]+)*)$ ]] || die 'stable numeric tag or latest required'
    NEXT_PG=$(pull_image "postgres:$pg_want")
    NEXT_VK=$(pull_image "valkey/valkey:$vk_want")
    pg_version=$(stable_version "$(docker run --rm --network none "$NEXT_PG" postgres --version)")
    vk_version=$(stable_version "$(docker run --rm --network none "$NEXT_VK" valkey-server --version)")
    if [[ $db != null ]]; then
        no_downgrade "$(stable_version "$(docker exec "$DB_ID" postgres --version)")" "$pg_version"
        no_downgrade "$(stable_version "$(docker exec "$VK_ID" valkey-server --version)")" "$vk_version"
    fi
    NEXT_WEB=$(pull_image "${DEPLOY_WEB_IMAGE:-$(jq -r .services.web.image <<< "$config")}")
    if [[ -n ${DEPLOY_COMMIT:-} ]]; then
        [[ $(docker image inspect "$NEXT_WEB" | jq -r '.[0].Config.Labels["org.opencontainers.image.revision"]') == "$DEPLOY_COMMIT" ]] || die 'Web image and deployment materials are not the same commit'
    fi
    if [[ $db != null ]]; then
        # Verify TCP authentication using the target client before any service is stopped.
        client "$DB_ID" psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -c 'SELECT 1' >/dev/null
    fi
    TX=$PROJECT-$(date -u +%Y%m%dT%H%M%S)-$(cat /proc/sys/kernel/random/uuid | cut -c1-8)
    BACKUP=$STATE/$TX; mkdir -m 700 "$BACKUP"
    TARGET=$TX-target; CACHE=$TX-cache; TEMPS=()
    NEW_PG=$TX-db; NEW_VK=$TX-valkey
    jq -n --argjson old "$OLD" --arg tx "$TX" --arg pg "$pg_want" --arg vk "$vk_want" \
        --arg pgv "$pg_version" --arg vkv "$vk_version" --arg backup "$BACKUP" \
        --arg pgimage "$NEXT_PG" --arg vkimage "$NEXT_VK" --arg webimage "$NEXT_WEB" \
        --arg pgvolume "$NEW_PG" --arg vkvolume "$NEW_VK" \
        '{phase:"prepared",transaction:$tx,old:$old,backup:$backup,desired:{postgres:$pg,valkey:$vk},versions:{postgres:$pgv,valkey:$vkv},target:{PG_IMAGE:$pgimage,VALKEY_IMAGE:$vkimage,WEB_IMAGE:$webimage,PG_VOLUME:$pgvolume,VALKEY_VOLUME:$vkvolume,PG_DATA:"/var/lib/postgresql/managed"}}' | atomic "$STATE/transaction.json"
    [[ ! -f $STATE/active.json ]] || cp "$STATE/active.json" "$BACKUP/previous.json"
    cp "$STATE/transaction.json" "$BACKUP/prepared.json"
    config_identity <<< "$config" > "$BACKUP/config-identity.json"
    # Keep old image IDs addressable after Compose replaces their containers.
    for name in db valkey web; do
        image=$(jq -r --arg name "$name" '.[$name].Image // empty' <<< "$OLD")
        [[ -z $image ]] || docker tag "$image" "luaaidiary-retained:$TX-$name"
    done
    sync -f "$BACKUP"
    FENCING=yes
    phase stopping
    local id name source
    while read -r id; do docker update --restart=no "$id" >/dev/null; done < <(jq -r '.[] | select(.!=null) | .Id' <<< "$OLD")
    if [[ $web != null ]]; then stop_clean "$(jq -r .Id <<< "$web")"; fi
    if [[ $db != null ]]; then
        [[ $(docker exec "$VK_ID" valkey-cli SAVE) == OK ]] || die 'Valkey SAVE failed'
        stop_clean "$DB_ID"; stop_clean "$VK_ID"
        assert_sources_offline
        phase offline
        source=$TX-source
        copy_volume "$old_pg" "$source"
        copy_volume "$old_vk" "$NEW_VK"
        start_pg "$source" "$(jq -r .Image <<< "$db")" "$source" "$old_data" "$DB_USER"
        supported_db "$source"
        fingerprint "$source" > "$BACKUP/validation.before"
        client "$source" pg_dumpall -h 127.0.0.1 -U "$DB_USER" --globals-only > "$BACKUP/globals.sql"
        client "$source" pg_dump -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -Fc --create > "$BACKUP/database.dump"
        (cd "$BACKUP" && sha256sum globals.sql database.dump > SHA256SUMS)
        sync -f "$BACKUP"
        new_volume "$NEW_PG"
        start_pg "$TARGET" "$NEXT_PG" "$NEW_PG" /var/lib/postgresql/managed "$DB_USER"
        # initdb's bootstrap role owns pinned system objects and cannot be reassigned.
        # Keep exactly that role; restore ALL of its ALTERs, grants and memberships.
        awk -v role="$DB_USER" '
            $0=="CREATE ROLE " role ";" || $0=="CREATE ROLE \"" role "\";" {n++; next}
            {print}
            END {if (n!=1) exit 1}
        ' "$BACKUP/globals.sql" > "$BACKUP/globals.restore.sql"
        client "$TARGET" psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$DB_USER" -d postgres < "$BACKUP/globals.restore.sql" > "$BACKUP/roles-restore.log"
        client "$TARGET" pg_restore --exit-on-error --create -h 127.0.0.1 -U "$DB_USER" -d postgres < "$BACKUP/database.dump"
        fingerprint "$TARGET" > "$BACKUP/validation.after"
        cmp "$BACKUP/validation.before" "$BACKUP/validation.after" || die 'restored rows/sequences/owners/extensions differ'
    else
        new_volume "$NEW_PG"; new_volume "$NEW_VK"
        start_pg "$TARGET" "$NEXT_PG" "$NEW_PG" /var/lib/postgresql/managed "$DB_USER" yes
    fi
    phase restored
    docker run --rm --network "container:$TARGET" \
        -e POSTGRES_HOST=127.0.0.1 -e POSTGRES_PORT=5432 -e "POSTGRES_USER=$DB_USER" \
        -e "POSTGRES_DB=$DB_NAME" -e "POSTGRES_PASSWORD=$DB_PASSWORD" -e MIGRATIONS_DIR=/migrations \
        -v "$ROOT/postgresql/migrations:/migrations:ro" -v "$ROOT/docker/web/run-migrations.sh:/migrate.sh:ro" \
        --entrypoint sh "$NEXT_PG" /migrate.sh > "$BACKUP/migrations.log" 2>&1
    docker run -d --name "$CACHE" --network none --restart no -v "$NEW_VK:/data" "$NEXT_VK" >/dev/null
    TEMPS+=("$CACHE")
    local ready=no i
    for ((i=0; i<60; i++)); do
        if [[ $(docker exec "$CACHE" valkey-cli PING 2>/dev/null || true) == PONG ]]; then ready=yes; break; fi
        sleep 1
    done
    [[ $ready == yes ]] || die 'restored Valkey did not become ready'
    for name in "${TEMPS[@]}"; do stop_clean "$name"; done
    # Recheck the originals after the entire isolated migration, before changing
    # runtime pins or allowing Compose to replace any original container.
    assert_sources_offline
    phase validated
    jq .target "$STATE/transaction.json" | atomic "$STATE/active.json"
    load_active
    pin_compose
    COMPOSE+=(-f "$STATE/pinned-compose.json")
    phase switching
    compose up -d --no-deps --no-build --pull never --wait db valkey
    # Durable point of no automatic return, BEFORE anything can accept Web traffic.
    phase publishing
    compose up -d --no-deps --no-build --pull never --wait web
    phase complete
    cp "$STATE/transaction.json" "$BACKUP/transaction.json"
    for name in "${TEMPS[@]}"; do docker rm "$name" >/dev/null; done # never -v
    log "complete; retained backups and old volumes: $BACKUP"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    trap fail_closed EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'echo "[infra] stopped; do not bypass an unfinished journal. See docs/infra-updates.md" >&2' ERR
    main "$@"
fi
