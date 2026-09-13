#!/usr/bin/env bash
# Note: intentionally no `set -e` — a stopped/missing cluster makes minikube/kubectl
# exit non-zero, and we still want every section below to print rather than bail out
# after the first failure.
set -uo pipefail

# Defaults match the Makefile. Override by exporting these before running, e.g.:
#   CLUSTER_NAME=foo NAMESPACE=bar ./scripts/status.sh
CLUSTER_NAME="${CLUSTER_NAME:-cdc-documentdb}"
NAMESPACE="${NAMESPACE:-cdc-documentdb-dev}"

GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

section() {
	printf "\n${BOLD}${GREEN}%s${NC}\n" "$1"
}

section "Minikube cluster (profile: $CLUSTER_NAME)"
minikube status --profile="$CLUSTER_NAME"

section "Control plane"
kubectl cluster-info

section "Nodes"
kubectl get nodes

section "Ingress controller (namespace: ingress-nginx)"
kubectl get pods -n ingress-nginx

section "Workshop pods (namespace: $NAMESPACE)"
kubectl get pods -n "$NAMESPACE"
