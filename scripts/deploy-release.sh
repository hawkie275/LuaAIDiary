#!/usr/bin/env bash
# Stage image-matching materials; use the updater from the workflow checkout.
set -Eeuo pipefail
umask 077
for command in git docker bash jq flock sync tar realpath; do
    command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
: "${DEPLOY_PATH:?Set an absolute durable deployment directory outside Actions checkout}"
: "${DEPLOY_WEB_IMAGE:?Set the released Web image}"
[[ $DEPLOY_PATH == /* ]] || { echo 'DEPLOY_PATH must be absolute' >&2; exit 1; }
checkout=$(git rev-parse --show-toplevel)
deploy=$(realpath -m "$DEPLOY_PATH")
[[ $deploy != "$checkout" && $deploy != "$checkout/"* ]] || { echo 'DEPLOY_PATH must be outside checkout' >&2; exit 1; }
[[ -f $deploy/.env ]] || { echo "Provision $deploy/.env before deploying" >&2; exit 1; }
export DEPLOY_COMMIT
DEPLOY_COMMIT=$(git rev-parse "${DEPLOY_RELEASE_REF:-HEAD}^{commit}")
: "${COMPOSE_PROJECT_NAME:?Set the deployment Compose project}"
export COMPOSE_PROJECT_NAME
export INFRA_STATE_DIR=$deploy/state INFRA_ENV_FILE=$deploy/.env
export INFRA_OVERRIDE=$deploy/docker-compose.override.yml
mkdir -p "$deploy/releases"
release=$(mktemp -d "$deploy/releases/${DEPLOY_COMMIT}.XXXXXX")
# Never copy the checkout's .env/override, never overwrite a user's override.
git archive "$DEPLOY_COMMIT" docker-compose.yml scripts docker/web postgresql | tar -x -C "$release"
cp "$checkout/scripts/infra-update.sh" "$release/scripts/infra-update.sh"
export INFRA_ROOT=$release
bash "$release/scripts/infra-update.sh" update
# The runtime journal is authoritative; this pointer is convenience only.
link=$deploy/.current-$(basename "$release")
ln -s "$release" "$link"
mv -Tf "$link" "$deploy/current"
sync -f "$deploy"
