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
# Image inspection is stubbed; Compose config never contacts the Docker daemon.
docker() {
    if [[ $1 == image && $2 == inspect ]]; then
        [[ $3 == "$(jq -r .WEB_IMAGE "$STATE/active.json")" ]]
        jq -n --arg version "$fixture_version" '[{Config:{Env:[("APP_VERSION="+$version)]}}]'
    else
        command docker "$@"
    fi
}
export PG_IMAGE=fixture:pg VALKEY_IMAGE=fixture:vk PG_DATA=/var/lib/postgresql/managed
export PG_VOLUME=fixture_pg VALKEY_VOLUME=fixture_vk
export POSTGRES_USER=fixture POSTGRES_DB=fixture POSTGRES_PASSWORD=fixture
jq -n '{PG_IMAGE:env.PG_IMAGE,VALKEY_IMAGE:env.VALKEY_IMAGE,PG_DATA:env.PG_DATA,
    PG_VOLUME:env.PG_VOLUME,VALKEY_VOLUME:env.VALKEY_VOLUME,WEB_IMAGE:"fixture:new"}' > "$STATE/active.json"
for style in mapping list; do
    jq '.WEB_IMAGE="fixture:new"' "$STATE/active.json" | atomic "$STATE/active.json"
    if [[ $style == mapping ]]; then
        printf 'services:\n  web:\n    dns: [1.1.1.1]\n    environment:\n      APP_VERSION: 0.7.3\n' > "$tmp/override.yml"
    else
        printf 'services:\n  web:\n    dns: [1.1.1.1]\n    environment:\n      - APP_VERSION=0.7.3\n' > "$tmp/override.yml"
    fi
    for fixture_version in 0.8.1 0.7.2 'quoted: "version"'; do
        if [[ $fixture_version == 0.7.2 ]]; then
            jq '.WEB_IMAGE="fixture:old"' "$STATE/active.json" | atomic "$STATE/active.json"
        fi
        pin_compose
        docker compose --env-file /dev/null -f "$ROOT/docker-compose.yml" -f "$tmp/override.yml" \
            -f "$STATE/pinned-compose.json" config --format json > "$tmp/resolved.json"
        jq -e --arg version "$fixture_version" --arg image "$(jq -r .WEB_IMAGE "$STATE/active.json")" \
            '.services.web | .environment.APP_VERSION==$version and .image==$image and .dns==["1.1.1.1"]' "$tmp/resolved.json" >/dev/null
    done
    ok "$style environment: image version, old snapshot/recovery image, quoting and DNS retained"
done
config_identity < "$tmp/resolved.json" > "$tmp/identity.json"
jq '.services.web.environment.APP_VERSION="0.7.3"' "$tmp/resolved.json" | config_identity > "$tmp/old-identity.json"
cmp "$tmp/identity.json" "$tmp/old-identity.json"
ok 'recovery identity ignores managed version but retains user settings'
echo "PASS $count unit checks"
