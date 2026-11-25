#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$ROOT/scripts/infra-update.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
count=0
ok() { count=$((count+1)); echo "ok $count - $*"; }
reject() { if ( "$@" ) >"$tmp/error" 2>&1; then echo "expected rejection: $*"; exit 1; fi; }
[[ $(stable_version 'postgres (PostgreSQL) 19.1 (Debian)') == 19.1 ]]; ok 'PG stable version'
[[ $(stable_version 'Valkey server v=9.0.1 sha=abc') == 9.0.1 ]]; ok 'Valkey stable version'
reject stable_version 'postgres (PostgreSQL) 20beta1'; ok 'reject prerelease'
reject stable_version 'Valkey server v=10.0.0-rc1 sha=abc'; ok 'reject Valkey prerelease'
no_downgrade 19.1 20.0; ok 'no dedicated major branch'
no_downgrade 19.9 19.10; ok 'numeric minor ordering'
reject no_downgrade 19.1 18.9; ok 'reject major downgrade'
reject no_downgrade 19.2 19.1; ok 'reject minor downgrade'
echo '{"phase":"restored"}' | atomic "$tmp/state.json"
[[ $(jq -r .phase "$tmp/state.json") == restored ]]; ok 'atomic state'
STATE=$tmp
cp "$tmp/state.json" "$tmp/transaction.json"
phase validated
[[ $(jq -r .phase "$tmp/transaction.json") == validated ]]; ok 'durable phase'
reject mount_name '{"Mounts":[{"Destination":"/data","Type":"bind"}]}' /data; ok 'reject bind data'
[[ $(mount_name '{"Mounts":[{"Destination":"/data","Type":"volume","Name":"actual"}]}' /data) == actual ]]; ok 'actual named volume'
# A failing SQL command must not be interpreted as an empty unsupported-feature result.
sql() { return 42; }
reject bash -c "source '$ROOT/scripts/infra-update.sh'; DB_USER=x; DB_NAME=x; sql() { return 42; }; supported_db fixture"; ok 'SQL failure propagates'
env COMPOSE_PROJECT_NAME=unit-"$$" INFRA_STATE_DIR="$tmp/state" INFRA_ENV_FILE="$ROOT/.env.example" \
    bash "$ROOT/scripts/infra-update.sh" compose up >"$tmp/out" 2>&1 && exit 1
grep -q 'no pinned runtime' "$tmp/out"; ok 'normal startup refuses unpinned runtime'
mkdir -p "$tmp/unfinished"
echo '{"phase":"publishing"}' > "$tmp/unfinished/transaction.json"
env COMPOSE_PROJECT_NAME=unit-"$$" INFRA_STATE_DIR="$tmp/unfinished" \
    bash "$ROOT/scripts/infra-update.sh" update >"$tmp/out" 2>&1 && exit 1
grep -q 'unfinished transaction' "$tmp/out"; ok 'interruption refuses automatic resume/rollback'
(
    exec 8>"/tmp/luaaidiary-${UID}-unit-$$.lock"
    flock -n 8
    env COMPOSE_PROJECT_NAME=unit-"$$" INFRA_STATE_DIR="$tmp/lock-test" \
        bash "$ROOT/scripts/infra-update.sh" update >"$tmp/out" 2>&1 && exit 1
    grep -q 'another host deployment' "$tmp/out"
)
ok 'host lock blocks another state directory'
reject bash -c "source '$ROOT/scripts/infra-update.sh'; new_volume() { :; }; docker() { return 23; }; NEXT_PG=fixture; copy_volume source target"
ok 'volume copy failure propagates'
reject bash -c "source '$ROOT/scripts/infra-update.sh'; docker() { return 24; }; pull_image postgres:999999"
ok 'pull failure propagates without fallback'
# Offline boundary rejects running, killed, or automatically restarting sources.
offline='[{"State":{"Running":false,"ExitCode":0,"OOMKilled":false},"HostConfig":{"RestartPolicy":{"Name":"no"}}}]'
docker() { printf '%s\n' "$offline"; }
assert_offline fixture; ok 'clean stopped source accepted'
offline=$(jq '.[0].State.Running=true' <<< "$offline")
reject assert_offline fixture; ok 'running source rejected before copy'
offline=$(jq '.[0].State.Running=false | .[0].HostConfig.RestartPolicy.Name="always"' <<< "$offline")
reject assert_offline fixture; ok 'restart-enabled source rejected before copy'
unset -f docker
OLD='{"web":{"Id":"web"},"db":{"Id":"db"},"valkey":{"Id":"cache"}}'
# Invoked indirectly by assert_sources_offline through reject.
# shellcheck disable=SC2329
docker() {
    if [[ $2 == web ]]; then
        echo '[{"State":{"Running":true,"ExitCode":0,"OOMKilled":false},"HostConfig":{"RestartPolicy":{"Name":"no"}}}]'
    else
        echo '[{"State":{"Running":false,"ExitCode":0,"OOMKilled":false},"HostConfig":{"RestartPolicy":{"Name":"no"}}}]'
    fi
}
reject assert_sources_offline; ok 'restarted Web rejected at final source boundary'
# shellcheck disable=SC2329
docker() { echo '[{"State":{"Running":false,"ExitCode":0,"OOMKilled":true},"HostConfig":{"RestartPolicy":{"Name":"no"}}}]'; }
reject assert_sources_offline; ok 'OOM source rejected at final source boundary'
unset -f docker
reject bash -c "source '$ROOT/scripts/infra-update.sh'; docker() { return 26; }; stop_clean fixture"
ok 'stop command failure propagates'
reject bash -c "source '$ROOT/scripts/infra-update.sh'; docker() { echo '[{\"State\":{\"ExitCode\":137,\"OOMKilled\":false}}]'; }; stop_clean fixture"
ok 'forced termination is not a clean stop'
reject bash -c "source '$ROOT/scripts/infra-update.sh'; docker() { return 25; }; guard_volume_users fixture"
ok 'volume-user inspection failure propagates'
# Cleanup must only act when this process owns the fencing stage, never on a
# second deployment rejected by the lock or an unfinished journal.
mkdir -p "$tmp/fencing"
echo '{"phase":"stopping","old":{"web":{"Id":"web"},"db":{"Id":"db"},"valkey":{"Id":"cache"}}}' > "$tmp/fencing/transaction.json"
export FENCE_TEST_LOG=$tmp/fence.log
reject bash -c "source '$ROOT/scripts/infra-update.sh'; STATE='$tmp/fencing'; FENCING=yes; docker() { echo \"\$*\" >> \"\$FENCE_TEST_LOG\"; }; trap fail_closed EXIT; exit 17"
[[ $(grep -c '^stop --time 120 ' "$FENCE_TEST_LOG") == 3 ]]
ok 'fencing failure stops all three services without starting rollback'
rm "$FENCE_TEST_LOG"
reject bash -c "source '$ROOT/scripts/infra-update.sh'; STATE='$tmp/fencing'; FENCING=yes; docker() { echo \"\$*\" >> \"\$FENCE_TEST_LOG\"; }; trap fail_closed EXIT; trap 'exit 143' TERM; kill -TERM \$\$"
[[ $(grep -c '^stop --time 120 ' "$FENCE_TEST_LOG") == 3 ]]
ok 'TERM during fencing stops all three services and never publishes'
rm "$FENCE_TEST_LOG"
reject bash -c "source '$ROOT/scripts/infra-update.sh'; STATE='$tmp/fencing'; docker() { echo called >> \"\$FENCE_TEST_LOG\"; }; trap fail_closed EXIT; exit 17"
[[ ! -e $FENCE_TEST_LOG ]]; ok 'non-owner failure never stops another deployment'
echo "PASS: $count unit/failure checks"
