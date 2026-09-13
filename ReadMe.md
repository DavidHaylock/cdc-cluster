# cdc-documentdb

CDC demo system - Bun/Elysia API, a MongoDB change-stream watcher, and a MongoDB replica set, deployed locally to minikube via Helm/Skaffold.

## Prerequisites

```bash
asdf install                                          # skaffold, minikube, helm, kubectl, jq, etc. - see .tool-versions
curl -fsSL https://bun.sh/install | bash              # bun, for running apps/api and apps/watcher locally
helm repo add bitnami https://charts.bitnami.com/bitnami
```

## First run (order of play)

1. `make start-cluster` - starts minikube (profile `cdc-documentdb`), enables the ingress addon, creates the `cdc-documentdb-dev` namespace, and points kubectl at it.
2. `make watch-api` - builds the `api`/`watcher` images straight into minikube and deploys the `cdc-app` Helm chart. Watches `apps/api` for source changes and rebuilds/redeploys automatically. Leave this running in its own terminal; `Ctrl-C` tears the Helm release back down when you're done.
3. In a second terminal: `./scripts/status.sh` - confirms the minikube cluster, nodes, ingress controller, and app pods are all up.
4. In a third terminal: `./scripts/smoke-test-api.sh` - port-forwards the `api` service and exercises `POST /save` and `PATCH /items/:id`, asserting the revision counter increments.

## Shutting down

- `Ctrl-C` the `make watch-api` terminal (uninstalls the Helm release). If it was killed uncleanly instead, run `make watch-api-clean`.
- `make stop` stops minikube; `make delete` removes the profile entirely.
- MongoDB's data volume survives a Helm uninstall (faster restarts, but also masks watcher-readiness issues on a fresh deploy). For a fully clean slate, delete it before the next `make watch-api`:
  ```bash
  kubectl delete pvc datadir-cdc-app-mongodb-0 -n cdc-documentdb-dev
  ```
