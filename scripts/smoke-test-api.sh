#!/usr/bin/env bash
# Port-forwards the api Service out of minikube, then exercises POST /save and
# PATCH /items/:id to confirm the revision-tracking flow works end to end.
#
# Defaults match the Makefile / skaffold.yaml. Override by exporting these
# before running, e.g.:
#   NAMESPACE=foo SERVICE=bar ./scripts/smoke-test-api.sh
set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-cdc-documentdb}"
NAMESPACE="${NAMESPACE:-cdc-documentdb-dev}"
SERVICE="${SERVICE:-cdc-app-api}"
REMOTE_PORT="${REMOTE_PORT:-3000}"
LOCAL_PORT="${LOCAL_PORT:-3000}"
BASE_URL="http://127.0.0.1:${LOCAL_PORT}"

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

section() { printf "\n${BOLD}${GREEN}%s${NC}\n" "$1"; }
ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "${RED}✗ %s${NC}\n" "$1"; exit 1; }

command -v kubectl >/dev/null || fail "kubectl not found"
command -v curl >/dev/null || fail "curl not found"
command -v jq >/dev/null || fail "jq not found"

section "Port-forwarding svc/${SERVICE} (namespace: ${NAMESPACE}, context: ${CLUSTER_NAME})"
PF_LOG="$(mktemp -t smoke-test-port-forward.XXXXXX)"
kubectl --context="$CLUSTER_NAME" -n "$NAMESPACE" port-forward "svc/${SERVICE}" "${LOCAL_PORT}:${REMOTE_PORT}" >"$PF_LOG" 2>&1 &
PF_PID=$!

cleanup() {
	kill "$PF_PID" >/dev/null 2>&1 || true
	wait "$PF_PID" 2>/dev/null || true
	rm -f "$PF_LOG"
}
trap cleanup EXIT

printf "Waiting for port-forward to come up"
UP=false
for _ in $(seq 1 30); do
	if curl -s -o /dev/null "$BASE_URL/"; then
		UP=true
		break
	fi
	printf "."
	sleep 1
done
echo
if [ "$UP" != true ]; then
	cat "$PF_LOG"
	fail "port-forward to svc/${SERVICE} never came up (is 'make start-cluster' / the api deployment running?)"
fi
ok "port-forward ready on ${BASE_URL}"

section "POST /save"
SAVE_RESPONSE=$(curl -s -w '\n%{http_code}' -X POST "$BASE_URL/save" \
	-H 'Content-Type: application/json' \
	-d '{"name":"smoke-test-item"}')
SAVE_STATUS=$(echo "$SAVE_RESPONSE" | tail -n1)
SAVE_JSON=$(echo "$SAVE_RESPONSE" | sed '$d')
echo "$SAVE_JSON"
[ "$SAVE_STATUS" = "200" ] || fail "POST /save returned HTTP ${SAVE_STATUS}"

ITEM_ID=$(echo "$SAVE_JSON" | jq -r '.insertedId // empty')
[ -n "$ITEM_ID" ] || fail "POST /save response had no insertedId"
ok "created item ${ITEM_ID}"

section "PATCH /items/${ITEM_ID}"
PATCH_RESPONSE=$(curl -s -w '\n%{http_code}' -X PATCH "$BASE_URL/items/${ITEM_ID}" \
	-H 'Content-Type: application/json' \
	-d '{"name":"smoke-test-item-updated"}')
PATCH_STATUS=$(echo "$PATCH_RESPONSE" | tail -n1)
PATCH_JSON=$(echo "$PATCH_RESPONSE" | sed '$d')
echo "$PATCH_JSON"
[ "$PATCH_STATUS" = "200" ] || fail "PATCH /items/${ITEM_ID} returned HTTP ${PATCH_STATUS}"

REVISION=$(echo "$PATCH_JSON" | jq -r '.revision // empty')
[ "$REVISION" = "2" ] || fail "expected revision 2 after one update, got '${REVISION}'"
ok "revision incremented to ${REVISION}"

section "All checks passed"
