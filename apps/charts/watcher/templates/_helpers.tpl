{{/* Chart name, overridable. */}}
{{- define "watcher.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name. */}}
{{- define "watcher.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "watcher.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "watcher.labels" -}}
helm.sh/chart: {{ include "watcher.chart" . }}
{{ include "watcher.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cdc-app
{{- end }}

{{- define "watcher.selectorLabels" -}}
app.kubernetes.io/name: {{ include "watcher.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
MongoDB connection string. `database.url` and `database.host` are rendered with
tpl so they can reference the release name.
*/}}
{{- define "watcher.databaseUrl" -}}
{{- $db := .Values.database -}}
{{- if $db.url -}}
{{- tpl $db.url . -}}
{{- else -}}
{{- $host := tpl $db.host . -}}
{{- printf "mongodb://%s:%v/%s?directConnection=%v&retryWrites=true&w=majority&replicaSet=%s" $host $db.port $db.name $db.directConnection $db.replicaSetName -}}
{{- end -}}
{{- end }}
