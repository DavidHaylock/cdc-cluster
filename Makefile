CLUSTER_NAME ?= cdc-documentdb
MINIKUBE_MEMORY ?= 4096
MINIKUBE_CPUS ?= 4
APP_NAME ?= app
NAMESPACE ?= cdc-documentdb-dev
HELM_CHART_PATH = _k8s/charts/$(APP_NAME)

GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[0;33m
NC := \033[0m

INFO := printf "$(GREEN)✓$(NC) %s\n"
WARN := printf "$(YELLOW)⚠$(NC) %s\n"
ERROR := printf "$(RED)✗$(NC) %s\n"

# Export variables for use in all targets
export AWS_ENDPOINT_URL = http://localhost:4566
export AWS_ACCESS_KEY_ID = test
export AWS_SECRET_ACCESS_KEY = test
export AWS_DEFAULT_REGION = us-east-1

start-cluster: ### [Step 1] Start minikube cluster
	$(INFO) "Starting minikube cluster..."
	minikube start --driver=docker \
		--memory=$(MINIKUBE_MEMORY) \
		--cpus=$(MINIKUBE_CPUS) \
		--profile=$(CLUSTER_NAME) \
		--kubernetes-version=v1.32.0
	$(INFO) "Waiting for cluster API server to be ready..."
	kubectl wait --for=condition=ready node --all --timeout=300s 2>/dev/null || true
	@sleep 5
	$(INFO) "Enabling ingress addon..."
	minikube addons enable ingress --profile=$(CLUSTER_NAME)
	$(INFO) "Waiting for ingress controller to be ready..."
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller,app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s 2>/dev/null || true
	kubectl create namespace $(NAMESPACE) || true
	kubectl config set-context $(CLUSTER_NAME) --namespace=$(NAMESPACE)
	$(INFO) "Cluster is ready"
	$(WARN) "Run 'make tunnel' in a separate terminal to reach ingress/LoadBalancer services from your Mac"

tunnel: ### Route macOS to minikube's LoadBalancer/ingress (needs sudo, keep running in a separate terminal)
	$(INFO) "Starting minikube tunnel (requires sudo, leave this running)..."
	minikube tunnel --profile=$(CLUSTER_NAME)

stop: ### Stop minikube cluster
	$(INFO) "Stopping minikube cluster..."
	minikube stop --profile=$(CLUSTER_NAME)

delete: ### Delete minikube cluster
	$(INFO) "Delete minikube cluster..."
	minikube delete --profile=$(CLUSTER_NAME)

status: ### [Step 1] Watch cluster status, refreshing every 2s (Ctrl+C to stop)
	@CLUSTER_NAME=$(CLUSTER_NAME) NAMESPACE=$(NAMESPACE) watch -n 2 -c ./scripts/status.sh

SKAFFOLD_FILE ?= skaffold.yaml

check-cluster: ### Fail fast if the minikube cluster isn't running
	@minikube status --profile=$(CLUSTER_NAME) >/dev/null 2>&1 || { \
		$(ERROR) "minikube profile '$(CLUSTER_NAME)' is not running - run 'make start-cluster' first"; \
		exit 1; \
	}

watch-api: check-cluster ### [Step 2] Live rebuild+redeploy of apps/api into the running cluster (Ctrl+C to tear down)
	$(INFO) "Deploying cdc-app to $(CLUSTER_NAME)/$(NAMESPACE) and watching apps/api for changes..."
	$(WARN) "Edit apps/api/src/index.ts to trigger a rebuild. Ctrl+C stops the loop and removes the release."
	skaffold dev \
		--filename=$(SKAFFOLD_FILE) \
		--kube-context=$(CLUSTER_NAME) \
		--namespace=$(NAMESPACE) \
		--port-forward=user \
		--tail

watch-api-clean: ### Remove whatever 'make watch-api' deployed (use if skaffold was killed uncleanly)
	$(INFO) "Deleting skaffold-managed release from $(CLUSTER_NAME)/$(NAMESPACE)..."
	skaffold delete \
		--filename=$(SKAFFOLD_FILE) \
		--kube-context=$(CLUSTER_NAME) \
		--namespace=$(NAMESPACE)

API_DIR := ../../applications/api
API_IMAGE := api:latest

ECR_REPO := api
API_ECR_IMAGE := $(ECR_REPO):latest

REPORT_DIR        := ../../applications/report
REPORT_IMAGE      := report:latest
REPORTS_LOCAL_DIR ?= reports
REPORT_JOB_NAME   ?= weather-report-manual

build:
	docker compose build

run: build
	docker compose up