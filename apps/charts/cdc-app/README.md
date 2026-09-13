# cdc-app

Umbrella chart for the CDC demo: the **api** service (Deployment + Service, templated here),
the **watcher** change-stream worker (local subchart at `../watcher`), and **MongoDB**
(bitnami/mongodb subchart, `architecture: replicaset` because change streams require a
replica set).

```sh
helm dependency update apps/charts/cdc-app
helm install cdc apps/charts/cdc-app \
  --set api.image.repository=<registry>/api --set api.image.tag=<tag> \
  --set watcher.image.repository=<registry>/watcher --set watcher.image.tag=<tag>
```

The `api` and `watcher` images are placeholders: build `apps/api/Dockerfile` and
`apps/watcher/Dockerfile` and push them to a registry before installing.

MongoDB auth is **disabled by default** (`mongodb.auth.enabled: false`) because the apps'
connection strings carry no credentials; enabling it means adding user/password to
`database.url` and `watcher.database.url`.
