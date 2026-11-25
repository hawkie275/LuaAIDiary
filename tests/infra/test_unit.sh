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
echo "PASS $count unit checks"
